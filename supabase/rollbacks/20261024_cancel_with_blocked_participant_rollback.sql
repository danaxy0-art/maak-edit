-- ROLLBACK for supabase/migrations/20261024_cancel_with_blocked_participant.sql.
-- Run once, as one transaction, in the SQL Editor. Restores the 20261021 version of
-- guard_maak_blocked_participants() exactly (copied from 20261021_account_blocking.sql).
-- Effect: a help seeker can again not cancel a pending request to a blocked
-- volunteer (participant_unavailable). Requests already canceled stay canceled; no
-- data is changed. Roll this back before rolling back 20261023, 20261022 or 20261021.
begin;
set local lock_timeout = '10s';

do $$ declare fp text; begin
 select md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g'))) into fp
 from pg_proc p where p.oid=to_regprocedure('public.guard_maak_blocked_participants()');
 if fp is null or fp not in ('669f3519a89e02d08e8469b3828ee284','9da7adda0620fd2a64867e6d697cf6e3') then
  raise exception 'guard_maak_blocked_participants() has an unexpected definition (%); stop and review', fp;
 end if;
end $$;

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
