-- Functional tests for 20261021_account_blocking.sql. Each check runs as the role
-- and JWT subject set by test.act*(); results are collected in test.results.
\set ON_ERROR_STOP 1
create table test.results(n serial primary key,name text,ok boolean,detail text);
grant usage on schema test to anon,authenticated,service_role;
grant select,insert on test.results to anon,authenticated,service_role;
grant usage on sequence test.results_n_seq to anon,authenticated,service_role;

-- Switch to an API role with a JWT subject (null = no user).
create function test.act(p_role text,p_sub uuid) returns void language plpgsql as $$
begin
 perform set_config('role','none',false);
 perform set_config('request.jwt.claims',case when p_sub is null then json_build_object('role',p_role)::text
  else json_build_object('sub',p_sub,'role',p_role)::text end,false);
 if p_role<>'postgres' then perform set_config('role',p_role,false); end if;
end $$;
create function test.as_user(p text) returns void language sql as $$ select test.act('authenticated',test.u(p)) $$;

-- expect: 'ok' | 'true' (query returns boolean) | 'error:<substring of message>'
create function test.check(p_name text,p_sql text,p_expect text) returns void language plpgsql as $$
declare v boolean; passed boolean; detail text;
begin
 begin
  if p_expect='true' then execute p_sql into v; passed:=coalesce(v,false); detail:=coalesce(v::text,'null');
  else execute p_sql; passed:=p_expect='ok'; detail:='succeeded'; end if;
 exception when others then
  passed:=p_expect like 'error:%' and position(substr(p_expect,7) in sqlerrm)>0; detail:=sqlerrm;
 end;
 insert into test.results(name,ok,detail) values(p_name,passed,detail);
end $$;

-- Simulates a teammate SECURITY DEFINER RPC: runs as owner, auth.uid() stays the caller.
create function test.rpc(p_sql text) returns void language plpgsql security definer as $$ begin execute p_sql; end $$;
grant execute on all functions in schema test to anon,authenticated,service_role;

------------------------------------------------------------------ baseline
select test.as_user('c1');
select test.check('baseline: seeker sees volunteer b1 in browse',$$select exists(select 1 from browse_volunteers() x where x->>'user_id'=test.u('b1')::text)$$,'true');
select test.check('baseline: b1 in matching candidates',$$select maak_matching_context()->'candidates' @> jsonb_build_array(jsonb_build_object('user_id',test.u('b1')))$$,'true');
select test.check('baseline: seeker can message e1',$$select can_send_maak_message(test.u('e1'))$$,'true');
select test.check('baseline: contact_available true',$$select (x->>'contact_available')::boolean from my_support_requests() x where x->>'id'=test.u('e1')::text$$,'true');
select test.check('baseline: my_block_status not blocked',$$select my_block_status()=jsonb_build_object('blocked',false)$$,'true');

------------------------------------------------------------------ permissions on moderation RPCs
select test.check('seeker cannot block',$$select admin_block_account(test.u('b1'),'x')$$,'error:not_allowed');
select test.check('seeker cannot list accounts',$$select count(*) from admin_list_accounts()$$,'error:not_allowed');
select test.check('seeker cannot list blocked',$$select count(*) from admin_blocked_accounts()$$,'error:not_allowed');
select test.check('seeker cannot read history',$$select count(*) from admin_account_moderation_history(test.u('b1'))$$,'error:not_allowed');
select test.check('seeker cannot reactivate',$$select admin_reactivate_account(test.u('b1'))$$,'error:not_allowed');
select test.check('authenticated cannot call is_maak_account_blocked',$$select is_maak_account_blocked(test.u('b1'))$$,'error:permission denied');
select test.check('authenticated cannot call guard function',$$select trim_maak_reason('x')$$,'error:permission denied');
select test.check('authenticated cannot read account_blocks',$$select count(*) from account_blocks$$,'error:permission denied');
select test.check('authenticated cannot read events',$$select count(*) from account_moderation_events$$,'error:permission denied');
select test.check('authenticated cannot insert events',$$insert into account_moderation_events(user_id,action,reason,actor_id) values(test.u('c1'),'blocked','x',test.u('c1'))$$,'error:permission denied');
select test.check('authenticated cannot insert blocks',$$insert into account_blocks(user_id,reason) values(test.u('b1'),'x')$$,'error:permission denied');
select test.act('anon',null);
select test.check('anon cannot block',$$select admin_block_account(test.u('b1'),'x')$$,'error:permission denied');
select test.check('anon cannot call my_block_status',$$select my_block_status()$$,'error:permission denied');
select test.check('anon cannot call is_maak_active',$$select is_maak_active()$$,'error:permission denied');
select test.check('anon still reads public conditions catalogue',$$select count(*)>0 from chronic_conditions$$,'true');

