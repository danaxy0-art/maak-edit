-- Rollback for 20261107120000_appeal_cooldown.sql.
-- Restores the 20261023 bodies of guard_appeal_insert, my_appeal_status and
-- submit_my_appeal (3 appeals per block, then no more) and the 1..3 attempt check.
-- Refuses if any appeal has attempt > 3: that history cannot fit the old rule, and
-- appeal history is never deleted. All appeal rows are kept.
begin;
set local lock_timeout = '10s';
do $$ begin
 if exists(select 1 from public.account_block_appeals where attempt > 3) then
  raise exception 'Appeals beyond attempt 3 exist; rolling back would contradict that history. Nothing changed.';
 end if;
end $$;
drop function if exists public.maak_appeal_cooldown_until(uuid);
alter table public.account_block_appeals drop constraint if exists account_block_appeals_attempt_positive;
alter table public.account_block_appeals drop constraint if exists account_block_appeals_attempt_check;
alter table public.account_block_appeals add constraint account_block_appeals_attempt_check check (attempt between 1 and 3);

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

revoke all on function public.guard_appeal_insert() from public, anon, authenticated;
revoke all on function public.my_appeal_status(), public.submit_my_appeal(text) from public, anon;
grant execute on function public.my_appeal_status(), public.submit_my_appeal(text) to authenticated;
notify pgrst, 'reload schema';
commit;
