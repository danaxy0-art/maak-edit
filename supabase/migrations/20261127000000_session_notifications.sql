-- Session notifications: show them in the app, push them, and give times in
-- the recipient's device time. Apply after 20261121100000_session_scheduling.sql
-- and 20261107020000_single_restriction_push.sql. Repeatable (safe to run twice;
-- running it again upgrades an earlier copy of this file).
--
-- 1. Session requests, confirmations, declines, cancellations and reschedules
--    were stored with kind 'session'. That kind belonged to the old booking
--    feature (removed), so the app hides it and the push trigger skips it:
--    nobody ever saw these. They now use kind 'support_session', which the app
--    shows (tap opens Sessions) and push_maak_notification sends like any other
--    kind. Old booking-era 'session' rows stay hidden.
--    Earlier scheduling notifications (reference_id = a session booking) move
--    to the new kind too. They appear in the app; they are not pushed again.
-- 2. Times were written as "2026-11-30 15:00 UTC". They are now written in the
--    recipient's device time, e.g. "Mon 30 Nov 2026, 6:00 PM":
--    * the app reports the device's UTC offset (set_maak_utc_offset) when it
--      opens and when it returns to the foreground;
--    * maak_session_label (used by the session functions) now returns a
--      placeholder, and maak_session_notify, which knows the recipient,
--      replaces it with the time at that recipient's offset;
--    * a recipient whose offset is not known yet gets Riyadh time, marked
--      "(Riyadh time)".
--    Stored notifications that still contain a UTC time are rewritten.
--    The text is written when the notification is sent: someone who later
--    moves to another time zone sees older notifications in the old one.
-- 3. The helpers have pg_temp in their search_path, like the rest of the schema.
begin;

-- Device UTC offsets ----------------------------------------------------------
create table if not exists public.member_time_zones (
  user_id uuid primary key references auth.users(id) on delete cascade,
  -- Minutes east of UTC, e.g. 180 for Riyadh, -300 for New York in winter.
  utc_offset_minutes integer not null
    check (utc_offset_minutes between -720 and 840 and utc_offset_minutes % 15 = 0),
  updated_at timestamptz not null default now());
alter table public.member_time_zones enable row level security;
revoke all on public.member_time_zones from anon, authenticated;

-- Called by the app with DateTime.now().timeZoneOffset.inMinutes.
create or replace function public.set_maak_utc_offset(p_minutes integer)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_allowed'; end if;
  if p_minutes is null or p_minutes not between -720 and 840 or p_minutes % 15 <> 0 then
    raise exception 'invalid_utc_offset';
  end if;
  insert into member_time_zones(user_id, utc_offset_minutes, updated_at)
  values (auth.uid(), p_minutes, now())
  on conflict (user_id) do update
    set utc_offset_minutes = excluded.utc_offset_minutes, updated_at = now()
    where member_time_zones.utc_offset_minutes <> excluded.utc_offset_minutes;
end; $$;
revoke all on function public.set_maak_utc_offset(integer) from public, anon;
grant execute on function public.set_maak_utc_offset(integer) to authenticated;

-- A session time as one member reads it: their device time, or Riyadh time
-- (marked) when their offset is unknown.
create or replace function public.maak_session_time_for(p_start timestamptz, p_user uuid)
returns text language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_offset integer;
begin
  select utc_offset_minutes into v_offset from member_time_zones where user_id = p_user;
  if v_offset is null then
    return to_char(p_start at time zone 'Asia/Riyadh', 'Dy FMDD Mon YYYY, FMHH12:MI AM')
           || ' (Riyadh time)';
  end if;
  return to_char((p_start at time zone 'UTC') + make_interval(mins => v_offset),
                 'Dy FMDD Mon YYYY, FMHH12:MI AM');
end; $$;
revoke all on function public.maak_session_time_for(timestamptz, uuid) from public, anon, authenticated;

-- Placeholder for a session time; maak_session_notify turns it into the
-- recipient's time. Only for notification text (it is not readable as is).
create or replace function public.maak_session_label(p_start timestamptz) returns text
language sql immutable set search_path = public, pg_temp as $$
  select '[[maak-time:' || to_char(p_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || 'Z]]'
$$;
revoke all on function public.maak_session_label(timestamptz) from public, anon, authenticated;

-- Replaces every session-time placeholder in a text for one recipient.
create or replace function public.maak_session_localize(p_text text, p_user uuid)
returns text language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_text text := p_text;
  v_token text;
begin
  loop
    v_token := substring(v_text from '\[\[maak-time:[0-9T:\-]+Z\]\]');
    exit when v_token is null;
    v_text := replace(v_text, v_token, public.maak_session_time_for(
      (substring(v_token from 13 for 19) || '+00')::timestamptz, p_user));
  end loop;
  return v_text;
end; $$;
revoke all on function public.maak_session_localize(text, uuid) from public, anon, authenticated;

create or replace function public.maak_session_notify(p_user uuid, p_title text, p_body text, p_ref uuid)
returns void language sql security definer set search_path = public, pg_temp as $$
  -- 'support_session': shown in the app and pushed (reference_id = the booking).
  insert into notifications(user_id, title, body, kind, reference_id)
  values (p_user, public.maak_session_localize(p_title, p_user),
          public.maak_session_localize(p_body, p_user), 'support_session', p_ref);
$$;
revoke all on function public.maak_session_notify(uuid, text, text, uuid) from public, anon, authenticated;

-- Earlier scheduling notifications: same kind as new ones.
update public.notifications n set kind = 'support_session'
where n.kind = 'session'
  and exists (select 1 from public.session_bookings b where b.id = n.reference_id);

-- Rewrite "YYYY-MM-DD HH24:MI UTC" (and any leftover placeholder) in stored
-- session notifications, in each recipient's time.
do $$
declare
  r record;
  v_body text;
  v_match text;
begin
  for r in select id, user_id, body from public.notifications
           where kind = 'support_session'
             and (body ~ '\d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC' or body like '%[[maak-time:%')
  loop
    v_body := r.body;
    loop
      v_match := substring(v_body from '\d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC');
      exit when v_match is null;
      v_body := replace(v_body, v_match,
        public.maak_session_time_for((left(v_match, 16) || ':00+00')::timestamptz, r.user_id));
    end loop;
    update public.notifications
    set body = public.maak_session_localize(v_body, r.user_id)
    where id = r.id;
  end loop;
end $$;

notify pgrst, 'reload schema';
commit;