------------------------------------------------------------------ block validation (admin a1)
select test.as_user('a1');
select test.check('admin cannot block self',$$select admin_block_account(test.u('a1'),'reason')$$,'error:cannot_block_self');
select test.check('admin cannot block another admin',$$select admin_block_account(test.u('a2'),'reason')$$,'error:cannot_block_admin');
select test.check('blank reason rejected',$$select admin_block_account(test.u('b1'),'   ')$$,'error:invalid_block_reason');
select test.check('whitespace-only reason (newline/tab) rejected',$$select admin_block_account(test.u('b1'),E'\n\t ')$$,'error:invalid_block_reason');
select test.check('null reason rejected',$$select admin_block_account(test.u('b1'),null)$$,'error:invalid_block_reason');
select test.check('501-char reason rejected',$$select admin_block_account(test.u('b1'),repeat('a',501))$$,'error:invalid_block_reason');
select test.check('unknown account rejected',$$select admin_block_account(test.u('99'),'reason')$$,'error:account_not_found');
select test.check('1-char reason accepted (matches Flutter)',$$select admin_block_account(test.u('b5'),'x')$$,'ok');
select test.check('500-char reason accepted',$$select admin_reactivate_account(test.u('b5'),repeat('n',500))$$,'ok');
select test.check('block b1 with padded reason',$$select admin_block_account(test.u('b1'),E'  Repeated spam\nmessages  ')$$,'ok');
select test.check('double block rejected',$$select admin_block_account(test.u('b1'),'again')$$,'error:already_blocked');
select test.act('postgres',null);
select test.check('reason stored trimmed with inner newline kept',$$select reason=E'Repeated spam\nmessages' and blocked_by=test.u('a1') from account_blocks where user_id=test.u('b1')$$,'true');
select test.check('block wrote exactly one event',$$select count(*)=1 from account_moderation_events where user_id=test.u('b1') and action='blocked'$$,'true');

