-- READ-ONLY PRECHECK for the production deployment (20261021 -> production compat
-- patch -> 20261022 -> 20261023). Run in the MAIN project's SQL Editor right before
-- deploying. Every column must be true; otherwise stop and share the output.
-- It confirms production still matches the export the patch and the production
-- rollback were written from, and that the role running the deployment can replace
-- the functions (CREATE OR REPLACE requires ownership).
with fn(name,args,md5) as (values
 -- Exported production bodies, whitespace collapsed (production export, 2026-10-21).
 ('admin_restrict_conversation','p_request_id uuid, p_reason text','e35f98d16de40df5da9220db57732216'),
 ('admin_support_requests','','91773d5611c324484b3f8c336de09594'),
 ('book_support_session','p_request_id uuid, p_starts_at timestamp with time zone','709c4025818db051f36979d820760604'),
 ('browse_volunteers','','91ffc2331c9eeb8b011a4b679812d07d'),
 ('can_send_maak_message','p_request_id uuid','545eae37a00b49824835322b6667fa84'),
 ('maak_matching_context','','ad4320f1474e39eff530771c54408f7f'),
 ('my_maak_conditions','','3557ce5de05c804598101a0a6b7011f5'),
 ('my_support_requests','','43f7a365025612d1423360d4ed5d9e32'),
 ('my_support_sessions','','32228bb272a3ae9b88fee4b29f03064e'),
 -- Not in the export: the production rollback restores the repository body.
 ('is_maak_admin','','9461ab5f6d8c48dbc7b3794c9cc1e5a5')),
pol(tablename,policyname,md5) as (values
 -- Repository definitions the deployment replaces and the rollback restores.
 ('condition_review_requests','condition_requests_read','4f097a9b47c432f9a68f65d25780718b'),
 ('help_seeker_profiles','seekers_owner_read','fd421dc1ea7e4646238e38a62eb7151f'),
 ('messages','messages_read','2fc368d5d4a8c5df91281c2d391a5957'),
 ('messages','messages_send','addc1aaa76dca3584e1b78d233a42c84'),
 ('notifications','notification_read','fd421dc1ea7e4646238e38a62eb7151f'),
 ('notifications','notification_update','f7d1bdfaf4aee36e60abd045b339c1f9'),
 ('objects','maak_document_read','d6bec41d38a63b2138e332fcaab883e8'),
 ('objects','maak_document_upload','a2b3bbb54cb2884359e3bf6b3fdb031b'),
 ('profiles','profiles_insert','a5871d583f2228166a7aca0fe90bb333'),
 ('profiles','profiles_read','b7253f0e983bc093c45fc6b211c7528f'),
 ('profiles','profiles_update','d39fd8f16b69dff309abbc0605323d57'),
 ('resources','resources_read','3c187b9354949c178cf3d7d8b7c92158'),
 ('support_requests','requests_read','ad93396e2dc2c329ced84c4c713c6fc5'),
 ('support_sessions','sessions_read','65fb1f678648f5f660d27b26efc16444'),
 ('user_conditions','user_conditions_read','4f097a9b47c432f9a68f65d25780718b'),
 ('volunteer_profiles','volunteers_read','4f097a9b47c432f9a68f65d25780718b'))
select
 (select count(*)=10 from fn join pg_proc p on p.proname=fn.name and p.pronamespace='public'::regnamespace
   and pg_get_function_identity_arguments(p.oid)=fn.args
   and md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g')))=fn.md5) as functions_match_export,
 (select count(*)=10 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in (select name from fn)) as no_overloads,
 (select bool_and(pg_get_userbyid(p.proowner)=current_user) from pg_proc p
   where p.pronamespace='public'::regnamespace and p.proname in (select name from fn)) as functions_owned_by_this_role,
 has_function_privilege('anon','public.is_maak_admin()','execute')
  and (select bool_and(has_function_privilege('authenticated',p.oid,'execute') and not has_function_privilege('anon',p.oid,'execute'))
   from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in
   ('can_send_maak_message','browse_volunteers','maak_matching_context','my_maak_conditions','my_support_requests'))
  and not has_function_privilege('anon','public.my_support_sessions()','execute')
  and not has_function_privilege('authenticated','public.my_support_sessions()','execute') as grants_as_reported,
 (select count(*)=16 from pol join pg_policies p on p.tablename=pol.tablename and p.policyname=pol.policyname
   and md5(p.cmd||p.permissive||p.roles::text||coalesce(p.qual,'')||'|'||coalesce(p.with_check,''))=pol.md5) as policies_match_repository,
 (select array_agg(tgrelid::regclass::text||'.'||tgname order by tgrelid::regclass::text||'.'||tgname)=array['messages.maak_message_notification',
   'profiles.maak_profile_guard','volunteer_profiles.maak_volunteer_guard'] from pg_trigger
   where not tgisinternal and tgrelid::regclass::text in ('profiles','help_seeker_profiles','volunteer_profiles','user_conditions',
   'condition_review_requests','support_requests','support_sessions','messages','notifications')) as triggers_as_reported,
 (select array_agg(tablename::text order by tablename)=array['messages','notifications']
   from pg_publication_tables where pubname='supabase_realtime') as realtime_as_reported,
 to_regclass('public.account_blocks') is null and to_regclass('public.account_moderation_events') is null
  and to_regclass('public.account_block_appeals') is null
  and to_regprocedure('public.is_maak_active()') is null and to_regprocedure('public.maak_admin_label(uuid)') is null as nothing_installed_yet,
 (select count(*)=3 from information_schema.columns where table_schema='public' and table_name='support_requests'
   and column_name in ('restricted_at','restricted_by','restriction_reason')) as restriction_columns_present,
 not exists(select 1 from public.profiles where role is null) as every_profile_has_a_role;

-- If policies_match_repository is false, run this and share the output: policy
-- text can be printed differently by another PostgreSQL version.
-- select tablename,policyname,cmd,permissive,roles,qual,with_check from pg_policies
--  where policyname in ('profiles_read','profiles_insert','profiles_update','seekers_owner_read','volunteers_read',
--   'user_conditions_read','condition_requests_read','notification_read','notification_update','requests_read',
--   'messages_read','messages_send','sessions_read','resources_read','maak_document_upload','maak_document_read')
--  order by 1,2;
