-- Reproduces the bug before 20261024 is applied; everything is rolled back.
\set ON_ERROR_STOP 1
begin;
select test.act('postgres',null);
insert into support_requests(id,seeker_id,volunteer_id,status) values(test.u('91'),test.u('c1'),test.u('b3'),'pending');
select test.as_user('a1');
select test.check('Before fix setup: block volunteer b3',$$select admin_block_account(test.u('b3'),'Before fix')$$,'ok');
select test.as_user('c1');
select test.check('Before fix: seeker cannot cancel a pending request to a blocked volunteer (the bug)',
 $$select cancel_support_request(test.u('91'))$$,'error:participant_unavailable');
select test.act('postgres',null);
select n,case when ok then 'PASS' else 'FAIL' end as result,name,detail from test.results order by n;
rollback;
