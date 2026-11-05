-- Production compatibility tests, run after the full production sequence
-- (20261021 -> production compat patch -> 20261022 -> 20261023) on a database
-- carrying the exported production definitions. Requires ../account_moderation_v2/15_harness.sql.
\set ON_ERROR_STOP 1

------------------------------------------------------------------ data and existing objects intact
select test.act('postgres',null);
select test.check('Data: every account, conversation, message, session and notification unchanged',$$
 select test.data_checksum()=(select checksum from test.baseline)$$,'true');
select test.check('Data: still 4 active conversations, none restricted',$$
 select count(*)=4 from support_requests where status='accepted' and restricted_at is null$$,'true');
select test.check('Triggers: the three production triggers are still installed',$$
 select count(*)=3 from pg_trigger where not tgisinternal and tgname in ('maak_profile_guard','maak_volunteer_guard','maak_message_notification')$$,'true');
select test.check('Constraints: support_requests has exactly the 7 production constraints',$$
 select array_agg(conname::text order by conname)=array['support_requests_check','support_requests_pkey',
  'support_requests_restricted_by_fkey','support_requests_restriction_consistent','support_requests_seeker_id_fkey',
  'support_requests_status_check','support_requests_volunteer_id_fkey']
 from pg_constraint where conrelid='public.support_requests'::regclass$$,'true');
select test.check('Constraints: restriction check is the production definition',$$
 select pg_get_constraintdef(oid) like '%length(TRIM(BOTH FROM restriction_reason))%500%'
 from pg_constraint where conname='support_requests_restriction_consistent'$$,'true');
select test.check('Constraints: a blank restriction reason is refused',$$
 update support_requests set restricted_at=now(),restriction_reason='  ' where id=test.u('e2')$$,'error:support_requests_restriction_consistent');
select test.check('Constraints: a restriction reason over 500 characters is refused',$$
 update support_requests set restricted_at=now(),restriction_reason=repeat('x',501) where id=test.u('e2')$$,'error:support_requests_restriction_consistent');
select test.check('Realtime: publication still contains exactly messages and notifications',$$
 select array_agg(tablename::text order by tablename)=array['messages','notifications'] from pg_publication_tables where pubname='supabase_realtime'$$,'true');

------------------------------------------------------------------ existing triggers still work alongside the guards
select test.as_user('c1');
select test.check('Trigger: a new message still notifies the other participant',$$
 insert into messages(request_id,sender_id,body) values(test.u('e1'),test.u('c1'),'Hello again')$$,'ok');
select test.act('postgres',null);
-- One notification came from the seed's message on e1; this message adds the second.
select test.check('Trigger: maak_message_notification wrote the notification',$$
 select count(*)=2 from notifications where user_id=test.u('b1') and kind='message' and reference_id=test.u('e1')$$,'true');
select test.as_user('c1');
select test.check('Trigger: maak_profile_guard still refuses a self-promotion',$$
 update profiles set role='admin' where id=auth.uid()$$,'error:role_not_allowed');
select test.as_user('b5');
select test.check('Trigger: maak_volunteer_guard still refuses self-approval',$$
 select test.rpc(format('update volunteer_profiles set status=''approved'' where user_id=%L',test.u('b5')))$$,'error:not_allowed');

------------------------------------------------------------------ matching keeps the production open-request rule
select test.as_user('c1');
select test.check('Matching: volunteers with an open request are still excluded',$$
 select not exists(select 1 from jsonb_array_elements(maak_matching_context()->'candidates') x
  where x->>'user_id' in (test.u('b1')::text,test.u('b2')::text))$$,'true');
select test.check('Matching: other matching volunteers are still offered',$$
 select exists(select 1 from jsonb_array_elements(maak_matching_context()->'candidates') x where x->>'user_id'=test.u('b3')::text)$$,'true');
select test.as_user('a1');
select test.check('Matching setup: block volunteer b3',$$select admin_block_account(test.u('b3'),'Compat test')$$,'ok');
select test.as_user('c1');
select test.check('Matching: a blocked volunteer is hidden',$$
 select not exists(select 1 from jsonb_array_elements(maak_matching_context()->'candidates') x where x->>'user_id'=test.u('b3')::text)$$,'true');
select test.as_user('a1');
select test.check('Matching setup: reactivate b3',$$select admin_reactivate_account(test.u('b3'))$$,'ok');
select test.check('Matching setup: block seeker c1',$$select admin_block_account(test.u('c1'),'Compat test')$$,'ok');
select test.as_user('c1');
select test.check('Matching: a blocked seeker gets account_blocked',$$select maak_matching_context()$$,'error:account_blocked');
select test.as_user('a1');
select test.check('Matching setup: reactivate c1',$$select admin_reactivate_account(test.u('c1'))$$,'ok');

------------------------------------------------------------------ conversation restriction (production RPCs)
select test.check('Restriction: admin_restrict_conversation still works',$$select admin_restrict_conversation(test.u('e3'),'Safety review')$$,'ok');
-- Counted as the owner: RLS rightly hides other users' notifications from the admin.
select test.act('postgres',null);
select test.check('Restriction: both participants notified (kind restricted)',$$
 select count(*)=2 from notifications where kind='restricted' and reference_id=test.u('e3')$$,'true');
