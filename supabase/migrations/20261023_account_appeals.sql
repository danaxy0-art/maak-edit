-- =====================================================================================
-- DEPLOYED TO PRODUCTION ON 2026-10-21 - DO NOT RE-RUN ON THE MAIN MA'AK PROJECT.
-- It is the last of the sequence; it is only re-applied after 20261021 or 20261022
-- has been re-run there by mistake (see their headers), followed by its verification.
-- Applied through the Supabase SQL Editor: migration history may not list it. Do not
-- run `supabase db push` or `supabase migration repair` against production until the
-- team has reconciled the history. Never run supabase_schema.sql or APPLY_UPDATES.sql
-- on production without review. Fresh databases: see supabase/production/README.md.
-- =====================================================================================
-- Apply after 20261022_account_moderation_visibility.sql. Idempotent; preserves data.
-- Account restriction appeals: a blocked help seeker or volunteer may appeal,
-- an admin approves (which reactivates the account) or rejects.
--
-- Rules enforced in the database (not only in the app):
--  * Each appeal belongs to one blocking event (the immutable 'blocked' row in
--    account_moderation_events). At most 3 appeals per event, at most one pending.
--  * The next appeal is possible only after the previous one was rejected.
--  * Approval reactivates the account in the same transaction.
--  * Any other end of a block (manual reactivation, account deletion) closes a
--    pending appeal as 'closed', never 'rejected'.
--  * Appeal rows are append-only: a pending appeal may be decided once; on
--    account deletion the free text is redacted. Nothing else can change them.
--  * Blocked users get two RPCs scoped to their own current block. The existing
--    blocked-user write guard is unchanged.
-- Retention: after account deletion, appeals keep only minimal metadata (ids,
-- attempt, status, closed reason, timestamps, deciding admin id); the member's
-- explanation and the admin's decision note (which may quote it) are redacted.
-- Lock order everywhere: member profile (FOR UPDATE) -> account_blocks -> appeal.
-- WARNING: re-running 20261021 or 20261022 replaces functions redefined here.
-- Re-apply this file afterwards.
begin;
set local lock_timeout = '10s';

do $$ begin
 if to_regprocedure('public.maak_admin_label(uuid)') is null then
  raise exception 'Apply 20261022_account_moderation_visibility.sql before this migration';
 end if;
end $$;

-- 1. Link every block to its 'blocked' event ----------------------------------
alter table public.account_blocks add column if not exists block_event_id uuid;
alter table public.account_blocks drop constraint if exists account_blocks_block_event_fk;
alter table public.account_blocks add constraint account_blocks_block_event_fk
 foreign key (block_event_id) references public.account_moderation_events(id);

-- 20261021 wrote each block and its event in one transaction (same now(), reason
-- and admin). Link only when all of these hold, otherwise stop instead of guessing:
--  * exactly one 'blocked' event has the block's user, timestamp, reason and admin;
--  * it is the only event of that user at or after the block's timestamp, so no
--    other event (even one with an identical timestamp) makes the order unclear;
--  * if blocked_by is null, the event's admin really no longer exists (the
--    ON DELETE SET NULL case); a null for any other reason is not trusted.
do $$ declare bad bigint; ids text; begin
 select count(*), string_agg(b.user_id::text, ', ') into bad, ids
 from public.account_blocks b
 where b.block_event_id is null and (
  (select count(*) from public.account_moderation_events e
    where e.user_id=b.user_id and e.action='blocked' and e.created_at=b.blocked_at
      and e.reason=b.reason and (b.blocked_by is null or e.actor_id=b.blocked_by)) <> 1
  or (select count(*) from public.account_moderation_events e
    where e.user_id=b.user_id and e.created_at>=b.blocked_at) <> 1
  or (b.blocked_by is null and exists(select 1 from public.account_moderation_events e
    join public.profiles a on a.id=e.actor_id
    where e.user_id=b.user_id and e.action='blocked' and e.created_at=b.blocked_at)));
 if bad > 0 then
  raise exception 'block_event_backfill_failed: % current block(s) lack exactly one latest matching blocked event (users: %)', bad, ids;
 end if;
 update public.account_blocks b set block_event_id=(select e.id from public.account_moderation_events e
   where e.user_id=b.user_id and e.action='blocked' and e.created_at=b.blocked_at
     and e.reason=b.reason and (b.blocked_by is null or e.actor_id=b.blocked_by))
 where b.block_event_id is null;
