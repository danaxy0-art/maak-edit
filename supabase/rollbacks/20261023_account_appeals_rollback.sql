-- ROLLBACK for supabase/migrations/20261023_account_appeals.sql. Run once, as one
-- transaction, in the Supabase SQL Editor. Restores the 20261022 state of every
-- function the migration redefined and removes the appeal RPCs, so the app can
-- no longer submit or decide appeals.
--
-- Kept on purpose (retained appeal history stays protected and consistent):
--  * the account_block_appeals table and its data, closed to clients;
--  * its append-only guards and the redaction-on-account-deletion trigger;
--  * the trigger closing a pending appeal when its block ends;
--  * account_blocks.block_event_id (now nullable again) with its link guard,
--    and account_moderation_events.appeal_id with its guard.
-- Remove those too with the optional block at the end, after exporting data.
-- Tested: restores every other object exactly (tests/database/account_moderation_v2).
begin;
set local lock_timeout = '10s';

-- 1. Remove the appeal RPCs (callers get "function does not exist").
drop function if exists public.my_appeal_status();
drop function if exists public.submit_my_appeal(text);
drop function if exists public.admin_pending_appeals();
drop function if exists public.admin_account_appeals(uuid);
drop function if exists public.admin_decide_appeal(uuid,boolean,text);

-- 2. The 20261021 admin_block_account does not set block_event_id.
alter table public.account_blocks alter column block_event_id drop not null;

-- 3. Restore admin_block_account exactly as in 20261021.
create or replace function public.admin_block_account(p_user_id uuid,p_reason text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); target_role text; clean text:=trim_maak_reason(p_reason);
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if p_user_id is null then raise exception 'account_not_found'; end if;
 if p_user_id=me then raise exception 'cannot_block_self'; end if;
 if clean is null or char_length(clean)>500 then raise exception 'invalid_block_reason'; end if;
 select role into target_role from profiles where id=p_user_id for update;
 if not found then raise exception 'account_not_found'; end if;
 if target_role='admin' then raise exception 'cannot_block_admin'; end if;
 insert into account_blocks(user_id,reason,blocked_by) values(p_user_id,clean,me) on conflict(user_id) do nothing;
 if not found then raise exception 'already_blocked'; end if;
 insert into account_moderation_events(user_id,action,reason,actor_id) values(p_user_id,'blocked',clean,me);
end; $$;

-- 4. Restore admin_account_moderation_history exactly as in 20261022.
create or replace function public.admin_account_moderation_history(p_user_id uuid) returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if not exists(select 1 from profiles where id=p_user_id and role in ('help_seeker','volunteer')) then
  raise exception 'account_not_found';
 end if;
 return query select jsonb_build_object('id',e.id,'action',e.action,'reason',e.reason,
  'actor_name',maak_admin_label(e.actor_id),'actor_is_me',e.actor_id=auth.uid(),'created_at',e.created_at)
 from account_moderation_events e
 where e.user_id=p_user_id order by e.created_at desc;
end; $$;

revoke all on function public.admin_block_account(uuid,text),public.admin_account_moderation_history(uuid) from public,anon;
grant execute on function public.admin_block_account(uuid,text),public.admin_account_moderation_history(uuid) to authenticated;
notify pgrst,'reload schema';
commit;

-- OPTIONAL, run separately only after exporting account_block_appeals (this
-- destroys appeal history and returns the schema exactly to 20261022):
-- begin;
-- drop trigger if exists maak_redact_appeals_on_delete on public.profiles;
-- drop trigger if exists maak_close_appeals_on_unblock on public.account_blocks;
-- drop trigger if exists maak_account_block_event_guard on public.account_blocks;
-- drop trigger if exists maak_moderation_event_appeal_guard on public.account_moderation_events;
-- drop table if exists public.account_block_appeals;
-- drop index if exists public.account_blocks_block_event_unique;
-- alter table public.account_blocks drop column if exists block_event_id;
-- alter table public.account_moderation_events drop column if exists appeal_id;
-- drop function if exists public.guard_account_block_event();
-- drop function if exists public.guard_appeal_insert();
-- drop function if exists public.guard_appeal_update();
-- drop function if exists public.guard_appeal_delete();
-- drop function if exists public.close_appeals_on_unblock();
-- drop function if exists public.redact_appeals_on_profile_delete();
-- drop function if exists public.guard_moderation_event_appeal();
-- commit;