------------------------------------------------------------------ blocked user b1: allowed
select test.as_user('b1');
select test.check('blocked: my_block_status shows reason, hides admin',$$select my_block_status()->>'reason'=E'Repeated spam\nmessages' and (my_block_status()->'blocked')::boolean and not (my_block_status() ? 'blocked_by')$$,'true');
select test.check('blocked: can read own profiles row (routing)',$$select count(*)=1 from profiles where id=test.u('b1')$$,'true');
select test.check('blocked: ensure_maak_profile still returns role',$$select ensure_maak_profile()='volunteer'$$,'true');
select test.check('blocked: is_maak_active false',$$select not is_maak_active()$$,'true');
------------------------------------------------------------------ blocked user b1: denied reads
select test.check('blocked: own volunteer_profiles hidden',$$select count(*)=0 from volunteer_profiles$$,'true');
select test.check('blocked: notifications hidden',$$select count(*)=0 from notifications$$,'true');
select test.check('blocked: support_requests hidden',$$select count(*)=0 from support_requests$$,'true');
select test.check('blocked: messages hidden',$$select count(*)=0 from messages$$,'true');
select test.check('blocked: sessions hidden',$$select count(*)=0 from support_sessions$$,'true');
select test.check('blocked: resources hidden',$$select count(*)=0 from resources$$,'true');
select test.check('blocked: user_conditions hidden',$$select count(*)=0 from user_conditions$$,'true');
select test.check('blocked: storage document hidden',$$select count(*)=0 from storage.objects$$,'true');
select test.check('blocked: browse_volunteers empty',$$select count(*)=0 from browse_volunteers()$$,'true');
select test.check('blocked: my_support_requests empty',$$select count(*)=0 from my_support_requests()$$,'true');
select test.check('blocked: my_support_sessions empty',$$select count(*)=0 from my_support_sessions()$$,'true');
select test.check('blocked: my_maak_conditions empty',$$select count(*)=0 from my_maak_conditions()$$,'true');
------------------------------------------------------------------ blocked user b1: denied writes
select test.check('blocked: direct profile update is a no-op',$$update profiles set full_name='Hacked' where id=test.u('b1')$$,'ok');
select test.check('blocked: profile save RPC denied',$$select save_maak_profile_reviewable('Vol One','vol_b1','volunteer',array['Diabetes'],'English','desc',null,false,false,null)$$,'error:account_blocked');
select test.check('blocked: legacy save_maak_profile denied',$$select save_maak_profile('Vol One','vol_b1','volunteer','Diabetes','English','desc',null,false)$$,'error:account_blocked');
-- BEFORE ROW triggers run before the RLS WITH CHECK, so the actor guard reports first.
select test.check('blocked: send message denied',$$insert into messages(request_id,sender_id,body) values(test.u('e1'),test.u('b1'),'hi')$$,'error:account_blocked');
select test.check('blocked: accept request denied',$$select decide_support_request(test.u('e2'),true)$$,'error:account_blocked');
select test.check('blocked: decline request denied (caller blocked)',$$select decide_support_request(test.u('e2'),false)$$,'error:account_blocked');
select test.check('blocked: book session denied',$$select book_support_session(test.u('e1'),now()+interval '5 days')$$,'error:account_blocked');
select test.check('blocked: storage upload denied',$$insert into storage.objects(bucket_id,name) values('verification-documents','b1/new.pdf')$$,'error:row-level security');
select test.check('blocked: mark notifications read is a no-op',$$update notifications set is_read=true where user_id=test.u('b1')$$,'ok');
select test.check('blocked: direct support_requests update denied',$$update support_requests set restricted_at=now() where id=test.u('e1')$$,'error:permission denied');
select test.check('blocked: definer RPC writing a message denied',$$select test.rpc(format('insert into messages(request_id,sender_id,body) values(%L,%L,%L)',test.u('e1'),test.u('b1'),'x'))$$,'error:account_blocked');
select test.check('blocked: definer RPC restricting a request denied',$$select test.rpc(format('update support_requests set restricted_at=now() where id=%L',test.u('e1')))$$,'error:account_blocked');
select test.check('blocked: definer RPC deleting a notification denied',$$select test.rpc(format('delete from notifications where user_id=%L',test.u('b1')))$$,'error:account_blocked');
select test.check('blocked: matching context denied',$$select maak_matching_context()$$,'error:not_allowed');
select test.act('postgres',null);
select test.check('blocked: profile name unchanged',$$select full_name='Vol One' from profiles where id=test.u('b1')$$,'true');

------------------------------------------------------------------ counterpart (c1 active, b1 blocked)
select test.as_user('c1');
select test.check('counterpart: blocked volunteer hidden from browse',$$select not exists(select 1 from browse_volunteers() x where x->>'user_id'=test.u('b1')::text)$$,'true');
select test.check('counterpart: other volunteers still listed',$$select exists(select 1 from browse_volunteers() x where x->>'user_id'=test.u('b2')::text)$$,'true');
select test.check('counterpart: blocked volunteer hidden from matching',$$select not (maak_matching_context()->'candidates' @> jsonb_build_array(jsonb_build_object('user_id',test.u('b1'))))$$,'true');
select test.check('counterpart: cannot message blocked contact',$$select not can_send_maak_message(test.u('e1'))$$,'true');
select test.check('counterpart: insert message to blocked contact denied',$$insert into messages(request_id,sender_id,body) values(test.u('e1'),test.u('c1'),'hi')$$,'error:participant_unavailable');
select test.check('counterpart: can still message active contact',$$insert into messages(request_id,sender_id,body) values(test.u('e3'),test.u('c1'),'hi b2')$$,'ok');
select test.check('counterpart: new request to blocked volunteer denied',$$select request_peer_support(test.u('b1'))$$,'error:participant_unavailable');
select test.check('counterpart: contact_available false',$$select not (x->>'contact_available')::boolean from my_support_requests() x where x->>'id'=test.u('e1')::text$$,'true');
select test.check('counterpart: history with blocked contact still readable',$$select count(*)=1 from messages where request_id=test.u('e1')$$,'true');