select test.as_user('a1');
select test.check('Restriction: restricting again is refused',$$select admin_restrict_conversation(test.u('e3'),'Again')$$,'error:conversation_changed');
select test.check('Restriction: admin_support_requests reports it, with names and counts',$$
 select x->>'restriction_reason'='Safety review' and x->>'restricted_at' is not null and x->>'seeker_name'='Seeker One'
  and x->>'volunteer_name'='Vol Two' and (x->>'message_count')::int>=0
 from admin_support_requests() x where x->>'id'=test.u('e3')::text$$,'true');
select test.check('Restriction: admin_support_requests lists every request',$$
 select count(*)=(select count(*) from test.all_requests()) from admin_support_requests()$$,'true');
select test.as_user('c1');
select test.check('Restriction: messaging a restricted conversation is refused (can_send)',$$select not can_send_maak_message(test.u('e3'))$$,'true');
select test.check('Restriction: inserting a message is refused by RLS',$$
 insert into messages(request_id,sender_id,body) values(test.u('e3'),test.u('c1'),'x')$$,'error:row-level security');
select test.as_user('b2');
select test.check('Restriction: booking a session is refused',$$select book_support_session(test.u('e3'),now()+interval '3 days')$$,'error:invalid_session');
select test.as_user('b4');
select test.check('Restriction: an unrestricted conversation can still book',$$select book_support_session(test.u('e6'),now()+interval '4 days')$$,'ok');
select test.as_user('a1');
select test.check('Restriction setup: block volunteer b1',$$select admin_block_account(test.u('b1'),'Compat test')$$,'ok');
select test.check('Restriction: works when a participant is blocked',$$select admin_restrict_conversation(test.u('e1'),'Review while blocked')$$,'ok');
select test.check('Restriction setup: reactivate b1',$$select admin_reactivate_account(test.u('b1'))$$,'ok');

------------------------------------------------------------------ response fields used by Flutter
select test.as_user('c1');
select test.check('Fields: my_support_requests keeps every production field (plus contact_available)',$$
 select count(*)=2 and bool_and(x ?& array['id','seeker_id','volunteer_id','status','created_at','restricted_at',
  'restricted_by','restriction_reason','contact_name','condition','description','last_message','contact_available'])
 from my_support_requests() x$$,'true');
select test.check('Fields: browse_volunteers keys unchanged',$$
 select count(*)>0 and bool_and((select array_agg(k order by k) from jsonb_object_keys(x) k)=array['condition','description','full_name','language','user_id'])
 from browse_volunteers() x$$,'true');
select test.check('Fields: matching keys unchanged',$$
 select (select array_agg(k order by k) from jsonb_object_keys(maak_matching_context()) k)=array['candidates','general_mode','seeker']$$,'true');

------------------------------------------------------------------ my_support_sessions privileges preserved
select test.check('Sessions: authenticated still has no EXECUTE (as in production)',$$select count(*) from my_support_sessions()$$,'error:permission denied');
select test.act('postgres',null);
select test.check('Sessions: privileges identical to production (no anon, no authenticated)',$$
 select not has_function_privilege('anon','public.my_support_sessions()','execute')
  and not has_function_privilege('authenticated','public.my_support_sessions()','execute')$$,'true');

------------------------------------------------------------------ blocked users gain nothing through production RPCs
select test.as_user('a1');
select test.check('Blocked setup: block seeker c2',$$select admin_block_account(test.u('c2'),'Compat test')$$,'ok');
select test.as_user('c2');
select test.check('Blocked: admin_support_requests refused',$$select count(*) from admin_support_requests()$$,'error:not_allowed');
select test.check('Blocked: admin_restrict_conversation refused',$$select admin_restrict_conversation(test.u('e2'),'x')$$,'error:not_allowed');
select test.check('Blocked: own conversations hidden',$$select count(*)=0 from my_support_requests()$$,'true');
select test.check('Blocked: cannot message',$$insert into messages(request_id,sender_id,body) values(test.u('e2'),test.u('c2'),'x')$$,'error:account_blocked');
select test.as_user('b1');
select test.check('Blocked: counterpart cannot book with a blocked seeker',$$select book_support_session(test.u('e2'),now()+interval '5 days')$$,'error:participant_unavailable');
select test.check('Blocked: counterpart cannot message a blocked seeker',$$insert into messages(request_id,sender_id,body) values(test.u('e2'),test.u('b1'),'x')$$,'error:participant_unavailable');
select test.as_user('a1');
select test.check('Blocked setup: reactivate c2',$$select admin_reactivate_account(test.u('c2'))$$,'ok');

------------------------------------------------------------------ grants and new features
select test.act('postgres',null);
select test.check('Grants: the six other functions keep production privileges',$$
 select has_function_privilege('anon','public.is_maak_admin()','execute')
  and bool_and(has_function_privilege('authenticated',p.oid,'execute') and not has_function_privilege('anon',p.oid,'execute'))
 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in
  ('can_send_maak_message','browse_volunteers','maak_matching_context','my_maak_conditions','my_support_requests')$$,'true');
select test.as_user('a1');
select test.check('New: Manage Accounts excludes admins',$$
 select count(*)>0 and bool_and(x->>'role' in ('help_seeker','volunteer')) from admin_list_accounts() x$$,'true');
select test.check('New: existing volunteer applications still load',$$select count(*)>0 from admin_volunteer_applications()$$,'true');

select n,case when ok then 'PASS' else 'FAIL' end as result,name,detail from test.results order by n;
select count(*) filter (where ok) as passed,count(*) filter (where not ok) as failed from test.results;
