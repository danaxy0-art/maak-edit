-- Extra data for 20261022/20261023 tests. Run after 10_seed.sql and
-- 20261021_account_blocking.sql, BEFORE the two new migrations, so blocks made
-- by the original admin_block_account exercise the block-event backfill.
-- Admins: a3 has full_name '' and no username (the confirmed maak-testing
-- case); a4 has only a chosen username; a5 only an auto-generated username;
-- a6 is deleted during the tests. Members: c4-c7, b6.
\set ON_ERROR_STOP 1
insert into auth.users(id,email,raw_user_meta_data) values
 (test.u('a3'),'a3@test','{}'),(test.u('a4'),'a4@test','{}'),
 (test.u('a5'),'a5@test','{}'),(test.u('a6'),'a6@test','{"full_name":"Departing Admin"}'),
 (test.u('c4'),'c4@test','{"full_name":"Noor Hasan"}'),(test.u('c5'),'c5@test','{"full_name":"Rami Saad"}'),
 (test.u('c6'),'c6@test','{"full_name":"Yara Malik"}'),(test.u('c7'),'c7@test','{"full_name":"Lama Aziz"}'),
 (test.u('b6'),'b6@test','{"full_name":"Dina Odeh","role":"volunteer"}');
update public.profiles set role='admin' where id in (test.u('a3'),test.u('a4'),test.u('a5'),test.u('a6'));
update public.profiles set username='moderator_lee' where id=test.u('a4');
update public.profiles set username='user_0123456789abcde' where id=test.u('a5');

-- Blocks via the original RPC, as each admin (auth.uid() from the JWT claim).
-- c6 is blocked, reactivated and blocked again: only the second block is current.
create function test.as_admin_block(p_admin text,p_user text,p_reason text) returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claims',json_build_object('sub',test.u(p_admin))::text,true);
 perform admin_block_account(test.u(p_user),p_reason);
end $$;
select test.as_admin_block('a3','c4','Spam links in messages');
select test.as_admin_block('a4','c5','Repeated harassment');
select test.as_admin_block('a5','b6','Fake volunteer credentials');
select test.as_admin_block('a6','c7','Abusive language');
select test.as_admin_block('a1','c6','First warning');
select set_config('request.jwt.claims',json_build_object('sub',test.u('a1'))::text,false);
select admin_reactivate_account(test.u('c6'),'Warning served');
select test.as_admin_block('a1','c6','Second offence');
select set_config('request.jwt.claims','',false);
