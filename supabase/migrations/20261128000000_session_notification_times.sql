-- === ADDED BY RAZAN: session notification times (shown in the app, pushed, member's own time) ===
-- This file RECORDS what is already live on the production database. The session
-- notifications there were changed directly in Supabase and the change never reached the
-- repo, so a database built from these migrations still had the old behaviour:
--   * kind 'session' notifications that the app hides and the push trigger skips,
--   * times written in UTC.
-- Production already does this instead, and this file makes the repo do the same:
--   * notifications use kind 'support_session' (shown in the app and pushed),
--   * maak_session_label() writes a time marker, [[maak-time:2026-12-01T08:00:00Z]],
--   * maak_session_localize() replaces each marker with the time in the receiving member's
--     own time zone (member_time_zones, saved by set_maak_utc_offset), or in Riyadh time
--     when the member has not saved one.
-- Only Razan's session functions (20261121100000_session_scheduling.sql) are touched, plus
-- one new small table. Nothing of another member's is changed and no notification row is
-- changed. Safe to run again: on production every statement leaves things as they are.
-- Undo with supabase/rollbacks/20261128000000_session_notification_times_rollback.sql.
begin;
set local lock_timeout = '10s';

create table if not exists public.member_time_zones (
  user_id uuid primary key references auth.users(id) on delete cascade,
  utc_offset_minutes integer not null check (utc_offset_minutes >= -720 and utc_offset_minutes <= 840 and utc_offset_minutes % 15 = 0),
  updated_at timestamptz not null default now()
);
alter table public.member_time_zones enable row level security;
-- No policy on purpose: members never touch the table directly. They save their offset
-- through set_maak_utc_offset() below, which only ever writes the caller's own row.
revoke all on public.member_time_zones from public, anon, authenticated;

create or replace function public.set_maak_utc_offset(p_minutes integer)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
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
end; $function$;
revoke all on function public.set_maak_utc_offset(integer) from public, anon;
grant execute on function public.set_maak_utc_offset(integer) to authenticated;

create or replace function public.maak_session_time_for(p_start timestamptz, p_user uuid)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $function$
declare v_offset integer;
begin
  select utc_offset_minutes into v_offset from member_time_zones where user_id = p_user;
  if v_offset is null then
    return to_char(p_start at time zone 'Asia/Riyadh', 'Dy FMDD Mon YYYY, FMHH12:MI AM')
           || ' (Riyadh time)';
  end if;
  return to_char((p_start at time zone 'UTC') + make_interval(mins => v_offset),
                 'Dy FMDD Mon YYYY, FMHH12:MI AM');
end; $function$;
revoke all on function public.maak_session_time_for(timestamptz, uuid) from public, anon, authenticated;

create or replace function public.maak_session_localize(p_text text, p_user uuid)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $function$
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
end; $function$;
revoke all on function public.maak_session_localize(text, uuid) from public, anon, authenticated;

create or replace function public.maak_session_label(p_start timestamptz)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $function$
  select '[[maak-time:' || to_char(p_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || 'Z]]'
$function$;
revoke all on function public.maak_session_label(timestamptz) from public, anon, authenticated;

create or replace function public.maak_session_notify(p_user uuid, p_title text, p_body text, p_ref uuid)
returns void language sql security definer set search_path to 'public', 'pg_temp' as $function$
  -- 'support_session': shown in the app and pushed (reference_id = the booking).
  insert into notifications(user_id, title, body, kind, reference_id)
  values (p_user, public.maak_session_localize(p_title, p_user),
          public.maak_session_localize(p_body, p_user), 'support_session', p_ref);
$function$;
revoke all on function public.maak_session_notify(uuid, text, text, uuid) from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