end $$;
alter table public.account_blocks alter column block_event_id set not null;
create unique index if not exists account_blocks_block_event_unique on public.account_blocks(block_event_id);

-- A foreign key is not enough: the event must be this user's 'blocked' event,
-- and once set the link can never change.
create or replace function public.guard_account_block_event() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 -- Set once: linking an unlinked block (the backfill, including a re-apply after
 -- a rollback) is allowed; changing or clearing an existing link is not.
 if TG_OP='UPDATE' and old.block_event_id is not null
    and new.block_event_id is distinct from old.block_event_id then
  raise exception 'block_event_immutable';
 end if;
 -- A missing link is rejected by NOT NULL after this trigger; letting it pass here
 -- keeps the clearer cannot_block_admin error from maak_account_block_target.
 if new.block_event_id is null then return new; end if;
 if not exists(select 1 from account_moderation_events e
   where e.id=new.block_event_id and e.action='blocked' and e.user_id=new.user_id) then
  raise exception 'block_event_mismatch';
 end if;
 return new;
end; $$;
drop trigger if exists maak_account_block_event_guard on public.account_blocks;
create trigger maak_account_block_event_guard before insert or update of block_event_id, user_id
 on public.account_blocks for each row execute function public.guard_account_block_event();

-- 2. Appeals table --------------------------------------------------------------
-- user_id and decided_by have no foreign keys, like account_moderation_events,
-- so minimal audit metadata survives account deletion.
create table if not exists public.account_block_appeals (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null,
 block_event_id uuid not null references public.account_moderation_events(id),
 attempt smallint not null check (attempt between 1 and 3),
 message text check (message is null or char_length(message) between 1 and 1000),
 status text not null default 'pending' check (status in ('pending','approved','rejected','closed')),
 closed_reason text check (closed_reason in ('reactivated','account_deleted')),
 submitted_at timestamptz not null default now(),
 decided_at timestamptz,
 decided_by uuid,
 decision_note text check (decision_note is null or char_length(decision_note) between 1 and 1000),
 redacted_at timestamptz,
 unique (block_event_id, attempt),
 check ((status = 'pending') = (decided_at is null)),
 check ((status = 'closed') = (closed_reason is not null)),
 check (status <> 'rejected' or decision_note is not null or redacted_at is not null),
 check (redacted_at is not null or message is not null),
 check (redacted_at is null or (message is null and decision_note is null))
);
create unique index if not exists one_pending_appeal_per_block
 on public.account_block_appeals(block_event_id) where status='pending';
create index if not exists appeals_user_date on public.account_block_appeals(user_id, submitted_at desc);
create index if not exists appeals_pending on public.account_block_appeals(submitted_at) where status='pending';
-- No policies: direct client access is denied; only the RPCs below read or write.
alter table public.account_block_appeals enable row level security;
revoke all on public.account_block_appeals from public,anon,authenticated;

-- New appeals must target the user's current block, as a fresh pending row.
create or replace function public.guard_appeal_insert() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.status<>'pending' or new.decided_at is not null or new.decided_by is not null
    or new.decision_note is not null or new.closed_reason is not null or new.redacted_at is not null then
  raise exception 'appeal_history_immutable';
 end if;
 if not exists(select 1 from account_moderation_events e
   where e.id=new.block_event_id and e.action='blocked' and e.user_id=new.user_id) then
  raise exception 'block_event_mismatch';
 end if;
 if not exists(select 1 from account_blocks b where b.user_id=new.user_id and b.block_event_id=new.block_event_id) then
  raise exception 'appeal_not_current';
 end if;
 return new;
