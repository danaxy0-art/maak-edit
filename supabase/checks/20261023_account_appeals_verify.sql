-- POST-DEPLOY VERIFICATION for 20261023_account_appeals.sql (read-only).
-- Run in the Supabase SQL Editor after applying it. Every column must be true.
with expected(name,md5) as (values
 ('admin_block_account','9dc579cff6bf4b8006dafe4032f2e938'),
 ('admin_account_moderation_history','98d312048f12f1ee7157e0ac5365739c'),
 ('my_appeal_status','091886404e4fd440b55e427babdd5ba5'),
 ('submit_my_appeal','0d25f00562b1407269d71085b08bf4b1'),
 ('admin_pending_appeals','b66310f72df059750e406720811be8ba'),
 ('admin_account_appeals','521d0f34103227522ba3b561f6be9fc0'),
 ('admin_decide_appeal','7ff3afb1af831693cfd5bf913f20958f'),
 ('guard_appeal_update','b1486d67cff267d626153c415ddb50b7'),
 ('close_appeals_on_unblock','97deb36e2387d8757b94d71ba9dedc18'),
 ('redact_appeals_on_profile_delete','1c189a17e8eb667068ff53cc5c97bf24'))
select
 (select count(*)=10 from expected e join pg_proc p on p.proname=e.name
   and p.pronamespace='public'::regnamespace and md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g')))=e.md5) as function_bodies_ok,
 (select attnotnull from pg_attribute where attrelid='public.account_blocks'::regclass and attname='block_event_id') as block_event_required,
 (select count(*)=0 from public.account_blocks b left join public.account_moderation_events e on e.id=b.block_event_id
   where e.id is null or e.action<>'blocked' or e.user_id<>b.user_id) as every_block_linked_to_own_blocked_event,
 (select count(*)=0 from public.account_block_appeals a left join public.account_moderation_events e on e.id=a.block_event_id
   where e.id is null or e.action<>'blocked' or e.user_id<>a.user_id) as every_appeal_linked_to_own_blocked_event,
 (select count(*)=0 from public.account_block_appeals a where a.status='pending'
   and not exists(select 1 from public.account_blocks b where b.block_event_id=a.block_event_id)) as no_orphaned_pending_appeals,
 (select coalesce(max(n),0)<=3 from (select count(*) n from public.account_block_appeals group by block_event_id) x)
  and (select coalesce(max(n),0)<=1 from (select count(*) n from public.account_block_appeals where status='pending' group by block_event_id) y) as appeal_limits_hold,
 (select count(*)=8 from pg_trigger where not tgisinternal and tgname in ('maak_account_block_event_guard',
   'maak_appeal_insert_guard','maak_appeal_update_guard','maak_appeal_delete_guard','maak_appeal_no_truncate',
   'maak_close_appeals_on_unblock','maak_redact_appeals_on_delete','maak_moderation_event_appeal_guard')) as triggers_ok,
 (select relrowsecurity from pg_class where oid='public.account_block_appeals'::regclass)
  and (select count(*)=0 from pg_policies where schemaname='public' and tablename='account_block_appeals')
  and not has_table_privilege('authenticated','public.account_block_appeals','select,insert,update,delete')
  and not has_table_privilege('anon','public.account_block_appeals','select') as appeals_table_private,
 (select bool_and(has_function_privilege('authenticated',p.oid,'execute') and not has_function_privilege('anon',p.oid,'execute'))
   from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('my_appeal_status','submit_my_appeal',
   'admin_pending_appeals','admin_account_appeals','admin_decide_appeal')) as rpc_grants_ok,
 (select bool_and(not has_function_privilege('authenticated',p.oid,'execute'))
   from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('guard_account_block_event',
   'guard_appeal_insert','guard_appeal_update','guard_appeal_delete','close_appeals_on_unblock',
   'redact_appeals_on_profile_delete','guard_moderation_event_appeal')) as internal_functions_private;
