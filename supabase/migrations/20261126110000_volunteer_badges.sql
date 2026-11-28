-- Sprint 4 | Volunteer achievement badges (US3 earn, US4 view).
--
-- Apply after 20261126100000_volunteer_ratings.sql. Repeatable; re-running it
-- never overwrites thresholds an administrator has changed, and never adds
-- or changes a completion that is already recorded.
--
-- Badges recognise participation on Ma'ak. They are not a medical
-- qualification and say nothing about the quality of support.
--
-- Participation credit
--  * volunteer_support_completions keeps one row per conversation, written by
--    the server the FIRST time the conversation ends as completed support:
--    accepted, ended, and the volunteer replied in it. Reopening a chat clears
--    support_requests.ended_at, but never this row, so earned credit is kept.
--    Members cannot write it; completed_at is the server clock.
--  * A badge counts DISTINCT help seekers with a completion. A pair of members
--    can only ever have one accepted conversation (one_open_request), so
--    repeated end/reopen cycles cannot add credit.
--  * Moderation applies when the badge is read: a conversation an
--    administrator restricted (support_requests.restricted_at, the recorded
--    moderation decision on that interaction) does not count while the
--    restriction stands; lifting it restores the credit.
--  * Account blocks do NOT remove credit: a block is a decision about an
--    account, not about a past interaction. (A blocked volunteer has no public
--    badge at all, because their whole summary is hidden.)
--  * When a member deletes their account, the existing cascade deletes their
--    conversations, and the credit for them goes too.
--
-- Backfill: conversations that are ended at the time this runs and meet the
-- rule above are recorded with their stored ended_at. Conversations that were
-- ended in the past but are currently reopened cannot be reconstructed (the
-- first end time and which messages preceded it are not stored); they earn
-- credit the next time they end. No timestamps are invented.
begin;
set local lock_timeout = '10s';

-- 1. Completion records ------------------------------------------------------
create table if not exists public.volunteer_support_completions (
  request_id uuid primary key references public.support_requests(id) on delete cascade,
  volunteer_id uuid not null references auth.users(id) on delete cascade,
  seeker_id uuid not null references auth.users(id) on delete cascade,
  completed_at timestamptz not null
);
create index if not exists volunteer_support_completions_by_volunteer
  on public.volunteer_support_completions(volunteer_id, seeker_id);
alter table public.volunteer_support_completions enable row level security;
revoke all on public.volunteer_support_completions from anon, authenticated;

-- Accepted, ended, and the volunteer replied. Moderation is applied on read.
create or replace function public.record_maak_support_completion() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.status = 'accepted' and new.ended_at is not null
     and exists (select 1 from messages m where m.request_id = new.id and m.sender_id = new.volunteer_id) then
    insert into volunteer_support_completions(request_id, volunteer_id, seeker_id, completed_at)
      values (new.id, new.volunteer_id, new.seeker_id, now())
      on conflict (request_id) do nothing;
  end if;
  return null;
end; $$;
revoke all on function public.record_maak_support_completion() from public, anon, authenticated;
drop trigger if exists maak_record_support_completion on public.support_requests;
create trigger maak_record_support_completion
  after update of ended_at on public.support_requests
  for each row when (old.ended_at is null and new.ended_at is not null)
  execute function public.record_maak_support_completion();

-- Backfill from conversations that are ended now (see header).
insert into public.volunteer_support_completions(request_id, volunteer_id, seeker_id, completed_at)
select r.id, r.volunteer_id, r.seeker_id, r.ended_at
from public.support_requests r
where r.status = 'accepted' and r.ended_at is not null
  and exists (select 1 from public.messages m where m.request_id = r.id and m.sender_id = r.volunteer_id)
on conflict (request_id) do nothing;

-- 2. Thresholds, editable by administrators in the SQL editor (not by members).
create table if not exists public.volunteer_badge_levels (
  level text primary key check (level in ('beginner', 'intermediate', 'expert')),
  rank smallint not null unique check (rank between 1 and 3),
  min_supported integer not null unique check (min_supported >= 1),
  updated_at timestamptz not null default now()
);
-- Provisionally approved thresholds (Sprint 4): 1, 5 and 15.
insert into public.volunteer_badge_levels(level, rank, min_supported)
  values ('beginner', 1, 1), ('intermediate', 2, 5), ('expert', 3, 15)
  on conflict (level) do nothing;