end; $$;
drop trigger if exists maak_appeal_insert_guard on public.account_block_appeals;
create trigger maak_appeal_insert_guard before insert on public.account_block_appeals
 for each row execute function public.guard_appeal_insert();

-- Only two updates are ever allowed:
--  * decision: pending -> approved/rejected/closed, exactly once, touching only
--    the decision columns, in a valid combination:
--     - approved/rejected: made by the signed-in active admin as decided_by,
--       while the member's profile exists; rejected needs a note; no closed_reason;
--     - closed: decided_by is the caller (null for service role or SQL), no note,
--       closed_reason 'reactivated' iff the member's profile still exists;
--     - decided_at set, not before submitted_at;
--  * redaction: once the member's profile is gone, clear message and note only.
-- Closing and redaction may happen to one row in either order during account
-- deletion; each is valid on its own.
create or replace function public.guard_appeal_update() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare member_exists boolean:=exists(select 1 from profiles where id=old.user_id);
 closing_reason text;
begin
 closing_reason:=case when member_exists then 'reactivated' else 'account_deleted' end;
 if new.id<>old.id or new.user_id<>old.user_id or new.block_event_id<>old.block_event_id
    or new.attempt<>old.attempt or new.submitted_at<>old.submitted_at then
  raise exception 'appeal_history_immutable';
 end if;
 if old.status='pending' and new.status<>'pending' then
  if new.message is distinct from old.message or new.redacted_at is distinct from old.redacted_at
     or new.decided_at is null or new.decided_at<old.submitted_at then
   raise exception 'appeal_decision_invalid';
  end if;
  if new.status in ('approved','rejected') then
   if auth.uid() is null or new.decided_by is distinct from auth.uid() or not is_maak_admin()
      or not member_exists or old.redacted_at is not null or new.closed_reason is not null
      or (new.status='rejected' and new.decision_note is null) then
    raise exception 'appeal_decision_invalid';
   end if;
  elsif new.status='closed' then
   if new.decision_note is not null or new.decided_by is distinct from auth.uid()
      or new.closed_reason is distinct from closing_reason then
    raise exception 'appeal_decision_invalid';
   end if;
  else
   raise exception 'appeal_decision_invalid';
  end if;
  return new;
 end if;
 if old.redacted_at is null and new.redacted_at is not null
    and new.message is null and new.decision_note is null
    and new.status=old.status and new.closed_reason is not distinct from old.closed_reason
    and new.decided_at is not distinct from old.decided_at
    and new.decided_by is not distinct from old.decided_by
    and not member_exists then
  return new;
 end if;
 raise exception 'appeal_history_immutable';
end; $$;
create or replace function public.guard_appeal_delete() returns trigger
language plpgsql set search_path=public,pg_temp as $$
begin raise exception 'appeal_history_immutable'; end; $$;
drop trigger if exists maak_appeal_update_guard on public.account_block_appeals;
create trigger maak_appeal_update_guard before update on public.account_block_appeals
 for each row execute function public.guard_appeal_update();
drop trigger if exists maak_appeal_delete_guard on public.account_block_appeals;
create trigger maak_appeal_delete_guard before delete on public.account_block_appeals
 for each row execute function public.guard_appeal_delete();
drop trigger if exists maak_appeal_no_truncate on public.account_block_appeals;
create trigger maak_appeal_no_truncate before truncate on public.account_block_appeals
 for each statement execute function public.guard_appeal_delete();

-- 3. Lifecycle triggers -----------------------------------------------------------
-- Whenever a block row disappears (manual reactivation, account deletion,
-- service-role maintenance), its pending appeal is closed, never rejected.
-- Approval marks its appeal approved before deleting the block, so it is skipped.
create or replace function public.close_appeals_on_unblock() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 update account_block_appeals
  set status='closed', decided_at=now(), decided_by=auth.uid(),
      closed_reason=case when exists(select 1 from profiles where id=old.user_id)
                         then 'reactivated' else 'account_deleted' end
  where block_event_id=old.block_event_id and status='pending';
 return old;
