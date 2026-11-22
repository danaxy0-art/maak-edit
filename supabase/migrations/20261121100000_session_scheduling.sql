-- === ADDED BY RAZAN: session scheduling =====================================
-- Covers these user stories (all new; no existing table or function is changed):
--   * Volunteer sets and manages available time slots.
--   * Help Seeker views a Volunteer's available slots.
--   * Help Seeker requests a support session at an available slot.
--   * Volunteer accepts or rejects a session request.
--   * Help Seeker or Volunteer reschedules or cancels a session.
--
-- Needs 20261021_account_blocking.sql (is_maak_active, is_maak_account_blocked,
-- guard_maak_blocked_actor), which is already part of the project.
-- Safe to run again. Writes go only through the functions at the bottom.
-- The old book_support_session / support_sessions objects are left untouched.
begin;
set local lock_timeout = '10s';

-- 1. Volunteer availability ---------------------------------------------------
create table if not exists public.volunteer_time_slots (
  id uuid primary key default gen_random_uuid(),
  volunteer_id uuid not null references auth.users(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  -- Set when the volunteer cancels a confirmed booking or reschedules it away:
  -- they are not free then, so the slot is no longer offered to anyone.
  withdrawn_at timestamptz,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (ends_at - starts_at >= interval '15 minutes'),
  check (ends_at - starts_at <= interval '4 hours'),
  unique (volunteer_id, starts_at)
);
create index if not exists volunteer_time_slots_by_volunteer
  on public.volunteer_time_slots(volunteer_id, starts_at);

-- 2. Session bookings (a Help Seeker's request for one slot) -------------------
create table if not exists public.session_bookings (
  id uuid primary key default gen_random_uuid(),
  slot_id uuid not null references public.volunteer_time_slots(id) on delete cascade,
  seeker_id uuid not null references auth.users(id) on delete cascade,
  volunteer_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','accepted','rejected','canceled')),
  reschedule_count integer not null default 0 check (reschedule_count between 0 and 3),
  canceled_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  responded_at timestamptz,
  check (seeker_id <> volunteer_id)
);
-- One live booking per slot: two people can never hold the same time.
create unique index if not exists session_bookings_one_live_per_slot
  on public.session_bookings(slot_id) where status in ('pending','accepted');
create index if not exists session_bookings_seeker on public.session_bookings(seeker_id, status);
create index if not exists session_bookings_volunteer on public.session_bookings(volunteer_id, status);

-- 3. Row security: members may only READ their own rows ------------------------
alter table public.volunteer_time_slots enable row level security;
alter table public.session_bookings enable row level security;
drop policy if exists time_slots_read_own on public.volunteer_time_slots;
create policy time_slots_read_own on public.volunteer_time_slots for select to authenticated
  using (volunteer_id = auth.uid() and (select is_maak_active()));
drop policy if exists bookings_read_own on public.session_bookings;
create policy bookings_read_own on public.session_bookings for select to authenticated
  using ((seeker_id = auth.uid() or volunteer_id = auth.uid()) and (select is_maak_active()));
revoke all on public.volunteer_time_slots, public.session_bookings from anon, authenticated;
grant select on public.volunteer_time_slots, public.session_bookings to authenticated;

-- A blocked account cannot write here, same as the other member tables.
drop trigger if exists maak_blocked_actor_guard on public.volunteer_time_slots;
create trigger maak_blocked_actor_guard before insert or update or delete on public.volunteer_time_slots
  for each row execute function public.guard_maak_blocked_actor();
drop trigger if exists maak_blocked_actor_guard on public.session_bookings;
create trigger maak_blocked_actor_guard before insert or update or delete on public.session_bookings
  for each row execute function public.guard_maak_blocked_actor();

-- 4. Helpers (internal) --------------------------------------------------------
create or replace function public.maak_session_notify(p_user uuid, p_title text, p_body text, p_ref uuid)
returns void language sql security definer set search_path = public as $$
  -- kind 'session' is shown in the app's notification list (push skips it).
  insert into notifications(user_id, title, body, kind, reference_id) values (p_user, p_title, p_body, 'session', p_ref);
$$;
revoke all on function public.maak_session_notify(uuid, text, text, uuid) from public, anon, authenticated;

create or replace function public.maak_session_label(p_start timestamptz) returns text
language sql immutable set search_path = public as $$
  select to_char(p_start at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC'
$$;
revoke all on function public.maak_session_label(timestamptz) from public, anon, authenticated;

-- 5. Volunteer: set and manage slots -------------------------------------------
create or replace function public.add_maak_time_slot(p_starts_at timestamptz, p_ends_at timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); v_id uuid;
begin
  if me is null or not public.is_maak_active()
     or not exists (select 1 from volunteer_profiles where user_id = me and status = 'approved')
    then raise exception 'not_allowed'; end if;
  if p_starts_at is null or p_ends_at is null or p_starts_at <= now()
     or p_ends_at - p_starts_at < interval '15 minutes'
     or p_ends_at - p_starts_at > interval '4 hours'
     or p_starts_at > now() + interval '90 days'
    then raise exception 'invalid_slot_time'; end if;
  perform pg_advisory_xact_lock(hashtextextended('slots:' || me::text, 0));
  if exists (select 1 from volunteer_time_slots s where s.volunteer_id = me and s.withdrawn_at is null
             and s.starts_at < p_ends_at and s.ends_at > p_starts_at)
    then raise exception 'slot_overlap'; end if;
  if (select count(*) from volunteer_time_slots s
        where s.volunteer_id = me and s.withdrawn_at is null and s.ends_at > now()) >= 50
    then raise exception 'slot_limit'; end if;
  -- A withdrawn slot with the same start would hit the unique rule: reuse it.
  delete from volunteer_time_slots s where s.volunteer_id = me and s.starts_at = p_starts_at
    and s.withdrawn_at is not null
    and not exists (select 1 from session_bookings b where b.slot_id = s.id and b.status in ('pending','accepted'));
  insert into volunteer_time_slots(volunteer_id, starts_at, ends_at) values (me, p_starts_at, p_ends_at)
    returning id into v_id;
  return v_id;
end; $$;

create or replace function public.remove_maak_time_slot(p_slot_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
  perform 1 from volunteer_time_slots where id = p_slot_id and volunteer_id = me for update;
  if not found then raise exception 'slot_unavailable'; end if;
  -- A slot with a pending or accepted booking must be handled (reject/cancel) first.
  if exists (select 1 from session_bookings where slot_id = p_slot_id and status in ('pending','accepted'))
    then raise exception 'slot_booked'; end if;
  delete from volunteer_time_slots where id = p_slot_id and volunteer_id = me;
end; $$;

-- The volunteer's own upcoming slots, with who (if anyone) holds each one.
create or replace function public.my_maak_time_slots() returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', s.id, 'starts_at', s.starts_at, 'ends_at', s.ends_at,
           'booking_id', b.id, 'booking_status', b.status, 'seeker_name', p.full_name)
  from volunteer_time_slots s
  left join session_bookings b on b.slot_id = s.id and b.status in ('pending','accepted')
  left join profiles p on p.id = b.seeker_id
  where auth.uid() is not null and public.is_maak_active()
    and s.volunteer_id = auth.uid() and s.withdrawn_at is null and s.ends_at > now()
  order by s.starts_at;
$$;

-- 6. Help Seeker: view a volunteer's open slots ---------------------------------
create or replace function public.volunteer_available_slots(p_volunteer_id uuid) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', s.id, 'volunteer_id', s.volunteer_id, 'starts_at', s.starts_at, 'ends_at', s.ends_at)
  from volunteer_time_slots s
  where auth.uid() is not null and public.is_maak_active()
    and s.volunteer_id = p_volunteer_id and s.withdrawn_at is null and s.starts_at > now()
    and exists (select 1 from volunteer_profiles v where v.user_id = s.volunteer_id and v.status = 'approved')
    and not public.is_maak_account_blocked(s.volunteer_id)
    and not exists (select 1 from session_bookings b where b.slot_id = s.id and b.status in ('pending','accepted'))
    -- A slot this help seeker was already turned down for is not offered to them again.
    and not exists (select 1 from session_bookings r where r.slot_id = s.id and r.seeker_id = auth.uid() and r.status = 'rejected')
  order by s.starts_at;
$$;

-- 7. Help Seeker: request a session at a slot ------------------------------------
create or replace function public.request_maak_session(p_slot_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); s record; v_id uuid; seeker_name text;
begin
  if me is null or not public.is_maak_active()
     or not exists (select 1 from help_seeker_profiles where user_id = me)
    then raise exception 'not_allowed'; end if;
  select * into s from volunteer_time_slots where id = p_slot_id for update;
  if not found or s.withdrawn_at is not null or s.starts_at <= now()
     or not exists (select 1 from volunteer_profiles v where v.user_id = s.volunteer_id and v.status = 'approved')
     or public.is_maak_account_blocked(s.volunteer_id)
    then raise exception 'slot_unavailable'; end if;
  if exists (select 1 from session_bookings where slot_id = p_slot_id and status in ('pending','accepted'))
    then raise exception 'slot_unavailable'; end if;
  -- The volunteer already turned this help seeker down for this exact time.
  if exists (select 1 from session_bookings where slot_id = p_slot_id and seeker_id = me and status = 'rejected')
    then raise exception 'slot_unavailable'; end if;
  perform pg_advisory_xact_lock(hashtextextended('seeker:' || me::text, 0));
  if exists (select 1 from session_bookings b join volunteer_time_slots t on t.id = b.slot_id
             where b.seeker_id = me and b.status in ('pending','accepted')
               and t.starts_at < s.ends_at and t.ends_at > s.starts_at)
    then raise exception 'session_overlap'; end if;
  if (select count(*) from session_bookings b join volunteer_time_slots t on t.id = b.slot_id
        where b.seeker_id = me and b.status = 'pending' and t.ends_at > now()) >= 3
    then raise exception 'too_many_pending'; end if;
  insert into session_bookings(slot_id, seeker_id, volunteer_id) values (p_slot_id, me, s.volunteer_id)
    returning id into v_id;
  select full_name into seeker_name from profiles where id = me;
  perform public.maak_session_notify(s.volunteer_id, 'New session request',
    coalesce(seeker_name, 'A help seeker') || ' asked for a session on ' || public.maak_session_label(s.starts_at) || '.', v_id);
  return v_id;
end; $$;

-- 8. Volunteer: accept or reject ---------------------------------------------------
create or replace function public.decide_maak_session(p_booking_id uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); b record; s record;
begin
  if me is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
  select * into b from session_bookings where id = p_booking_id and volunteer_id = me for update;
  if not found or b.status <> 'pending' then raise exception 'session_changed'; end if;
  select * into s from volunteer_time_slots where id = b.slot_id for update;
  if s.starts_at <= now() then raise exception 'session_changed'; end if;
  update session_bookings set status = case when p_accept then 'accepted' else 'rejected' end,
         responded_at = now(), updated_at = now() where id = b.id;
  -- Rejecting only turns down THIS help seeker: the slot goes back to open for
  -- others. That same help seeker cannot request it again (see request_maak_session).
  perform public.maak_session_notify(b.seeker_id,
    case when p_accept then 'Session confirmed' else 'Session request declined' end,
    case when p_accept then 'Your session on ' || public.maak_session_label(s.starts_at) || ' is confirmed.'
         else 'The volunteer cannot do ' || public.maak_session_label(s.starts_at) || '. Please choose another time.' end,
    b.id);
end; $$;

-- 9. Either side: cancel -----------------------------------------------------------
create or replace function public.cancel_maak_session(p_booking_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); b record; s record; other uuid;
begin
  if me is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
  select * into b from session_bookings where id = p_booking_id and (seeker_id = me or volunteer_id = me) for update;
  if not found or b.status not in ('pending','accepted') then raise exception 'session_changed'; end if;
  select * into s from volunteer_time_slots where id = b.slot_id for update;
  if s.starts_at <= now() then raise exception 'session_started'; end if;
  update session_bookings set status = 'canceled', canceled_by = me, updated_at = now() where id = b.id;
  -- Seeker cancels: the time is free again. Volunteer cancels: they are unavailable then.
  if me = b.volunteer_id then update volunteer_time_slots set withdrawn_at = now() where id = s.id; end if;
  other := case when me = b.seeker_id then b.volunteer_id else b.seeker_id end;
  perform public.maak_session_notify(other, 'Session canceled',
    'The session on ' || public.maak_session_label(s.starts_at) || ' was canceled.', b.id);
end; $$;

-- 10. Either side: reschedule to another open slot of the same volunteer -----------
-- Help Seeker moves it: it goes back to 'pending' so the volunteer confirms again.
-- Volunteer moves it: it stays as it is and the Help Seeker is told (they may cancel).
create or replace function public.reschedule_maak_session(p_booking_id uuid, p_new_slot_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); b record; old_s record; new_s record; other uuid; by_seeker boolean;
begin
  if me is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
  select * into b from session_bookings where id = p_booking_id and (seeker_id = me or volunteer_id = me) for update;
  if not found or b.status not in ('pending','accepted') then raise exception 'session_changed'; end if;
  if b.reschedule_count >= 3 then raise exception 'reschedule_limit'; end if;
  by_seeker := (me = b.seeker_id);
  -- Lock both slots in a fixed order so two reschedules cannot deadlock.
  perform 1 from volunteer_time_slots where id in (b.slot_id, p_new_slot_id) order by id for update;
  select * into old_s from volunteer_time_slots where id = b.slot_id;
  select * into new_s from volunteer_time_slots where id = p_new_slot_id;
  if old_s.starts_at <= now() then raise exception 'session_started'; end if;
  if new_s.id is null or new_s.volunteer_id <> b.volunteer_id or new_s.id = old_s.id
     or new_s.withdrawn_at is not null or new_s.starts_at <= now()
     or exists (select 1 from session_bookings x where x.slot_id = new_s.id and x.status in ('pending','accepted'))
     or exists (select 1 from session_bookings x where x.slot_id = new_s.id and x.seeker_id = b.seeker_id and x.status = 'rejected')
    then raise exception 'slot_unavailable'; end if;
  if exists (select 1 from session_bookings x join volunteer_time_slots t on t.id = x.slot_id
             where x.seeker_id = b.seeker_id and x.id <> b.id and x.status in ('pending','accepted')
               and t.starts_at < new_s.ends_at and t.ends_at > new_s.starts_at)
    then raise exception 'session_overlap'; end if;
  update session_bookings set slot_id = new_s.id, reschedule_count = reschedule_count + 1, updated_at = now(),
         status = case when by_seeker then 'pending' else b.status end,
         responded_at = case when by_seeker then null else b.responded_at end
   where id = b.id;
  if not by_seeker then update volunteer_time_slots set withdrawn_at = now() where id = old_s.id; end if;
  other := case when by_seeker then b.volunteer_id else b.seeker_id end;
  perform public.maak_session_notify(other,
    case when by_seeker then 'Session rescheduled: please confirm' else 'Session rescheduled' end,
    'The session moved from ' || public.maak_session_label(old_s.starts_at) || ' to ' || public.maak_session_label(new_s.starts_at) || '.',
    b.id);
end; $$;

-- 11. Both sides: list my sessions ------------------------------------------------------
create or replace function public.my_maak_sessions() returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', b.id, 'slot_id', b.slot_id, 'status', b.status,
           -- What the app shows. The stored status is never changed by time alone:
           --   pending, start time passed  -> expired   (nobody answered in time)
           --   accepted, now inside slot   -> in_progress
           --   accepted, slot is over      -> completed
           'display_status', case
             when b.status = 'pending' and s.starts_at <= now() then 'expired'
             when b.status = 'accepted' and s.ends_at <= now() then 'completed'
             when b.status = 'accepted' and s.starts_at <= now() then 'in_progress'
             else b.status end,
           'starts_at', s.starts_at, 'ends_at', s.ends_at, 'volunteer_id', b.volunteer_id, 'seeker_id', b.seeker_id,
           'is_volunteer', b.volunteer_id = auth.uid(), 'contact_name', p.full_name,
           'reschedule_count', b.reschedule_count, 'canceled_by_me', b.canceled_by = auth.uid())
  from session_bookings b
  join volunteer_time_slots s on s.id = b.slot_id
  join profiles p on p.id = case when b.seeker_id = auth.uid() then b.volunteer_id else b.seeker_id end
  where auth.uid() is not null and public.is_maak_active() and (b.seeker_id = auth.uid() or b.volunteer_id = auth.uid())
  order by s.starts_at desc;
$$;

-- 12. Grants (only signed-in members may call the public functions) ---------------------
do $$ declare f text; begin
  foreach f in array array[
    'add_maak_time_slot(timestamptz,timestamptz)','remove_maak_time_slot(uuid)','my_maak_time_slots()',
    'volunteer_available_slots(uuid)','request_maak_session(uuid)','decide_maak_session(uuid,boolean)',
    'cancel_maak_session(uuid)','reschedule_maak_session(uuid,uuid)','my_maak_sessions()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
commit;
-- === END ADDED BY RAZAN =====================================================