-- Progression: a higher badge always needs more help seekers supported.
create or replace function public.guard_maak_badge_progression() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if exists (select 1 from volunteer_badge_levels a join volunteer_badge_levels b
             on a.rank < b.rank and a.min_supported >= b.min_supported)
    then raise exception 'badge_thresholds_out_of_order'; end if;
  return null;
end; $$;
drop trigger if exists maak_badge_progression on public.volunteer_badge_levels;
create trigger maak_badge_progression after insert or update on public.volunteer_badge_levels
  for each statement execute function public.guard_maak_badge_progression();
revoke all on function public.guard_maak_badge_progression() from public, anon, authenticated;

alter table public.volunteer_badge_levels enable row level security;
drop policy if exists badge_levels_read on public.volunteer_badge_levels;
create policy badge_levels_read on public.volunteer_badge_levels for select to authenticated using (true);
revoke all on public.volunteer_badge_levels from anon, authenticated;
grant select on public.volunteer_badge_levels to authenticated;

-- 3. Counting ----------------------------------------------------------------
-- Distinct help seekers with a completion whose conversation is not
-- restricted. Internal; the single definition used everywhere below.
create or replace function public.maak_volunteer_supported_counts(p_volunteer_ids uuid[])
returns table (volunteer_id uuid, supported integer)
language sql stable security definer set search_path = public, pg_temp as $$
  select c.volunteer_id, count(distinct c.seeker_id)::int
  from volunteer_support_completions c
  join support_requests r on r.id = c.request_id and r.restricted_at is null
  where c.volunteer_id = any (p_volunteer_ids)
  group by c.volunteer_id;
$$;
revoke all on function public.maak_volunteer_supported_counts(uuid[]) from public, anon, authenticated;

-- Highest badge reached with p_supported distinct help seekers supported, or null.
create or replace function public.maak_badge_for(p_supported integer) returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select level from volunteer_badge_levels where min_supported <= coalesce(p_supported, 0)
  order by rank desc limit 1;
$$;
revoke all on function public.maak_badge_for(integer) from public, anon, authenticated;

-- Replaces the ratings version: same rows and fields, plus 'badge'
-- ('beginner' | 'intermediate' | 'expert' | null). Set-based: one pass over
-- ratings and one over completions for the whole batch (up to 100). The count
-- itself is not published; the volunteer sees it through my_maak_badge_progress.
create or replace function public.maak_volunteer_stats(p_volunteer_ids uuid[]) returns setof jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare ids uuid[];
begin
  if auth.uid() is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
  if coalesce(cardinality(p_volunteer_ids), 0) > 100 then raise exception 'too_many_volunteers'; end if;
  select coalesce(array_agg(v.user_id), '{}') into ids
  from volunteer_profiles v
  where v.user_id = any (p_volunteer_ids) and v.status = 'approved'
    and not exists (select 1 from account_blocks b where b.user_id = v.user_id);
  return query
  select jsonb_build_object('volunteer_id', id, 'rating_count', coalesce(r.n, 0),
           'average_rating', case when coalesce(r.n, 0) >= public.maak_rating_min_for_average()
                                  then round(r.avg_stars, 1) end,
           'badge', public.maak_badge_for(c.supported))
  from unnest(ids) as id
  left join (select x.volunteer_id, count(*)::int as n, avg(x.stars)::numeric as avg_stars
             from volunteer_ratings x where x.volunteer_id = any (ids) group by x.volunteer_id) r
    on r.volunteer_id = id
  left join public.maak_volunteer_supported_counts(ids) c on c.volunteer_id = id;
end; $$;

-- The signed-in volunteer's own progress:
-- {supported, badge, next_badge, next_min}. Null for non-volunteers.
create or replace function public.my_maak_badge_progress() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare me uuid := auth.uid(); n integer; nxt volunteer_badge_levels;
begin
  if me is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
  if not exists (select 1 from volunteer_profiles where user_id = me and status = 'approved') then return null; end if;
  n := coalesce((select supported from public.maak_volunteer_supported_counts(array[me])), 0);
  select * into nxt from volunteer_badge_levels where min_supported > n order by rank limit 1;
  return jsonb_build_object('supported', n, 'badge', public.maak_badge_for(n),
    'next_badge', nxt.level, 'next_min', nxt.min_supported);
end; $$;

revoke all on function public.maak_volunteer_stats(uuid[]), public.my_maak_badge_progress() from public, anon;
grant execute on function public.maak_volunteer_stats(uuid[]), public.my_maak_badge_progress() to authenticated;

notify pgrst, 'reload schema';
commit;