end; $$;
drop trigger if exists maak_close_appeals_on_unblock on public.account_blocks;
create trigger maak_close_appeals_on_unblock after delete on public.account_blocks
 for each row execute function public.close_appeals_on_unblock();

-- Account deletion: redact free text, keep minimal metadata.
create or replace function public.redact_appeals_on_profile_delete() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 update account_block_appeals set message=null, decision_note=null, redacted_at=now()
  where user_id=old.id and redacted_at is null;
 return old;
end; $$;
drop trigger if exists maak_redact_appeals_on_delete on public.profiles;
create trigger maak_redact_appeals_on_delete after delete on public.profiles
 for each row execute function public.redact_appeals_on_profile_delete();

-- An automatic reactivation event names its appeal; validate that link.
alter table public.account_moderation_events add column if not exists appeal_id uuid;
create or replace function public.guard_moderation_event_appeal() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.appeal_id is not null and (new.action<>'reactivated' or not exists(
   select 1 from account_block_appeals a
   where a.id=new.appeal_id and a.user_id=new.user_id and a.status='approved')) then
  raise exception 'appeal_event_mismatch';
 end if;
 return new;
end; $$;
drop trigger if exists maak_moderation_event_appeal_guard on public.account_moderation_events;
create trigger maak_moderation_event_appeal_guard before insert on public.account_moderation_events
 for each row execute function public.guard_moderation_event_appeal();

-- 4. Blocking now records its event ------------------------------------------------
-- 20261021 body; the event is written first so the block row can reference it.
-- The FOR UPDATE profile lock serialises concurrent block/reactivate/appeal calls.
create or replace function public.admin_block_account(p_user_id uuid,p_reason text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); target_role text; clean text:=trim_maak_reason(p_reason); event_id uuid;
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if p_user_id is null then raise exception 'account_not_found'; end if;
 if p_user_id=me then raise exception 'cannot_block_self'; end if;
 if clean is null or char_length(clean)>500 then raise exception 'invalid_block_reason'; end if;
 select role into target_role from profiles where id=p_user_id for update;
 if not found then raise exception 'account_not_found'; end if;
 if target_role='admin' then raise exception 'cannot_block_admin'; end if;
 if exists(select 1 from account_blocks where user_id=p_user_id) then raise exception 'already_blocked'; end if;
 insert into account_moderation_events(user_id,action,reason,actor_id)
  values(p_user_id,'blocked',clean,me) returning id into event_id;
 insert into account_blocks(user_id,reason,blocked_by,block_event_id) values(p_user_id,clean,me,event_id);
end; $$;

-- 5. Member RPCs (own data only) -----------------------------------------------------
-- The caller's current block and its appeals (newest attempt first). The deciding
-- admin is never revealed to the member.
create or replace function public.my_appeal_status() returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); blk account_blocks%rowtype; used int; pending boolean; items jsonb;
begin
 if me is null then raise exception 'not_allowed'; end if;
 select * into blk from account_blocks where user_id=me;
 if not found then
  return jsonb_build_object('blocked',false,'max_appeals',3,'can_appeal',false,'unavailable_reason','account_active');
 end if;
 select count(*), coalesce(bool_or(status='pending'),false),
  coalesce(jsonb_agg(jsonb_build_object('attempt',attempt,'status',status,'message',message,
    'submitted_at',submitted_at,'decided_at',decided_at,'closed_reason',closed_reason,
    'decision_note',case when status='rejected' then decision_note end) order by attempt desc),'[]'::jsonb)
  into used, pending, items
 from account_block_appeals where block_event_id=blk.block_event_id;
 return jsonb_build_object('blocked',true,
  'block',jsonb_build_object('reason',blk.reason,'blocked_at',blk.blocked_at),
  'max_appeals',3,'appeals_used',used,'appeals_remaining',greatest(3-used,0),
  'can_appeal',not pending and used<3,
  'unavailable_reason',case when pending then 'appeal_pending' when used>=3 then 'appeal_limit_reached' end,
  'appeals',items);
