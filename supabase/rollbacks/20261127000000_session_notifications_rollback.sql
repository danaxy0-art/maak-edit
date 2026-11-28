-- Rollback for 20261127000000_session_notifications.sql.
-- Session notifications go back to kind 'session' (hidden in the app, not
-- pushed) and new ones show times in UTC again. Stored device offsets are
-- deleted. Bodies already rewritten to local time are kept.
begin;

create or replace function public.maak_session_label(p_start timestamptz) returns text
language sql immutable set search_path = public as $$
  select to_char(p_start at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC'
$$;
revoke all on function public.maak_session_label(timestamptz) from public, anon, authenticated;

create or replace function public.maak_session_notify(p_user uuid, p_title text, p_body text, p_ref uuid)
returns void language sql security definer set search_path = public as $$
  insert into notifications(user_id, title, body, kind, reference_id) values (p_user, p_title, p_body, 'session', p_ref);
$$;
revoke all on function public.maak_session_notify(uuid, text, text, uuid) from public, anon, authenticated;

update public.notifications set kind = 'session' where kind = 'support_session';

drop function if exists public.maak_session_localize(text, uuid);
drop function if exists public.maak_session_time_for(timestamptz, uuid);
drop function if exists public.set_maak_utc_offset(integer);
drop table if exists public.member_time_zones;

notify pgrst, 'reload schema';
commit;
