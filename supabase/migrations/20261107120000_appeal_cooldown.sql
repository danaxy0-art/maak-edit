-- =====================================================================================
-- Ma'ak | SWE 444 | Sprint 3 | Appeals: repeating 90-day cooldown
-- NOT YET APPLIED anywhere. Apply after 20261023_account_appeals.sql, through the SQL
-- Editor after team approval (never `supabase db push`). Idempotent.
-- Rollback: supabase/rollbacks/20261107120000_appeal_cooldown_rollback.sql
-- Verify (read-only): supabase/checks/20261107120000_appeal_cooldown_verify.sql
-- =====================================================================================
-- Rules per blocking event (all enforced in the database with server timestamps):
--  * The first 3 appeals work exactly as before.
--  * Once 3 or more appeals exist and the latest was REJECTED, the next appeal opens
--    90 days after that rejection's decided_at (set by now() in admin_decide_appeal).
--  * Each later appeal is ONE attempt; if it is rejected, a new 90-day wait starts
--    from its own decided_at. This repeats indefinitely. No new set of 3.
--  * Still one pending appeal at a time; approval still reactivates the account;
--    nothing is unblocked automatically; history is never reset or deleted.
--  * Histories exhausted before this migration use their stored third-rejection
--    decided_at, so the wait may already be over.
-- Changes: the attempt check (1..3 -> >= 1), one internal helper, and new bodies for
-- my_appeal_status, submit_my_appeal and guard_appeal_insert. Admin RPCs, the
-- decision/redaction/close guards and the appeals table data are unchanged.
-- WARNING: re-running 20261023_account_appeals.sql replaces these three functions;
-- re-apply this file afterwards.
begin;
set local lock_timeout = '10s';

do $$ begin
 if to_regprocedure('public.submit_my_appeal(text)') is null
    or to_regclass('public.account_block_appeals') is null then
  raise exception 'Apply 20261023_account_appeals.sql first';
 end if;
end $$;

-- 1. Attempts beyond 3 are now valid (history rows are untouched).
alter table public.account_block_appeals drop constraint if exists account_block_appeals_attempt_check;
alter table public.account_block_appeals drop constraint if exists account_block_appeals_attempt_positive;
alter table public.account_block_appeals add constraint account_block_appeals_attempt_positive check (attempt >= 1);

-- 2. Internal helper: when the next appeal for a blocking event may be submitted.
-- null = no cooldown applies (fewer than 3 appeals, or the latest is not a rejection).
create or replace function public.maak_appeal_cooldown_until(p_block_event_id uuid) returns timestamptz
language sql stable security definer set search_path=public,pg_temp as $$
 select case when (select count(*) from account_block_appeals where block_event_id = p_block_event_id) >= 3
   then (select case when a.status = 'rejected' then a.decided_at + interval '90 days' end
         from account_block_appeals a where a.block_event_id = p_block_event_id
         order by a.attempt desc limit 1)
 end;
$$;

-- 3. Insert guard: same checks as 20261023 plus attempt numbering and the cooldown,
-- so no code path (RPC, SQL, service role) can skip the wait or reuse a number.
create or replace function public.guard_appeal_insert() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare used int; latest account_block_appeals%rowtype;
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
 select count(*) into used from account_block_appeals where block_event_id=new.block_event_id;
 if new.attempt <> used + 1 then raise exception 'appeal_attempt_invalid'; end if;
 if used >= 3 then
  select * into latest from account_block_appeals where block_event_id=new.block_event_id
   order by attempt desc limit 1;
  if latest.status <> 'rejected' or latest.decided_at is null
     or now() < latest.decided_at + interval '90 days' then
   raise exception 'appeal_cooldown';
  end if;
 end if;
 return new;
end; $$;

-- 4. Member status: adds the cooldown fields; keeps every existing key.
create or replace function public.my_appeal_status() returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); blk account_blocks%rowtype; used int; pending boolean; items jsonb;
 cooldown timestamptz; waiting boolean;
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
 cooldown := maak_appeal_cooldown_until(blk.block_event_id);
 waiting := not pending and used >= 3 and (cooldown is null or now() < cooldown);
 return jsonb_build_object('blocked',true,
  'block',jsonb_build_object('reason',blk.reason,'blocked_at',blk.blocked_at),
  'max_appeals',3,'appeals_used',used,
  'appeals_remaining',case when used < 3 then 3-used when pending or waiting then 0 else 1 end,
  'can_appeal',not pending and not waiting,
  'unavailable_reason',case when pending then 'appeal_pending' when waiting then 'appeal_cooldown' end,
  'cooldown_days',90,
  'in_cooldown_cycle',used >= 3,
  'cooldown_until',case when used >= 3 and not pending then cooldown end,
  'cooldown_days_remaining',case when waiting and cooldown is not null
     then greatest(1, ceil(extract(epoch from (cooldown - now())) / 86400.0)::int) end,
  'server_now',now(),
  'appeals',items);
end; $$;

-- 5. Submit: the 3-appeal stop becomes the cooldown check (the guard enforces it too).
create or replace function public.submit_my_appeal(p_message text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); clean text:=trim_maak_reason(p_message); blk account_blocks%rowtype;
 used int; cooldown timestamptz;
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
 if used >= 3 then
  cooldown := maak_appeal_cooldown_until(blk.block_event_id);
  if cooldown is null or now() < cooldown then raise exception 'appeal_cooldown'; end if;
 end if;
 insert into account_block_appeals(user_id,block_event_id,attempt,message)
  values(me,blk.block_event_id,used+1,clean);
 return my_appeal_status();
end; $$;

-- 6. Privileges (unchanged signatures keep their grants; restated for clarity).
revoke all on function public.maak_appeal_cooldown_until(uuid), public.guard_appeal_insert()
 from public, anon, authenticated;
revoke all on function public.my_appeal_status(), public.submit_my_appeal(text) from public, anon;
grant execute on function public.my_appeal_status(), public.submit_my_appeal(text) to authenticated;

notify pgrst, 'reload schema';
commit;