end; $$;

-- Validation happens before anything is written, and any error rolls back the
-- transaction, so a failed submission never uses an attempt.
create or replace function public.submit_my_appeal(p_message text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); clean text:=trim_maak_reason(p_message); blk account_blocks%rowtype; used int;
begin
 if me is null then raise exception 'not_allowed'; end if;
 if clean is null or char_length(clean)>1000 then raise exception 'invalid_appeal_message'; end if;
 perform 1 from profiles where id=me for update;
 if not found then raise exception 'account_active'; end if;
 select * into blk from account_blocks where user_id=me for update;
 if not found then raise exception 'account_active'; end if;
 if exists(select 1 from account_block_appeals where block_event_id=blk.block_event_id and status='pending') then
  raise exception 'appeal_pending';
 end if;
 select count(*) into used from account_block_appeals where block_event_id=blk.block_event_id;
 if used>=3 then raise exception 'appeal_limit_reached'; end if;
 insert into account_block_appeals(user_id,block_event_id,attempt,message)
  values(me,blk.block_event_id,used+1,clean);
 return my_appeal_status();
end; $$;

-- 6. Admin RPCs ------------------------------------------------------------------------
create or replace function public.admin_pending_appeals() returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 return query select jsonb_build_object('appeal_id',a.id,'user_id',a.user_id,
  'full_name',p.full_name,'username',p.username,'email',u.email,'role',p.role,
  'attempt',a.attempt,'max_appeals',3,'message',a.message,'submitted_at',a.submitted_at,
  'block_reason',b.reason,'blocked_at',b.blocked_at,
  'blocked_by_name',maak_admin_label(b.blocked_by),
  'blocked_by_is_me',coalesce(b.blocked_by=auth.uid(),false))
 from account_block_appeals a
 join account_blocks b on b.block_event_id=a.block_event_id
 join profiles p on p.id=a.user_id and p.role in ('help_seeker','volunteer')
 left join auth.users u on u.id=a.user_id
 where a.status='pending'
 order by a.submitted_at;
end; $$;

-- Every appeal of one member across all of their blocks, newest first.
create or replace function public.admin_account_appeals(p_user_id uuid) returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if not exists(select 1 from profiles where id=p_user_id and role in ('help_seeker','volunteer')) then
  raise exception 'account_not_found';
 end if;
 return query select jsonb_build_object('appeal_id',a.id,'block_event_id',a.block_event_id,
  'is_current_block',exists(select 1 from account_blocks b where b.block_event_id=a.block_event_id),
  'block_reason',e.reason,'blocked_at',e.created_at,
  'attempt',a.attempt,'status',a.status,'closed_reason',a.closed_reason,'message',a.message,
  'submitted_at',a.submitted_at,'decided_at',a.decided_at,'decision_note',a.decision_note,
  'decided_by_name',case when a.decided_by is not null then maak_admin_label(a.decided_by) end,
  'decided_by_is_me',coalesce(a.decided_by=auth.uid(),false))
 from account_block_appeals a join account_moderation_events e on e.id=a.block_event_id
 where a.user_id=p_user_id
 order by a.submitted_at desc;
end; $$;

