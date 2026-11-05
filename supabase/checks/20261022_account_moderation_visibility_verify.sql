-- POST-DEPLOY VERIFICATION for 20261022_account_moderation_visibility.sql (read-only).
-- Run in the Supabase SQL Editor after applying it. Every column must be true.
-- Fingerprints are of the migration's function bodies with whitespace collapsed;
-- admin_account_moderation_history may already carry the 20261023 version.
with expected(name,md5) as (values
 ('maak_admin_label','7fe13bd0737c3c37ecf0b329b4d74336'),
 ('admin_list_accounts','c59c9fb95f8411a9e0852ae2af684906'),
 ('admin_blocked_accounts','e61d7c0256bf4e0433f5306a1c201a11'),
 ('admin_account_moderation_history','4a1646d4cc409f9a08ab54ba3cb56a4e'),
 ('admin_account_moderation_history','98d312048f12f1ee7157e0ac5365739c'))
select
 (select count(distinct e.name)=4 from expected e join pg_proc p on p.proname=e.name
   and p.pronamespace='public'::regnamespace and md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g')))=e.md5) as function_bodies_ok,
 (select qual='(id = auth.uid())' and cmd='SELECT' and roles='{authenticated}' from pg_policies
   where schemaname='public' and tablename='profiles' and policyname='profiles_read') as profiles_read_own_row_only,
 (select count(*)=3 from pg_policies where schemaname='public' and tablename='profiles') as profiles_policy_count_ok,
 not has_function_privilege('authenticated','public.maak_admin_label(uuid)','execute')
  and not has_function_privilege('anon','public.maak_admin_label(uuid)','execute') as label_helper_private,
 has_function_privilege('authenticated','public.admin_list_accounts()','execute')
  and not has_function_privilege('anon','public.admin_list_accounts()','execute')
  and not has_function_privilege('anon','public.admin_blocked_accounts()','execute')
  and not has_function_privilege('anon','public.admin_account_moderation_history(uuid)','execute') as rpc_grants_ok,
 (select coalesce(bool_and(public.maak_admin_label(b.blocked_by) <> ''),true) from public.account_blocks b) as every_block_has_a_label;
