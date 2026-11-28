-- Sprint 4 | Volunteer ratings (US1 rate a volunteer, US2 view ratings).
--
-- Apply after 20261021_account_blocking.sql, 20261105000000_chat_end_reactions.sql
-- (support_requests.ended_at) and 20261106100000_admin_report_management.sql
-- (support_requests.restricted_at). Repeatable. Adds new objects only; no
-- existing table, function or policy is changed.
--
-- Rules (enforced here, not in the app):
--  * Only the help seeker of a conversation can rate its volunteer, once per
--    conversation. The rating is kept if the chat is reopened. The rater may
--    correct it once, within maak_rating_correction_window() of submitting;
--    after that it is final.
--  * The conversation must count as completed support: accepted, ended by a
--    participant, not restricted by an administrator, and the volunteer sent
--    at least one message in it (see maak_request_had_support).
--  * Members read only their own ratings. Everyone else sees an aggregate:
--    the count, and the average once there are enough ratings that no single
--    help seeker's score can be singled out (maak_rating_min_for_average).
--  * Writes go only through rate_maak_volunteer and correct_maak_rating.
begin;
set local lock_timeout = '10s';

create table if not exists public.volunteer_ratings (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.support_requests(id) on delete cascade,
  seeker_id uuid not null references auth.users(id) on delete cascade,
  volunteer_id uuid not null references auth.users(id) on delete cascade,
  stars smallint not null check (stars between 1 and 5),
  created_at timestamptz not null default now(),
  -- Set by the one allowed correction; a corrected rating cannot change again.
  corrected_at timestamptz,
  check (seeker_id <> volunteer_id),
  check (corrected_at is null or corrected_at >= created_at)
);
create index if not exists volunteer_ratings_by_volunteer on public.volunteer_ratings(volunteer_id);

alter table public.volunteer_ratings enable row level security;
drop policy if exists volunteer_ratings_read_own on public.volunteer_ratings;
create policy volunteer_ratings_read_own on public.volunteer_ratings for select to authenticated
  using (seeker_id = auth.uid() and (select public.is_maak_active()));
revoke all on public.volunteer_ratings from anon, authenticated;
grant select on public.volunteer_ratings to authenticated;

-- A blocked account cannot write here, same as the other member tables.
drop trigger if exists maak_blocked_actor_guard on public.volunteer_ratings;
create trigger maak_blocked_actor_guard before insert or update or delete on public.volunteer_ratings
  for each row execute function public.guard_maak_blocked_actor();

-- Ratings need this many before an average is shown (count is always shown).
create or replace function public.maak_rating_min_for_average() returns integer
language sql immutable set search_path = public, pg_temp as $$ select 3 $$;

-- How long after submitting a help seeker may make their one correction.
create or replace function public.maak_rating_correction_window() returns interval
language sql immutable set search_path = public, pg_temp as $$ select interval '24 hours' $$;

