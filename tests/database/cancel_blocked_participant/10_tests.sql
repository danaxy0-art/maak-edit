-- Tests for 20261024_cancel_with_blocked_participant.sql on a production-like
-- database (see run_tests.sh). Requires ../account_moderation_v2/15_harness.sql.
-- Pending requests (ids 91-95), with b3 and c2 blocked:
--  91 c1 -> b3 (blocked volunteer)    92 c2 (blocked) -> b3 (blocked)
--  93 c3 -> b1                         94 c2 (blocked seeker) -> b4
--  95 c1 -> b4 (both active)          96 c2 (blocked) -> b2, already canceled
\set ON_ERROR_STOP 1

select test.act('postgres',null);
select test.check('Fixture: cancel_support_request is the exact production version',$$
 select md5(btrim(regexp_replace(prosrc,'[[:space:]]+',' ','g')))='35bdcd6da23a1ef6eccada2367a696d8'
 from pg_proc where oid='public.cancel_support_request(uuid)'::regprocedure$$,'true');
select test.check('Fixture: cancel_support_request privileges as in production',$$
 select has_function_privilege('authenticated','public.cancel_support_request(uuid)','execute')
  and not has_function_privilege('anon','public.cancel_support_request(uuid)','execute')$$,'true');
insert into support_requests(id,seeker_id,volunteer_id,status) values
 (test.u('91'),test.u('c1'),test.u('b3'),'pending'),(test.u('92'),test.u('c2'),test.u('b3'),'pending'),
 (test.u('93'),test.u('c3'),test.u('b1'),'pending'),(test.u('94'),test.u('c2'),test.u('b4'),'pending'),
 (test.u('95'),test.u('c1'),test.u('b4'),'pending'),(test.u('96'),test.u('c2'),test.u('b2'),'canceled');
create function test.request(p text) returns public.support_requests language sql security definer as $$
 select * from public.support_requests where id=test.u(p) $$;
grant execute on function test.request(text) to anon,authenticated;
select test.as_user('a1');
select test.check('Setup: block volunteer b3',$$select admin_block_account(test.u('b3'),'Cancel test')$$,'ok');
select test.check('Setup: block seeker c2',$$select admin_block_account(test.u('c2'),'Cancel test')$$,'ok');

------------------------------------------------------------------ the fix
select test.as_user('c1');
select test.check('Fix: seeker cancels own pending request to a blocked volunteer',$$select cancel_support_request(test.u('91'))$$,'ok');
select test.check('Fix: request is canceled; participants and restriction fields unchanged',$$
 select status='canceled' and seeker_id=test.u('c1') and volunteer_id=test.u('b3')
  and restricted_at is null and restricted_by is null and restriction_reason is null from test.request('91')$$,'true');
select test.act('postgres',null);
select test.check('Fix: the team''s cancellation notification is still created',$$
 select count(*)=1 from notifications where user_id=test.u('b3') and kind='request' and reference_id=test.u('91')$$,'true');
select test.as_user('c1');
select test.check('Fix: repeating the cancellation succeeds (production is idempotent)',$$select cancel_support_request(test.u('91'))$$,'ok');
select test.act('postgres',null);
select test.check('Fix: the repeat sent no second notification and changed nothing',$$
 select (select count(*) from notifications where reference_id=test.u('91'))=1
  and (select status='canceled' and volunteer_id=test.u('b3') from support_requests where id=test.u('91'))$$,'true');

------------------------------------------------------------------ unauthorized cancellation
select test.as_user('b3');
select test.check('Unauthorized: blocked volunteer cannot cancel a request',$$select cancel_support_request(test.u('92'))$$,'error:request_changed');
select test.as_user('c3');
select test.check('Unauthorized: another seeker cannot cancel someone else''s request',$$select cancel_support_request(test.u('92'))$$,'error:request_changed');
select test.check('Unauthorized: another seeker''s already canceled request is not reported as success',$$select cancel_support_request(test.u('91'))$$,'error:request_changed');
select test.as_user('b1');
select test.check('Unauthorized: the volunteer cannot cancel (seekers only)',$$select cancel_support_request(test.u('93'))$$,'error:request_changed');
select test.as_user('b3');
select test.check('Unauthorized: the blocked volunteer of an already canceled request gets no success',$$select cancel_support_request(test.u('91'))$$,'error:request_changed');
select test.as_user('c2');
select test.check('Unauthorized: a blocked seeker cannot cancel their own request',$$select cancel_support_request(test.u('92'))$$,'error:account_blocked');
select test.check('Idempotent path: a blocked seeker''s already canceled request returns without writing',$$select cancel_support_request(test.u('96'))$$,'ok');
select test.act('postgres',null);
select test.check('Idempotent path: nothing written for the blocked seeker (no notification, still canceled)',$$
 select (select count(*) from notifications where reference_id=test.u('96'))=0
  and (select status='canceled' from support_requests where id=test.u('96'))$$,'true');