------------------------------------------------------------------ participant rules with blocked seeker c3
select test.as_user('a1');
select test.check('block seeker c3',$$select admin_block_account(test.u('c3'),'Abusive language')$$,'ok');
select test.as_user('c3');
select test.check('blocked seeker: matching denied',$$select maak_matching_context()$$,'error:account_blocked');
select test.check('blocked seeker: new request denied',$$select request_peer_support(test.u('b2'))$$,'error:account_blocked');
select test.as_user('b2');
select test.check('active volunteer can decline blocked seeker',$$select decide_support_request(test.u('e4'),false)$$,'ok');
select test.as_user('b3');
select test.check('active volunteer cannot accept blocked seeker',$$select decide_support_request(test.u('e5'),true)$$,'error:participant_unavailable');
select test.as_user('b4');
select test.check('cannot book session with blocked seeker',$$select book_support_session(test.u('e6'),now()+interval '6 days')$$,'error:participant_unavailable');
select test.check('cannot reschedule session with blocked seeker',$$select test.rpc(format('update support_sessions set starts_at=starts_at+interval ''1 hour'' where id=%L',test.u('d6')))$$,'error:participant_unavailable');
select test.check('cannot change duration with blocked seeker',$$select test.rpc(format('update support_sessions set duration_minutes=90 where id=%L',test.u('d6')))$$,'error:participant_unavailable');
select test.check('no-op session update allowed',$$select test.rpc(format('update support_sessions set starts_at=starts_at where id=%L',test.u('d6')))$$,'ok');
select test.check('participant restriction update allowed with blocked contact',$$select test.rpc(format('update support_requests set restricted_at=now(),restriction_reason=%L where id=%L','safety',test.u('e6')))$$,'ok');
select test.check('restriction update naming status=status allowed',$$select test.rpc(format('update support_requests set status=status,restricted_at=null where id=%L',test.u('e6')))$$,'ok');
select test.check('reopening a declined request with blocked seeker denied',$$select test.rpc(format('update support_requests set status=%L where id=%L','pending',test.u('e4')))$$,'error:participant_unavailable');
select test.check('seeker_id immutable',$$select test.rpc(format('update support_requests set seeker_id=%L where id=%L',test.u('c1'),test.u('e6')))$$,'error:request_participants_immutable');
select test.check('volunteer_id immutable',$$select test.rpc(format('update support_requests set volunteer_id=%L where id=%L',test.u('b1'),test.u('e6')))$$,'error:request_participants_immutable');
select test.check('message request_id immutable',$$select test.rpc(format('update messages set request_id=%L where id=%L',test.u('e3'),test.u('f6')))$$,'error:request_link_immutable');
select test.check('session request_id immutable',$$select test.rpc(format('update support_sessions set request_id=%L where id=%L',test.u('e3'),test.u('d6')))$$,'error:request_link_immutable');
select test.as_user('b2');
select test.check('switching to a blocked participant blocked by immutability',$$select test.rpc(format('update support_requests set seeker_id=%L where id=%L',test.u('c3'),test.u('e3')))$$,'error:request_participants_immutable');

