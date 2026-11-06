-- READ-ONLY verification for 20261106100000_admin_report_management.sql.
-- Safe on any database, including production. Every column must be true.
select
 (select count(*) = 4 from pg_proc where pronamespace = 'public'::regnamespace and proname in
   ('admin_list_reports','admin_report_details','admin_dismiss_report','admin_end_reported_conversation')) as admin_rpcs_installed,
 (select bool_and(has_function_privilege('authenticated', p.oid, 'execute')
     and not has_function_privilege('anon', p.oid, 'execute') and p.prosecdef)
   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
   ('admin_list_reports','admin_report_details','admin_dismiss_report','admin_end_reported_conversation')) as admin_rpcs_secured,
 (select bool_and(not has_function_privilege('authenticated', p.oid, 'execute'))
   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
   ('guard_maak_report_change','guard_maak_report_decision','maak_report_member','maak_report_card')) as helpers_internal,
 (select pg_get_constraintdef(oid) like '%conversation_ended%' from pg_constraint
   where conname = 'reports_status_check' and conrelid = 'public.reports'::regclass) as status_extended,
 not exists(select 1 from information_schema.columns where table_schema = 'public' and table_name = 'reports'
   and column_name in ('decided_by','decided_at','decision_note')) as reports_columns_unchanged,
 (not has_table_privilege('authenticated', 'public.report_decisions', 'select,insert,update,delete')
   and not has_table_privilege('anon', 'public.report_decisions', 'select,insert,update,delete')) as decisions_private,
 (select count(*) = 2 from pg_trigger where tgrelid = 'public.reports'::regclass
   and tgname in ('maak_report_guard','maak_report_no_truncate')) as evidence_guarded,
 (select count(*) = 2 from pg_trigger where tgrelid = 'public.report_decisions'::regclass
   and tgname in ('maak_report_decision_guard','maak_report_decision_no_truncate')) as decisions_guarded,
 not has_table_privilege('authenticated', 'public.reports', 'insert,update,delete') as reports_read_only,
 (select md5(btrim(regexp_replace(prosrc, '[[:space:]]+', ' ', 'g'))) = 'e35f98d16de40df5da9220db57732216'
   from pg_proc where oid = to_regprocedure('public.admin_restrict_conversation(uuid,text)')) as restriction_rpc_unchanged,
 (select position('restricted_at is null' in lower(prosrc)) > 0 from pg_proc
   where oid = to_regprocedure('public.can_send_maak_message(uuid)')) as messaging_respects_restriction,
 to_regprocedure('public.report_maak_message(uuid,text,text)') is not null as member_reporting_kept;