select test.act('anon',null);
select test.check('Unauthorized: anon cannot call cancel_support_request',$$select cancel_support_request(test.u('93'))$$,'error:permission denied');
select test.act('postgres',null);
select test.check('Unauthorized: refused requests are still pending',$$
 select count(*)=3 from support_requests where id in (test.u('92'),test.u('93'),test.u('94')) and status='pending'$$,'true');

------------------------------------------------------------------ the guard exception stays narrow (simulated SECURITY DEFINER RPCs)
select test.as_user('b4');
select test.check('Narrow: a volunteer cannot set canceled past the guard on a blocked seeker''s request',
 $$select test.rpc(format('update support_requests set status=''canceled'' where id=%L',test.u('94')))$$,'error:participant_unavailable');
select test.as_user('c1');
select test.check('Narrow: a canceled request cannot be reopened with a blocked volunteer',
 $$select test.rpc(format('update support_requests set status=''pending'' where id=%L',test.u('91')))$$,'error:participant_unavailable');
select test.check('Narrow: a canceled request cannot be accepted with a blocked volunteer',
 $$select test.rpc(format('update support_requests set status=''accepted'' where id=%L',test.u('91')))$$,'error:participant_unavailable');
select test.check('Narrow: participants stay immutable',
 $$select test.rpc(format('update support_requests set volunteer_id=%L where id=%L',test.u('b4'),test.u('91')))$$,'error:request_participants_immutable');
select test.as_user('a1');
select test.check('Narrow setup: block volunteer b1',$$select admin_block_account(test.u('b1'),'Cancel test')$$,'ok');
select test.as_user('c1');
select test.check('Narrow: an accepted conversation cannot be set canceled past the guard',
 $$select test.rpc(format('update support_requests set status=''canceled'' where id=%L',test.u('e1')))$$,'error:participant_unavailable');
select test.check('Narrow: cancel_support_request refuses an accepted conversation',$$select cancel_support_request(test.u('e1'))$$,'error:request_changed');

------------------------------------------------------------------ existing blocking protections
select test.check('Blocking: no new request to a blocked volunteer',
 $$select test.rpc(format('insert into support_requests(seeker_id,volunteer_id) values(%L,%L)',test.u('c1'),test.u('b3')))$$,'error:participant_unavailable');
select test.check('Blocking: no message to a blocked participant',
 $$insert into messages(request_id,sender_id,body) values(test.u('e1'),test.u('c1'),'x')$$,'error:participant_unavailable');
select test.as_user('c2');
select test.check('Blocking: a blocked user cannot send messages',
 $$insert into messages(request_id,sender_id,body) values(test.u('e2'),test.u('c2'),'x')$$,'error:account_blocked');
select test.check('Blocking: a blocked user cannot change profile records',
 $$select test.rpc(format('update help_seeker_profiles set description=''x'' where user_id=%L',test.u('c2')))$$,'error:account_blocked');
select test.check('Blocking: a blocked user still sees no conversations',$$select count(*)=0 from my_support_requests()$$,'true');
select test.as_user('b4');
select test.check('Blocking: a volunteer cannot accept a blocked seeker''s request',$$select decide_support_request(test.u('94'),true)$$,'error:participant_unavailable');
select test.check('Blocking: declining a blocked seeker''s request is still allowed',$$select decide_support_request(test.u('94'),false)$$,'ok');

------------------------------------------------------------------ team cancellation rules and production restrictions
select test.as_user('c1');
select test.check('Team rule: cancelling a pending request between active users still works',$$select cancel_support_request(test.u('95'))$$,'ok');
select test.check('Team rule: an accepted conversation cannot be canceled',$$select cancel_support_request(test.u('e3'))$$,'error:request_changed');
select test.as_user('a1');
select test.check('Restriction: admin_restrict_conversation still works',$$select admin_restrict_conversation(test.u('e3'),'Cancel test review')$$,'ok');
select test.check('Restriction: a canceled request cannot be restricted (accepted only)',$$select admin_restrict_conversation(test.u('91'),'x')$$,'error:conversation_changed');
select test.as_user('c1');
select test.check('Restriction: a restricted conversation cannot be canceled',$$select cancel_support_request(test.u('e3'))$$,'error:request_changed');
select test.check('Restriction: it stays accepted and restricted',$$
 select status='accepted' and restriction_reason='Cancel test review' from test.request('e3')$$,'true');
select test.check('Restriction: messaging it is still refused',$$select not can_send_maak_message(test.u('e3'))$$,'true');

------------------------------------------------------------------ after reactivation
select test.as_user('a1');
select test.check('Reactivation setup: reactivate b3',$$select admin_reactivate_account(test.u('b3'))$$,'ok');
select test.as_user('c1');
select test.check('Reactivation: the canceled request stays canceled',$$select status='canceled' from test.request('91')$$,'true');
select test.check('Reactivation: a canceled request does not prevent a new one',
 $$select test.rpc(format('insert into support_requests(seeker_id,volunteer_id) values(%L,%L)',test.u('c1'),test.u('b3')))$$,'ok');

select test.act('postgres',null);
select n,case when ok then 'PASS' else 'FAIL' end as result,name,detail from test.results order by n;
select count(*) filter (where ok) as passed,count(*) filter (where not ok) as failed from test.results;