------------------------------------------------------------------ admin / service-role maintenance
select test.as_user('a1');
select test.check('admin restriction works with blocked participant',$$select admin_restrict_conversation(test.u('e6'),'Safety review')$$,'ok');
select test.check('admin_support_requests still readable',$$select count(*)=6 from admin_support_requests()$$,'true');
select test.check('admin maintenance may change participants',$$select test.rpc(format('update support_requests set volunteer_id=%L where id=%L',test.u('b1'),test.u('e6')))$$,'ok');
select test.check('admin maintenance may change them back',$$select test.rpc(format('update support_requests set volunteer_id=%L where id=%L',test.u('b4'),test.u('e6')))$$,'ok');
select test.check('admin blocks pending applicant b5',$$select admin_block_account(test.u('b5'),'Hold during review')$$,'ok');
select test.check('admin can still review a blocked applicant',$$select review_volunteer_application(test.u('b5'),true,null)$$,'ok');
select test.check('admin reactivates b5',$$select admin_reactivate_account(test.u('b5'))$$,'ok');
select test.act('service_role',null);
select test.check('service role may change participants',$$update support_requests set volunteer_id=test.u('b1') where id=test.u('e6')$$,'ok');
select test.check('service role may change them back',$$update support_requests set volunteer_id=test.u('b4') where id=test.u('e6')$$,'ok');
select test.check('service role may write messages for blocked user',$$insert into messages(request_id,sender_id,body) values(test.u('e6'),test.u('c3'),'system')$$,'ok');
select test.act('postgres',null);
select test.check('restriction notifications sent to both participants',$$select count(*)=2 from notifications where reference_id=test.u('e6') and title='Conversation restricted'$$,'true');

------------------------------------------------------------------ admin listing
select test.as_user('a1');
select test.check('list accounts: all 10 profiles',$$select count(*)=10 from admin_list_accounts()$$,'true');
select test.check('list accounts: admins and self not blockable',$$select bool_and(not (x->>'can_block')::boolean) from admin_list_accounts() x where x->>'role'='admin'$$,'true');
select test.check('list accounts: blocked flagged',$$select bool_and((x->>'is_blocked')::boolean) from admin_list_accounts() x where x->>'user_id' in (test.u('b1')::text,test.u('c3')::text)$$,'true');
select test.check('blocked list: b1 and c3 with details',$$select count(*)=2 and bool_and(x->>'reason' is not null and x->>'blocked_by_name'='Admin One' and x->>'email' is not null) from admin_blocked_accounts() x$$,'true');

------------------------------------------------------------------ reactivation
select test.check('reactivate b1',$$select admin_reactivate_account(test.u('b1'),'Appeal accepted')$$,'ok');
select test.check('reactivate again rejected',$$select admin_reactivate_account(test.u('b1'))$$,'error:not_blocked');
select test.check('reactivate unknown rejected',$$select admin_reactivate_account(test.u('99'))$$,'error:account_not_found');
select test.check('history keeps block and reactivation',$$select array_agg(x->>'action' order by x->>'created_at')=array['blocked','reactivated'] from admin_account_moderation_history(test.u('b1')) x$$,'true');
select test.check('block b1 again increments times_blocked',$$select admin_block_account(test.u('b1'),'Second offence')$$,'ok');
select test.check('times_blocked is 2',$$select (x->>'times_blocked')::int=2 from admin_blocked_accounts() x where x->>'user_id'=test.u('b1')::text$$,'true');
select test.check('reactivate b1 for restore tests',$$select admin_reactivate_account(test.u('b1'))$$,'ok');
select test.as_user('b1');
select test.check('reactivated: status cleared',$$select my_block_status()=jsonb_build_object('blocked',false)$$,'true');
select test.check('reactivated: both reactivation notifications visible',$$select count(*)=2 from notifications where kind='account'$$,'true');
select test.check('reactivated: requests visible again',$$select count(*)>0 from my_support_requests()$$,'true');
select test.check('reactivated: can message e1 again',$$select can_send_maak_message(test.u('e1'))$$,'true');
select test.as_user('c1');
select test.check('reactivated: listed in browse again',$$select exists(select 1 from browse_volunteers() x where x->>'user_id'=test.u('b1')::text)$$,'true');

------------------------------------------------------------------ live restricted_at behaviour preserved
select test.as_user('a1');
select test.check('admin restricts e3',$$select admin_restrict_conversation(test.u('e3'),'Review')$$,'ok');
select test.as_user('c1');
select test.check('restricted conversation cannot be messaged (live rule kept)',$$select not can_send_maak_message(test.u('e3'))$$,'true');
select test.as_user('b2');
select test.check('restricted conversation cannot be booked (live rule kept)',$$select book_support_session(test.u('e3'),now()+interval '7 days')$$,'error:invalid_session');

