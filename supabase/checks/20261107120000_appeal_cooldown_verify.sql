-- READ-ONLY verification for 20261107120000_appeal_cooldown.sql. Every column must be true.
select
 to_regprocedure('public.maak_appeal_cooldown_until(uuid)') is not null as cooldown_helper,
 not has_function_privilege('authenticated', 'public.maak_appeal_cooldown_until(uuid)', 'execute') as helper_internal,
 (select position('appeal_cooldown' in prosrc) > 0 and position('appeal_attempt_invalid' in prosrc) > 0
   from pg_proc where oid = to_regprocedure('public.guard_appeal_insert()')) as insert_guard_enforces_cooldown,
 (select position('appeal_cooldown' in prosrc) > 0 and position('appeal_limit_reached' in prosrc) = 0
   from pg_proc where oid = to_regprocedure('public.submit_my_appeal(text)')) as submit_uses_cooldown,
 (select position('cooldown_days_remaining' in prosrc) > 0
   from pg_proc where oid = to_regprocedure('public.my_appeal_status()')) as status_reports_cooldown,
 exists(select 1 from pg_constraint where conrelid = 'public.account_block_appeals'::regclass
   and conname = 'account_block_appeals_attempt_positive') as attempts_beyond_three_allowed,
 not exists(select 1 from pg_constraint where conrelid = 'public.account_block_appeals'::regclass
   and contype = 'c' and pg_get_constraintdef(oid) ilike '%attempt%<= 3%') as old_three_cap_removed,
 exists(select 1 from pg_indexes where indexname = 'one_pending_appeal_per_block') as one_pending_kept,
 (select count(*) = 3 from pg_trigger where tgrelid = 'public.account_block_appeals'::regclass
   and tgname in ('maak_appeal_update_guard', 'maak_appeal_delete_guard', 'maak_appeal_no_truncate')) as history_guards_kept,
 (select has_function_privilege('authenticated', 'public.submit_my_appeal(text)', 'execute')
     and not has_function_privilege('anon', 'public.submit_my_appeal(text)', 'execute')) as submit_grants;
