-- READ-ONLY verification for 20261107110000_admin_lift_restriction.sql. Every column must be true.
select
 to_regclass('public.conversation_restriction_events') is not null as history_table,
 (not has_table_privilege('authenticated', 'public.conversation_restriction_events', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.conversation_restriction_events', 'select,insert,update,delete')) as history_private,
 (select count(*) = 2 from pg_trigger where tgrelid = 'public.conversation_restriction_events'::regclass
   and tgname in ('maak_restriction_events_immutable', 'maak_restriction_events_no_truncate')) as history_immutable,
 exists(select 1 from pg_trigger where tgrelid = 'public.support_requests'::regclass
   and tgname = 'maak_record_restriction_event' and tgenabled <> 'D') as restrictions_recorded,
 (select bool_and(p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')
     and not has_function_privilege('anon', p.oid, 'execute'))
   from pg_proc p where p.oid in (to_regprocedure('public.admin_lift_conversation_restriction(uuid,text)'),
                                  to_regprocedure('public.admin_conversation_restriction_history(uuid)'))) as rpcs_secured,
 not has_function_privilege('authenticated', 'public.record_maak_restriction_event()', 'execute') as trigger_fn_internal,
 not exists(select 1 from public.support_requests s where s.restricted_at is not null
   and not exists(select 1 from public.conversation_restriction_events e
                  where e.request_id = s.id and e.action = 'restricted' and e.created_at = s.restricted_at)) as current_restrictions_recorded,
 (select md5(btrim(regexp_replace(prosrc, '[[:space:]]+', ' ', 'g'))) = 'e35f98d16de40df5da9220db57732216'
   from pg_proc where oid = to_regprocedure('public.admin_restrict_conversation(uuid,text)')) as restriction_rpc_unchanged,
 (select position('restricted_at is null' in lower(prosrc)) > 0 and position('ended_at is null' in lower(prosrc)) > 0
   from pg_proc where oid = to_regprocedure('public.can_send_maak_message(uuid)')) as chat_eligibility_unchanged;
