-- POST-DEPLOY VERIFICATION for production (read-only). Run after the production
-- compat patch, and again after 20261023. Every column must be true.
-- Replaces 20261021_account_blocking_verify.sql in production: that file
-- fingerprints the repository matching function, which the patch replaces, so its
-- redefined_bodies_ok column is expected to be false there.
with expected(name,md5) as (values
 ('is_maak_admin','848df6829e6a94e25a1cf11539119aeb'),
 ('can_send_maak_message','5517008cbf6ddf1fe00249befcbaf9b0'),
 ('browse_volunteers','931c46c9ec10cff56cbc368e5c53c60a'),
 ('maak_matching_context','ea79618e0afae18b14eb05b0e2a1aec4'),
 ('my_maak_conditions','a4f919d1c4af631c765821ddd83db511'),
 ('my_support_requests','19c0dc4873f18141509020d722d8e33e'),
 ('my_support_sessions','806ba8b8db4a85097ce8c248ec081dd2')),
untouched(name,md5) as (values
 -- Production functions the deployment must not change (production export).
 ('admin_restrict_conversation','e35f98d16de40df5da9220db57732216'),
 ('admin_support_requests','91773d5611c324484b3f8c336de09594'),
 ('book_support_session','709c4025818db051f36979d820760604'))
select
 (select count(*)=7 from expected e join pg_proc p on p.proname=e.name and p.pronamespace='public'::regnamespace
   and md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g')))=e.md5) as patched_bodies_ok,
 (select position('r.status in (''pending'',''accepted'')' in prosrc)>0 and position('account_blocks' in prosrc)>0
   from pg_proc where proname='maak_matching_context' and pronamespace='public'::regnamespace) as matching_keeps_open_request_rule,
 (select position('restricted_at is null' in prosrc)>0 from pg_proc
   where proname='can_send_maak_message' and pronamespace='public'::regnamespace) as messaging_restriction_kept,
 (select count(*)=3 from untouched u join pg_proc p on p.proname=u.name and p.pronamespace='public'::regnamespace
   and md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g')))=u.md5) as production_rpcs_untouched,
 not has_function_privilege('anon','public.my_support_sessions()','execute')
  and not has_function_privilege('authenticated','public.my_support_sessions()','execute') as sessions_privileges_as_before,
 has_function_privilege('anon','public.is_maak_admin()','execute')
  and (select bool_and(has_function_privilege('authenticated',p.oid,'execute') and not has_function_privilege('anon',p.oid,'execute'))
   from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in
   ('can_send_maak_message','browse_volunteers','maak_matching_context','my_maak_conditions','my_support_requests')) as other_grants_as_before,
 (select count(*)=13 from pg_trigger where not tgisinternal and tgname in
   ('maak_blocked_actor_guard','maak_blocked_participant_guard','maak_blocked_role_guard')) as guard_triggers_ok,
 (select count(*)=3 from pg_trigger where not tgisinternal and tgname in
   ('maak_profile_guard','maak_volunteer_guard','maak_message_notification')) as production_triggers_kept,
 (select array_agg(tablename::text order by tablename)=array['messages','notifications']
   from pg_publication_tables where pubname='supabase_realtime') as realtime_unchanged,
 not has_table_privilege('authenticated','public.account_blocks','select,insert,update,delete')
  and not has_table_privilege('authenticated','public.account_moderation_events','select,insert,update,delete') as moderation_tables_private;