-- Approve (optional note; reactivates in this transaction) or reject (note
-- required). A second decision on the same appeal gets appeal_already_decided.
create or replace function public.admin_decide_appeal(p_appeal_id uuid,p_approve boolean,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); clean text:=trim_maak_reason(p_note); target uuid;
 appeal account_block_appeals%rowtype; blk account_blocks%rowtype;
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if p_approve is null then raise exception 'invalid_decision_note'; end if;
 if (not p_approve and clean is null) or char_length(clean)>1000 then raise exception 'invalid_decision_note'; end if;
 select user_id into target from account_block_appeals where id=p_appeal_id;
 if not found then raise exception 'appeal_not_found'; end if;
 perform 1 from profiles where id=target and role in ('help_seeker','volunteer') for update;
 if not found then raise exception 'appeal_not_found'; end if;
 select * into appeal from account_block_appeals where id=p_appeal_id for update;
 if appeal.status<>'pending' then raise exception 'appeal_already_decided'; end if;
 select * into blk from account_blocks where user_id=target for update;
 if not found or blk.block_event_id<>appeal.block_event_id then raise exception 'appeal_not_current'; end if;
 if p_approve then
  update account_block_appeals set status='approved',decided_at=now(),decided_by=me,decision_note=clean
   where id=p_appeal_id;
  delete from account_blocks where user_id=target;
  insert into account_moderation_events(user_id,action,reason,actor_id,appeal_id)
   values(target,'reactivated','Appeal approved',me,p_appeal_id);
  insert into notifications(user_id,title,body,kind) values(target,'Account reactivated',
   'Your appeal was approved and your Ma''ak account has been reactivated. Welcome back.','account');
 else
  update account_block_appeals set status='rejected',decided_at=now(),decided_by=me,decision_note=clean
   where id=p_appeal_id;
 end if;
 return jsonb_build_object('appeal_id',p_appeal_id,'status',case when p_approve then 'approved' else 'rejected' end,
  'reactivated',p_approve);
end; $$;

-- Latest: 20261022, plus appeal submissions and decisions, newest first. Within
-- one instant: event, then decision, then submission.
create or replace function public.admin_account_moderation_history(p_user_id uuid) returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if not exists(select 1 from profiles where id=p_user_id and role in ('help_seeker','volunteer')) then
  raise exception 'account_not_found';
 end if;
 return query select x.entry from (
  select e.created_at as at, 2 as rank, jsonb_build_object('id',e.id,'action',e.action,'reason',e.reason,
   'actor_name',maak_admin_label(e.actor_id),'actor_is_me',e.actor_id=auth.uid(),
   'created_at',e.created_at,'appeal_id',e.appeal_id) as entry
  from account_moderation_events e where e.user_id=p_user_id
  union all
  select a.decided_at, 1, jsonb_build_object('id',a.id::text||':decision','action','appeal_'||a.status,
   'reason',a.decision_note,'attempt',a.attempt,'closed_reason',a.closed_reason,
   'actor_name',case when a.decided_by is not null then maak_admin_label(a.decided_by) end,
   'actor_is_me',coalesce(a.decided_by=auth.uid(),false),'created_at',a.decided_at)
  from account_block_appeals a where a.user_id=p_user_id and a.status<>'pending'
  union all
  select a.submitted_at, 0, jsonb_build_object('id',a.id::text||':submitted','action','appeal_submitted',
   'reason',a.message,'attempt',a.attempt,'redacted',a.redacted_at is not null,
   'actor_name',null,'actor_is_me',false,'created_at',a.submitted_at)
  from account_block_appeals a where a.user_id=p_user_id
 ) x order by x.at desc, x.rank desc;
end; $$;

-- 7. Function privileges ------------------------------------------------------------
revoke all on function public.guard_account_block_event(),public.guard_appeal_insert(),
 public.guard_appeal_update(),public.guard_appeal_delete(),public.close_appeals_on_unblock(),
 public.redact_appeals_on_profile_delete(),public.guard_moderation_event_appeal()
 from public,anon,authenticated;
revoke all on function public.admin_block_account(uuid,text),public.my_appeal_status(),
 public.submit_my_appeal(text),public.admin_pending_appeals(),public.admin_account_appeals(uuid),
 public.admin_decide_appeal(uuid,boolean,text),public.admin_account_moderation_history(uuid)
 from public,anon;
grant execute on function public.admin_block_account(uuid,text),public.my_appeal_status(),
 public.submit_my_appeal(text),public.admin_pending_appeals(),public.admin_account_appeals(uuid),
 public.admin_decide_appeal(uuid,boolean,text),public.admin_account_moderation_history(uuid)
 to authenticated;
notify pgrst,'reload schema';
commit;
