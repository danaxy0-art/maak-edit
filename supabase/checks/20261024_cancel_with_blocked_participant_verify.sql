-- POST-DEPLOY VERIFICATION for 20261024_cancel_with_blocked_participant.sql (read-only).
-- Run in the Supabase SQL Editor after applying it. Every column must be true.
-- Before the migration is applied, guard_fixed is false and guard_was_20261021 tells
-- whether the guard is still the 20261021 version the migration expects.
select
 (select md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g')))='9da7adda0620fd2a64867e6d697cf6e3'
   from pg_proc p where p.oid=to_regprocedure('public.guard_maak_blocked_participants()')) as guard_fixed,
 (select md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g'))) in
   ('669f3519a89e02d08e8469b3828ee284','9da7adda0620fd2a64867e6d697cf6e3')
   from pg_proc p where p.oid=to_regprocedure('public.guard_maak_blocked_participants()')) as guard_was_20261021,
 (select p.prosecdef and p.proconfig=array['search_path=public, pg_temp']
   from pg_proc p where p.oid=to_regprocedure('public.guard_maak_blocked_participants()')) as guard_definer_and_search_path,
 (select count(*)=3 from pg_trigger t where not t.tgisinternal and t.tgenabled='O'
   and t.tgname='maak_blocked_participant_guard'
   and t.tgfoid='public.guard_maak_blocked_participants()'::regprocedure
   and t.tgrelid in ('public.support_requests'::regclass,'public.support_sessions'::regclass,'public.messages'::regclass)) as participant_triggers_attached,
 (select count(*)=9 from pg_trigger t where not t.tgisinternal and t.tgenabled='O'
   and t.tgname='maak_blocked_actor_guard') as actor_triggers_attached,
 (select pg_get_constraintdef(c.oid) like '%canceled%' from pg_constraint c
   where c.conrelid='public.support_requests'::regclass and c.conname='support_requests_status_check') as canceled_status_allowed,
 (to_regprocedure('public.cancel_support_request(uuid)') is not null
   and has_function_privilege('authenticated','public.cancel_support_request(uuid)','execute')
   and not has_function_privilege('anon','public.cancel_support_request(uuid)','execute')) as cancel_rpc_unchanged;
