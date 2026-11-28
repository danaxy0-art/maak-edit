-- POST-DEPLOY VERIFICATION for 20261021_account_blocking.sql (read-only).
-- Run in the Supabase SQL Editor after applying the migration. Every column must be
-- true. The fingerprints are of the migration's function bodies with whitespace
-- collapsed; if the migration changes, recompute them.
with redefined(name,md5) as (values
 ('is_maak_admin','848df6829e6a94e25a1cf11539119aeb'),('can_send_maak_message','5517008cbf6ddf1fe00249befcbaf9b0'),
 ('browse_volunteers','931c46c9ec10cff56cbc368e5c53c60a'),('maak_matching_context','347c7cb7e7a882770222edbfeafe81ea'),
 ('my_maak_conditions','a4f919d1c4af631c765821ddd83db511'),('my_support_requests','19c0dc4873f18141509020d722d8e33e'),
 ('my_support_sessions','806ba8b8db4a85097ce8c248ec081dd2'))
select
 (select count(*) from pg_trigger where not tgisinternal and tgname in
   ('maak_blocked_actor_guard','maak_blocked_participant_guard','maak_blocked_role_guard'))=13 as guard_triggers_ok,
 (select count(*) from pg_policies where (schemaname='public' and tablename in ('profiles','help_seeker_profiles',
   'volunteer_profiles','user_conditions','condition_review_requests','notifications','support_requests','messages',
   'support_sessions','resources')) or (schemaname='storage' and tablename='objects'))=17 as policy_count_ok,
 to_regclass('public.account_blocks') is not null and to_regclass('public.account_moderation_events') is not null as tables_ok,
 (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname in ('is_maak_account_blocked',
   'is_maak_active','trim_maak_reason','guard_moderation_history','guard_account_block_target','guard_maak_blocked_actor',
   'guard_maak_blocked_participants','guard_blocked_admin_promotion','admin_list_accounts','admin_blocked_accounts',
   'admin_account_moderation_history','admin_block_account','admin_reactivate_account','my_block_status'))=14 as new_functions_ok,
 (select count(*)=7 from redefined r join pg_proc p on p.proname=r.name and p.pronamespace='public'::regnamespace
   and md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g')))=r.md5) as redefined_bodies_ok,
 (select position('restricted_at is null' in prosrc)>0 from pg_proc where proname='can_send_maak_message'
   and pronamespace='public'::regnamespace) as live_restriction_kept,
 not has_function_privilege('anon','public.admin_block_account(uuid,text)','execute')
   and has_function_privilege('authenticated','public.admin_block_account(uuid,text)','execute')
   and not has_function_privilege('authenticated','public.is_maak_account_blocked(uuid)','execute')
   and has_function_privilege('anon','public.is_maak_admin()','execute') as function_grants_ok,
 not has_table_privilege('authenticated','public.account_moderation_events','select,insert,update,delete')
   and not has_table_privilege('authenticated','public.account_blocks','select,insert,update,delete')
   and not has_table_privilege('anon','public.account_blocks','select') as tables_private_ok;