------------------------------------------------------------------ history immutability and lifecycle
select test.act('postgres',null);
select test.check('history UPDATE rejected even for owner',$$update account_moderation_events set reason='edited'$$,'error:moderation_history_immutable');
select test.check('history DELETE rejected even for owner',$$delete from account_moderation_events$$,'error:moderation_history_immutable');
select test.check('history TRUNCATE rejected even for owner',$$truncate account_moderation_events$$,'error:moderation_history_immutable');
select test.act('service_role',null);
select test.check('history DELETE rejected for service_role',$$delete from account_moderation_events$$,'error:moderation_history_immutable');
select test.act('postgres',null);
select test.check('blocked account cannot be promoted to admin',$$update profiles set role='admin' where id=test.u('c3')$$,'error:account_blocked');
select test.check('direct SQL block of an admin rejected',$$insert into account_blocks(user_id,reason) values(test.u('a2'),'x')$$,'error:cannot_block_admin');
select test.check('new sign-up still creates a profile',$$insert into auth.users(id,email) values(test.u('99'),'new@test')$$,'ok');
select test.check('signup profile exists',$$select count(*)=1 from profiles where id=test.u('99')$$,'true');
select test.check('deleting a blocked account (service cascade) works',$$delete from auth.users where id=test.u('c3')$$,'ok');
select test.check('block row removed with the account',$$select count(*)=0 from account_blocks where user_id=test.u('c3')$$,'true');
select test.check('history survives account deletion',$$select count(*)=1 from account_moderation_events where user_id=test.u('c3')$$,'true');
select test.as_user('a2');
select test.check('admin a2 blocks b2',$$select admin_block_account(test.u('b2'),'Temporary hold')$$,'ok');
select test.act('postgres',null);
select test.check('deleting the blocking admin succeeds',$$delete from auth.users where id=test.u('a2')$$,'ok');
select test.check('block row kept with blocked_by null',$$select blocked_by is null from account_blocks where user_id=test.u('b2')$$,'true');

------------------------------------------------------------------ grants match expectations
select test.check('anon has no EXECUTE on new or redefined functions (except is_maak_admin)',$$
 select bool_and(not has_function_privilege('anon',p.oid,'execute')) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in
 ('is_maak_account_blocked','is_maak_active','trim_maak_reason','guard_maak_blocked_actor','guard_maak_blocked_participants',
  'guard_blocked_admin_promotion','guard_account_block_target','guard_moderation_history','admin_list_accounts','admin_blocked_accounts',
  'admin_account_moderation_history','admin_block_account','admin_reactivate_account','my_block_status','can_send_maak_message',
  'browse_volunteers','maak_matching_context','my_maak_conditions','my_support_requests','my_support_sessions')$$,'true');
select test.check('anon keeps is_maak_admin',$$select has_function_privilege('anon','public.is_maak_admin()','execute')$$,'true');
select test.check('authenticated cannot execute internal helpers',$$
 select bool_and(not has_function_privilege('authenticated',p.oid,'execute')) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in
 ('is_maak_account_blocked','trim_maak_reason','guard_maak_blocked_actor','guard_maak_blocked_participants','guard_blocked_admin_promotion',
  'guard_account_block_target','guard_moderation_history')$$,'true');
select test.check('redefined function signatures unchanged',$$
 select count(*)=7 from pg_proc p where p.pronamespace='public'::regnamespace and (p.proname,pg_get_function_identity_arguments(p.oid),pg_get_function_result(p.oid)) in
 (('is_maak_admin','','boolean'),('can_send_maak_message','p_request_id uuid','boolean'),('browse_volunteers','','SETOF jsonb'),
  ('maak_matching_context','','jsonb'),('my_maak_conditions','','SETOF jsonb'),('my_support_requests','','SETOF jsonb'),('my_support_sessions','','SETOF jsonb'))$$,'true');

select test.act('postgres',null);
select n,case when ok then 'PASS' else 'FAIL' end as result,name,detail from test.results order by n;
select count(*) filter (where ok) as passed,count(*) filter (where not ok) as failed from test.results;
