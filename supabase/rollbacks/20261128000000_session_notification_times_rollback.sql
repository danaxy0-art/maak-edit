-- Rollback for 20261128000000_session_notification_times.sql (ADDED BY RAZAN). Puts the two
-- session functions back as 20261121100000_session_scheduling.sql first defined them (kind
-- 'session', times in UTC) and removes the two helpers. The member_time_zones table and
-- set_maak_utc_offset() are KEPT on purpose so members' saved time zones are not lost.
begin;
create or replace function public.maak_session_notify(p_user uuid, p_title text, p_body text, p_ref uuid)
returns void language sql security definer set search_path = public as $$
  insert into notifications(user_id, title, body, kind, reference_id) values (p_user, p_title, p_body, 'session', p_ref);
$$;
revoke all on function public.maak_session_notify(uuid, text, text, uuid) from public, anon, authenticated;
create or replace function public.maak_session_label(p_start timestamptz) returns text
language sql immutable set search_path = public as $$
  select to_char(p_start at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC'
$$;
revoke all on function public.maak_session_label(timestamptz) from public, anon, authenticated;
drop function if exists public.maak_session_localize(text, uuid);
drop function if exists public.maak_session_time_for(timestamptz, uuid);
notify pgrst, 'reload schema';
commit;
