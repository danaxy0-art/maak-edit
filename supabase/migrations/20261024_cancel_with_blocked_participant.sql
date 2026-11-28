-- DEPLOYED TO PRODUCTION ON 2026-10-21 - DO NOT RE-RUN on the main Ma'ak project
-- without a team decision (see supabase/production/README.md). All seven
-- post-deployment verification checks returned true.
-- On other databases: apply after 20261023_account_appeals.sql. Idempotent; changes
-- no data.
--
-- Fix: a help seeker could not cancel their own pending support request when the
-- volunteer was blocked. cancel_support_request() sets status='canceled', and the
-- participant guard from 20261021_account_blocking.sql treated every status change
-- except declining as new contact, so it raised participant_unavailable.
--
-- Cancelling only ends contact, like declining. This redefines
-- guard_maak_blocked_participants() with one added exception, deliberately narrow:
-- pending -> canceled, by the request's own seeker (the team's cancellation rule).
-- The function body is otherwise the exact 20261021 version. Unchanged:
--  * a blocked caller is still refused first by maak_blocked_actor_guard
--    (account_blocked), so a blocked seeker cannot cancel and a blocked user
--    cannot change any record;
--  * participants stay immutable; new requests, messages, sessions, accepting,
--    reopening and every other status change involving a blocked participant are
--    still refused with participant_unavailable;
--  * cancel_support_request() itself and its rules (own pending request only) are
--    not changed; conversation restrictions apply to accepted requests only and
--    are not touched.
-- Rollback: supabase/rollbacks/20261024_cancel_with_blocked_participant_rollback.sql.
-- Verification: supabase/checks/20261024_cancel_with_blocked_participant_verify.sql.
begin;
set local lock_timeout = '10s';

-- Replace only a known definition: the 20261021 body, or this file's (re-run).
do $$ declare fp text; begin
 select md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g'))) into fp
 from pg_proc p where p.oid=to_regprocedure('public.guard_maak_blocked_participants()');
 if fp is null then raise exception 'Apply 20261021_account_blocking.sql before this migration'; end if;
 if to_regclass('public.account_block_appeals') is null then
  raise exception 'Apply 20261023_account_appeals.sql before this migration'; end if;
 -- Whitespace-collapsed body fingerprints: 20261021 version, this file's version.
 if fp not in ('669f3519a89e02d08e8469b3828ee284','9da7adda0620fd2a64867e6d697cf6e3') then
  raise exception 'guard_maak_blocked_participants() has an unexpected definition (%); stop and review', fp;
 end if;
end $$;

-- Participant rules for ordinary users (admin and service-role maintenance is exempt).
-- Runs after maak_blocked_actor_guard (same-event BEFORE triggers fire in name
-- order), so a blocked caller is always rejected first with account_blocked.
--  * seeker_id/volunteer_id (requests) and request_id (messages, sessions) are
--    immutable after creation. This also applies inside SECURITY DEFINER RPCs,
--    because auth.uid() is still the calling user there.
--  * New contact with a blocked participant is denied: creating a request, message
--    or session, any request status change except declining or the seeker
--    cancelling a pending request, and rescheduling.
--  * Other updates pass, e.g. the team's restricted_at restriction/unrestriction,
--    declining and cancelling, so an active user can always end contact with a
--    blocked one.
-- Changes to the columns compared here are found by value, whichever columns an
-- UPDATE names, so the trigger fires on every update.
create or replace function public.guard_maak_blocked_participants() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare seeker uuid; volunteer uuid;
begin
 if auth.uid() is null or is_maak_admin() then return new; end if;
 if TG_OP='UPDATE' then
  if TG_TABLE_NAME='support_requests' then
   if new.seeker_id is distinct from old.seeker_id or new.volunteer_id is distinct from old.volunteer_id then
    raise exception 'request_participants_immutable'; end if;
   if new.status is not distinct from old.status or new.status='declined' then return new; end if;
   if old.status='pending' and new.status='canceled' and auth.uid()=old.seeker_id then return new; end if;
  else
   if new.request_id is distinct from old.request_id then raise exception 'request_link_immutable'; end if;
   if TG_TABLE_NAME='messages' then return new; end if;
   -- support_sessions: only a reschedule is new contact.
   if new.starts_at is not distinct from old.starts_at
    and new.duration_minutes is not distinct from old.duration_minutes then return new; end if;
  end if;
 end if;
 if TG_TABLE_NAME='support_requests' then seeker:=new.seeker_id; volunteer:=new.volunteer_id;
 else select r.seeker_id,r.volunteer_id into seeker,volunteer from support_requests r where r.id=new.request_id; end if;
 -- Waits for an in-flight admin_block_account on either participant (see actor guard).
 perform 1 from profiles where id in (seeker,volunteer) order by id for key share;
 if is_maak_account_blocked(seeker) or is_maak_account_blocked(volunteer) then raise exception 'participant_unavailable'; end if;
 return new;
end; $$;

commit;