-- The volunteer can still receive rating changes (approved and not blocked).
create or replace function public.maak_rateable_volunteer(p_volunteer_id uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select not public.is_maak_account_blocked(p_volunteer_id)
    and exists (select 1 from volunteer_profiles v where v.user_id = p_volunteer_id and v.status = 'approved');
$$;
revoke all on function public.maak_rateable_volunteer(uuid) from public, anon, authenticated;

-- Completed support: the single definition used by ratings (and later badges).
create or replace function public.maak_request_had_support(p_request_id uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from support_requests r
    where r.id = p_request_id and r.status = 'accepted'
      and r.ended_at is not null and r.restricted_at is null
      and exists (select 1 from messages m where m.request_id = r.id and m.sender_id = r.volunteer_id)
  );
$$;
revoke all on function public.maak_request_had_support(uuid) from public, anon, authenticated;

-- Why the caller can or cannot rate this conversation. Internal.
create or replace function public.maak_rating_state(p_request_id uuid) returns text
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare r support_requests;
begin
  select * into r from support_requests where id = p_request_id;
  if not found or auth.uid() is null or auth.uid() not in (r.seeker_id, r.volunteer_id) then return 'unavailable'; end if;
  if auth.uid() <> r.seeker_id then return 'not_seeker'; end if;
  if exists (select 1 from volunteer_ratings v where v.request_id = r.id) then return 'rated'; end if;
  if r.restricted_at is not null then return 'restricted'; end if;
  if r.status <> 'accepted' or r.ended_at is null then return 'not_ended'; end if;
  if not public.maak_request_had_support(r.id) then return 'no_support'; end if;
  if not public.is_maak_active() or not public.maak_rateable_volunteer(r.volunteer_id)
    then return 'unavailable'; end if;
  return 'eligible';
end; $$;
revoke all on function public.maak_rating_state(uuid) from public, anon, authenticated;

-- The caller may still correct their rating of this conversation. Internal.
create or replace function public.maak_can_correct_rating(p_request_id uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_maak_active() and exists (
    select 1 from volunteer_ratings v
    where v.request_id = p_request_id and v.seeker_id = auth.uid()
      and v.corrected_at is null
      and now() < v.created_at + public.maak_rating_correction_window()
      and public.maak_rateable_volunteer(v.volunteer_id)
  );
$$;
revoke all on function public.maak_can_correct_rating(uuid) from public, anon, authenticated;

-- The help seeker's rating state for one conversation:
-- {state, stars, volunteer_id, can_correct, correct_until, correction_window_seconds}.
-- The app words its deadline only from these values, never from a constant.
create or replace function public.my_maak_rating(p_request_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare st text; v volunteer_ratings; can boolean;
begin
  if auth.uid() is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
  st := public.maak_rating_state(p_request_id);
  if st in ('unavailable', 'not_seeker') then return jsonb_build_object('state', st); end if;
  select * into v from volunteer_ratings where request_id = p_request_id;
  can := st = 'rated' and public.maak_can_correct_rating(p_request_id);
  return jsonb_build_object('state', st,
    'stars', v.stars,
    'volunteer_id', (select volunteer_id from support_requests where id = p_request_id),
    'can_correct', can,
    'correct_until', case when can then v.created_at + public.maak_rating_correction_window() end,
    'correction_window_seconds', extract(epoch from public.maak_rating_correction_window())::int);
end; $$;

-- US1: submit a 1-5 star rating for a completed conversation.
create or replace function public.rate_maak_volunteer(p_request_id uuid, p_stars integer) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me uuid := auth.uid(); r support_requests; st text;
begin
  if me is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
  if p_stars is null or p_stars not between 1 and 5 then raise exception 'invalid_rating'; end if;
  -- FOR SHARE: a reopen (which clears ended_at) cannot pass this check concurrently.
  select * into r from support_requests where id = p_request_id for share;
  st := public.maak_rating_state(p_request_id);
  if st = 'rated' then raise exception 'already_rated'; end if;
  if st <> 'eligible' then raise exception 'rating_not_allowed'; end if;
  begin
    insert into volunteer_ratings(request_id, seeker_id, volunteer_id, stars)
      values (r.id, me, r.volunteer_id, p_stars);
  exception when unique_violation then raise exception 'already_rated';
  end;
  return public.my_maak_rating(p_request_id);
end; $$;

-- US1: the one correction of a submitted rating. Never creates a new rating.
create or replace function public.correct_maak_rating(p_request_id uuid, p_stars integer) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me uuid := auth.uid(); v volunteer_ratings;
begin
  if me is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
  if p_stars is null or p_stars not between 1 and 5 then raise exception 'invalid_rating'; end if;
  -- FOR UPDATE: two corrections sent at once cannot both pass the check.
  select * into v from volunteer_ratings where request_id = p_request_id and seeker_id = me for update;
  if not found then raise exception 'rating_not_found'; end if;
  if not public.maak_can_correct_rating(p_request_id) then raise exception 'correction_not_allowed'; end if;
  if v.stars = p_stars then raise exception 'rating_unchanged'; end if;
  update volunteer_ratings set stars = p_stars, corrected_at = now() where id = v.id;
  return public.my_maak_rating(p_request_id);
end; $$;

-- US2: public summary for up to 100 approved, active volunteers. One row per
-- requested volunteer: {volunteer_id, rating_count, average_rating|null}.
create or replace function public.maak_volunteer_stats(p_volunteer_ids uuid[]) returns setof jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
  if coalesce(cardinality(p_volunteer_ids), 0) > 100 then raise exception 'too_many_volunteers'; end if;
  return query
  select jsonb_build_object('volunteer_id', v.user_id, 'rating_count', coalesce(s.n, 0),
           'average_rating', case when coalesce(s.n, 0) >= public.maak_rating_min_for_average()
                                  then round(s.avg_stars, 1) end)
  from (select distinct unnest(p_volunteer_ids) as id) ids
  join volunteer_profiles v on v.user_id = ids.id and v.status = 'approved'
  left join lateral (select count(*)::int as n, avg(stars)::numeric as avg_stars
                     from volunteer_ratings x where x.volunteer_id = v.user_id) s on true
  where not public.is_maak_account_blocked(v.user_id);
end; $$;

do $$ declare f text; begin
  foreach f in array array['my_maak_rating(uuid)', 'rate_maak_volunteer(uuid,integer)',
                           'correct_maak_rating(uuid,integer)', 'maak_volunteer_stats(uuid[])'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public.maak_rating_min_for_average(), public.maak_rating_correction_window() from public, anon;
grant execute on function public.maak_rating_min_for_average(), public.maak_rating_correction_window() to authenticated;

notify pgrst, 'reload schema';
commit;
