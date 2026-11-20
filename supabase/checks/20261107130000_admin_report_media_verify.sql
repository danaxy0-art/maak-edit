-- READ-ONLY verification for 20261107130000_admin_report_media.sql. Every column must
-- be true. Reads only catalog data: no files, paths, messages or member data.
with fn as (
 select p.oid, p.proname, p.prosecdef, p.proconfig,
        md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g'))) as fp
 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
), pol as (
 select policyname, cmd, roles::text as roles, coalesce(qual,'') as qual, coalesce(with_check,'') as with_check
 from pg_policies where schemaname = 'storage' and tablename = 'objects'
)
select
 -- New objects
 exists(select 1 from fn where oid = to_regprocedure('public.can_admin_view_report_media(text)')
   and prosecdef and array_to_string(proconfig, ',') like '%search_path=public%')            as admin_media_rule_secured,
 exists(select 1 from fn where oid = to_regprocedure('public.admin_report_media(uuid)')
   and prosecdef and array_to_string(proconfig, ',') like '%search_path=public%')            as admin_media_rpc_secured,
 (has_function_privilege('authenticated', 'public.admin_report_media(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.can_admin_view_report_media(text)', 'execute')
  and not has_function_privilege('anon', 'public.admin_report_media(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.can_admin_view_report_media(text)', 'execute')) as grants_ok,
 (not has_function_privilege('authenticated', 'public.maak_report_media_item(text,text,integer,boolean)', 'execute')
  and not has_function_privilege('anon', 'public.maak_report_media_item(text,text,integer,boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.maak_report_media_mime(text)', 'execute')) as internal_helpers_private,
 exists(select 1 from pol where policyname = 'maak_chat_media_admin_report_read' and cmd = 'SELECT'
   and roles = '{authenticated}' and qual like '%chat-media%' and qual like '%can_admin_view_report_media(name)%') as admin_read_policy,
 -- The Admin rule is used by exactly one policy, and that policy only reads.
 (select count(*) from pol where qual like '%can_admin_view_report_media%'
    or with_check like '%can_admin_view_report_media%') = 1                                   as admin_policy_read_only,
 -- Unchanged: bucket, participant policies, participant rule, report details.
 exists(select 1 from storage.buckets where id = 'chat-media' and public = false)             as bucket_still_private,
 (exists(select 1 from pol where policyname = 'maak_chat_media_read' and cmd = 'SELECT'
    and qual like '%can_access_maak_media(name, false)%')
  and exists(select 1 from pol where policyname = 'maak_chat_media_upload' and cmd = 'INSERT'
    and with_check like '%can_access_maak_media(name, true)%')
  and exists(select 1 from pol where policyname = 'maak_chat_media_orphan_delete' and cmd = 'DELETE')) as participant_policies_kept,
 exists(select 1 from fn where oid = to_regprocedure('public.can_access_maak_media(text,boolean)')
   and fp = 'f0f06df0363159d4e0345138608ffc5a')                                               as participant_rule_unchanged,
 exists(select 1 from fn where oid = to_regprocedure('public.admin_report_details(uuid)')
   and fp = '83a1356eae6ac9d248069bacce3e2c6c')                                               as report_details_unchanged;
