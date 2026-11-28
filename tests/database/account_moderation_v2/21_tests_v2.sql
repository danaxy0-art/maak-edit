-- Functional and security tests for 20261022 (visibility, labels) and 20261023
-- (appeals). Requires 11_seed_v2.sql and 15_harness.sql. Results: test.results.
\set ON_ERROR_STOP 1

------------------------------------------------------------------ A: admins hidden
select test.as_user('a1');
select test.check('A list: only help seekers and volunteers',$$
 select count(*)>0 and bool_and(x->>'role' in ('help_seeker','volunteer')) from admin_list_accounts() x$$,'true');
select test.check('A list: no admin ids or admin emails',$$
 select not exists(select 1 from admin_list_accounts() x where x->>'user_id' in
  (select test.u(i)::text from unnest(array['a1','a2','a3','a4','a5','a6']) i)
  or x->>'email' like 'a_@test')$$,'true');
select test.check('A blocked list: members only, no blocker uuid',$$
 select count(*)=5 and bool_and(x->>'role' in ('help_seeker','volunteer') and not (x ? 'blocked_by')) from admin_blocked_accounts() x$$,'true');
select test.check('A history: admin target is account_not_found',$$select count(*) from admin_account_moderation_history(test.u('a2'))$$,'error:account_not_found');
select test.check('A history: unknown target is account_not_found',$$select count(*) from admin_account_moderation_history(test.u('99'))$$,'error:account_not_found');
select test.check('A history: no actor_id key',$$select bool_and(not (x ? 'actor_id')) from admin_account_moderation_history(test.u('c6')) x$$,'true');
select test.check('A label helper not callable by clients',$$select maak_admin_label(test.u('a1'))$$,'error:permission denied');

------------------------------------------------------------------ A: profiles_read own row only
select test.check('A profiles: admin reads only own row',$$select count(*)=1 and min(id::text)=test.u('a1')::text from profiles$$,'true');
select test.check('A profiles: admin cannot read another admin',$$select count(*)=0 from profiles where id=test.u('a2')$$,'true');
select test.check('A profiles: admin cannot read a member directly',$$select count(*)=0 from profiles where id=test.u('c1')$$,'true');
select test.check('A profiles: admin own role still readable (AuthGate)',$$select role='admin' from profiles where id=auth.uid()$$,'true');
select test.as_user('c1');
select test.check('A profiles: member reads only own row',$$select count(*)=1 from profiles$$,'true');
select test.as_user('c6');
select test.check('A profiles: blocked member still reads own role',$$select role='help_seeker' from profiles where id=auth.uid()$$,'true');

------------------------------------------------------------------ A: verified labels
select test.as_user('a1');
select test.check('A label: unnamed admin, no username -> Administrator',$$
 select x->>'blocked_by_name'='Administrator' from admin_blocked_accounts() x where x->>'user_id'=test.u('c4')::text$$,'true');
select test.check('A label: chosen username used when no name',$$
 select x->>'blocked_by_name'='moderator_lee' from admin_blocked_accounts() x where x->>'user_id'=test.u('c5')::text$$,'true');
select test.check('A label: auto-generated username ignored -> Administrator',$$
 select x->>'blocked_by_name'='Administrator' from admin_blocked_accounts() x where x->>'user_id'=test.u('b6')::text$$,'true');
select test.check('A label: named admin uses trimmed full name',$$
 select x->>'blocked_by_name'='Admin One' from admin_blocked_accounts() x where x->>'user_id'=test.u('c6')::text$$,'true');
select test.check('A label: (you) flag true for the blocking admin',$$
 select (x->>'blocked_by_is_me')::boolean from admin_blocked_accounts() x where x->>'user_id'=test.u('c6')::text$$,'true');
select test.check('A label: (you) flag false for another admin''s block',$$
 select not (x->>'blocked_by_is_me')::boolean from admin_blocked_accounts() x where x->>'user_id'=test.u('c4')::text$$,'true');
select test.as_user('a2');
select test.check('A label: multiple admins -> a2 is not the blocker of c6',$$
 select x->>'blocked_by_name'='Admin One' and not (x->>'blocked_by_is_me')::boolean from admin_blocked_accounts() x where x->>'user_id'=test.u('c6')::text$$,'true');
select test.check('A label: history actor labels and is_me per caller',$$
 select bool_and(x->>'actor_name'='Admin One' and not (x->>'actor_is_me')::boolean)
 from admin_account_moderation_history(test.u('c6')) x where x->>'action' in ('blocked','reactivated')$$,'true');
select test.act('postgres',null);
select test.check('A label: deleting the blocking admin succeeds',$$delete from auth.users where id=test.u('a6')$$,'ok');
select test.as_user('a1');
select test.check('A label: deleted blocker -> Former administrator',$$
 select x->>'blocked_by_name'='Former administrator' from admin_blocked_accounts() x where x->>'user_id'=test.u('c7')::text$$,'true');
select test.check('A label: deleted actor in history -> Former administrator',$$
 select x->>'actor_name'='Former administrator' from admin_account_moderation_history(test.u('c7')) x where x->>'action'='blocked'$$,'true');

------------------------------------------------------------------ A: existing admin features still work
select test.check('A regression: volunteer applications RPC',$$select count(*)>0 from admin_volunteer_applications()$$,'true');
select test.check('A regression: condition requests RPC',$$select count(*)>=0 from admin_condition_requests()$$,'true');
select test.check('A regression: chronic conditions readable',$$select count(*)>0 from chronic_conditions$$,'true');
select test.check('A regression: is_maak_admin',$$select is_maak_admin()$$,'true');
select test.check('A protection: admins still cannot be blocked',$$select admin_block_account(test.u('a2'),'x')$$,'error:cannot_block_admin');
select test.check('A protection: admins have no block to reactivate',$$select admin_reactivate_account(test.u('a2'))$$,'error:not_blocked');

------------------------------------------------------------------ B: backfill and event link integrity
select test.act('postgres',null);
select test.check('B backfill: every block linked to its own blocked event',$$
 select count(*)=0 from account_blocks b left join account_moderation_events e on e.id=b.block_event_id
 where e.id is null or e.action<>'blocked' or e.user_id<>b.user_id or e.created_at<>b.blocked_at$$,'true');
select test.check('B backfill: re-blocked c6 links to the second block',$$
 select e.reason='Second offence' from account_blocks b join account_moderation_events e on e.id=b.block_event_id where b.user_id=test.u('c6')$$,'true');
select test.check('B link: cannot change a block''s event',$$
 update account_blocks set block_event_id=(select block_event_id from account_blocks where user_id=test.u('c5')) where user_id=test.u('c4')$$,'error:block_event_immutable');
select test.check('B link: event of another user rejected',$$
 update account_blocks set user_id=test.u('c3') where user_id=test.u('c4')$$,'error:block_event_mismatch');
select test.check('B link: a reactivated event is not a block event',$$
 insert into account_blocks(user_id,reason,block_event_id) values(test.u('c1'),'x',
  (select id from account_moderation_events where action='reactivated' and user_id=test.u('c6') limit 1))$$,'error:block_event_mismatch');
select test.check('B link: missing event rejected (NOT NULL)',$$insert into account_blocks(user_id,reason) values(test.u('c1'),'x')$$,'error:block_event_id');
select test.check('B link: admin target still cannot_block_admin',$$insert into account_blocks(user_id,reason) values(test.u('a2'),'x')$$,'error:cannot_block_admin');

------------------------------------------------------------------ B: member side
select test.as_user('c6');
select test.check('B status: blocked, 3 remaining, can appeal',$$
 select (s->>'blocked')::boolean and (s->>'appeals_remaining')::int=3 and (s->>'can_appeal')::boolean
  and s->'block'->>'reason'='Second offence' from my_appeal_status() s$$,'true');
select test.check('B submit: blank rejected',$$select submit_my_appeal(E'  \n ')$$,'error:invalid_appeal_message');
select test.check('B submit: null rejected',$$select submit_my_appeal(null)$$,'error:invalid_appeal_message');
select test.check('B submit: 1001 chars rejected',$$select submit_my_appeal(repeat('a',1001))$$,'error:invalid_appeal_message');
select test.check('B submit: failures used no attempt',$$select (my_appeal_status()->>'appeals_used')::int=0$$,'true');
select test.check('B submit: 1000 chars after trimming accepted',$$select submit_my_appeal('  '||repeat('a',1000)||'  ')$$,'ok');
select test.check('B submit: stored trimmed',$$select char_length((test.appeal('c6',1)).message)=1000$$,'true');
select test.check('B submit: second while pending -> appeal_pending',$$select submit_my_appeal('again')$$,'error:appeal_pending');
select test.check('B status: pending blocks submission',$$
 select not (s->>'can_appeal')::boolean and s->>'unavailable_reason'='appeal_pending' and (s->>'appeals_remaining')::int=2 from my_appeal_status() s$$,'true');
select test.check('B member: admin appeal RPCs denied',$$select count(*) from admin_pending_appeals()$$,'error:not_allowed');
select test.check('B member: cannot decide',$$select admin_decide_appeal(test.appeal_id('c6'),true)$$,'error:not_allowed');
select test.check('B member: no direct read of appeals',$$select count(*) from account_block_appeals$$,'error:permission denied');
select test.check('B member: no direct insert of appeals',$$insert into account_block_appeals(user_id,block_event_id,attempt,message) values(auth.uid(),gen_random_uuid(),1,'x')$$,'error:permission denied');
select test.check('B member: still blocked from messages',$$select count(*)=0 from messages$$,'true');
select test.check('B member: still blocked from volunteers',$$select count(*)=0 from browse_volunteers()$$,'true');
select test.check('B member: still blocked from sessions',$$select count(*)=0 from my_support_sessions()$$,'true');
select test.check('B member: still cannot write notifications',$$update notifications set is_read=true$$,'ok');
select test.as_user('c1');
select test.check('B active member: status says account_active',$$select my_appeal_status()->>'unavailable_reason'='account_active'$$,'true');
select test.check('B active member: cannot submit',$$select submit_my_appeal('hello')$$,'error:account_active');
select test.act('anon',null);
select test.check('B anon: cannot read status',$$select my_appeal_status()$$,'error:permission denied');
select test.check('B anon: cannot submit',$$select submit_my_appeal('x')$$,'error:permission denied');

------------------------------------------------------------------ B: admin review, rejections, limit
select test.as_user('a1');
select test.check('B admin: pending list shows c6 with block context',$$
 select x->>'attempt'='1' and x->>'block_reason'='Second offence' and x->>'blocked_by_name'='Admin One'
  and (x->>'blocked_by_is_me')::boolean and x->>'email'='c6@test' from admin_pending_appeals() x where x->>'user_id'=test.u('c6')::text$$,'true');
select test.check('B admin: reject needs a note',$$select admin_decide_appeal(test.appeal_id('c6'),false,'  ')$$,'error:invalid_decision_note');
select test.check('B admin: note over 1000 rejected',$$select admin_decide_appeal(test.appeal_id('c6'),true,repeat('n',1001))$$,'error:invalid_decision_note');
select test.check('B admin: reject with note',$$select admin_decide_appeal(test.appeal_id('c6'),false,'Evidence confirms the messages.')$$,'ok');
select test.check('B admin: second decision -> already decided',$$select admin_decide_appeal(test.appeal_id('c6'),true)$$,'error:appeal_already_decided');
select test.check('B admin: unknown appeal',$$select admin_decide_appeal(gen_random_uuid(),true)$$,'error:appeal_not_found');
select test.check('B reject: account stays blocked',$$select test.blocked('c6')$$,'true');
select test.as_user('c6');
select test.check('B member: sees rejection note, 2 remaining, can appeal again',$$
 select s->'appeals'->0->>'status'='rejected' and s->'appeals'->0->>'decision_note'='Evidence confirms the messages.'
  and (s->>'appeals_remaining')::int=2 and (s->>'can_appeal')::boolean and not (s->'appeals'->0 ? 'decided_by') from my_appeal_status() s$$,'true');
select test.check('B attempt 2 submitted',$$select submit_my_appeal('Second appeal')$$,'ok');
select test.as_user('a2');
select test.check('B attempt 2 rejected by another admin',$$select admin_decide_appeal(test.appeal_id('c6'),false,'Still not resolved.')$$,'ok');
select test.as_user('c6');
select test.check('B attempt 3 submitted',$$select submit_my_appeal('Third appeal')$$,'ok');
select test.as_user('a1');
select test.check('B attempt 3 rejected',$$select admin_decide_appeal(test.appeal_id('c6'),false,'Final decision.')$$,'ok');
select test.as_user('c6');
select test.check('B limit: no further appeals for this block',$$
 select not (s->>'can_appeal')::boolean and s->>'unavailable_reason'='appeal_limit_reached' and (s->>'appeals_remaining')::int=0 from my_appeal_status() s$$,'true');
select test.check('B limit: fourth submission refused',$$select submit_my_appeal('Fourth')$$,'error:appeal_limit_reached');
select test.act('postgres',null);
select test.check('B limit: direct attempt 4 violates the check',$$
 insert into account_block_appeals(user_id,block_event_id,attempt,message)
 select user_id,block_event_id,4,'x' from account_blocks where user_id=test.u('c6')$$,'error:attempt_check');
select test.check('B limit: direct duplicate attempt violates uniqueness',$$
 insert into account_block_appeals(user_id,block_event_id,attempt,message)
 select user_id,block_event_id,3,'x' from account_blocks where user_id=test.u('c6')$$,'error:duplicate key');
select test.as_user('c5');
select test.check('B pending rule: c5 submits',$$select submit_my_appeal('Please review')$$,'ok');
select test.act('postgres',null);
select test.check('B pending rule: direct second pending rejected',$$
 insert into account_block_appeals(user_id,block_event_id,attempt,message)
 select user_id,block_event_id,2,'x' from account_blocks where user_id=test.u('c5')$$,'error:one_pending_appeal_per_block');
select test.check('B ownership: appeal for another user''s block rejected',$$
 insert into account_block_appeals(user_id,block_event_id,attempt,message)
 select test.u('c1'),block_event_id,2,'x' from account_blocks where user_id=test.u('c5')$$,'error:block_event_mismatch');
select test.check('B ownership: decided row cannot be inserted',$$
 insert into account_block_appeals(user_id,block_event_id,attempt,message,status,decided_at,decision_note)
 select user_id,block_event_id,2,'x','rejected',now(),'n' from account_blocks where user_id=test.u('c4')$$,'error:appeal_history_immutable');

------------------------------------------------------------------ B: manual reactivation closes, re-block resets
select test.as_user('a1');
select test.check('B manual reactivation with a pending appeal',$$select admin_reactivate_account(test.u('c5'),'Resolved by phone')$$,'ok');
select test.check('B manual reactivation closes (not rejects) the appeal',$$
 select a.status='closed' and a.closed_reason='reactivated' and a.decided_by=test.u('a1') and a.decision_note is null
 from test.appeal('c5',1) a$$,'true');
select test.check('B re-block c5',$$select admin_block_account(test.u('c5'),'New incident')$$,'ok');
select test.as_user('c5');
select test.check('B re-block: three new appeals, old closed one not counted',$$
 select (s->>'appeals_remaining')::int=3 and (s->>'can_appeal')::boolean and jsonb_array_length(s->'appeals')=0 from my_appeal_status() s$$,'true');
select test.as_user('a1');
select test.check('B history: closed appeal kept for admins, not current',$$
 select x->>'status'='closed' and not (x->>'is_current_block')::boolean from admin_account_appeals(test.u('c5')) x$$,'true');
select test.check('B admin appeals for an admin target refused',$$select count(*) from admin_account_appeals(test.u('a2'))$$,'error:account_not_found');

------------------------------------------------------------------ B: approval reactivates atomically
select test.as_user('c4');
select test.check('B approve flow: c4 submits',$$select submit_my_appeal('I was hacked; it is fixed now.')$$,'ok');
select test.as_user('a2');
select test.check('B approve: reactivates in the same call',$$select (admin_decide_appeal(test.appeal_id('c4'),true,'Verified with the member.')->>'reactivated')::boolean$$,'true');
select test.check('B approve: block removed',$$select not test.blocked('c4')$$,'true');
select test.act('postgres',null);
select test.check('B approve: reactivated event linked to the appeal',$$
 select count(*)=1 from account_moderation_events where user_id=test.u('c4') and action='reactivated' and appeal_id=test.appeal_id('c4') and actor_id=test.u('a2')$$,'true');
select test.check('B approve: member notified',$$
 select count(*)=1 from notifications where user_id=test.u('c4') and kind='account' and body like '%appeal was approved%'$$,'true');
select test.check('B approve: appeal approved, decided by a2',$$
 select a.status='approved' and a.decided_by=test.u('a2') from test.appeal('c4',1) a$$,'true');
select test.check('B event link: bogus appeal_id rejected',$$
 insert into account_moderation_events(user_id,action,reason,actor_id,appeal_id) values(test.u('c1'),'reactivated','x',test.u('a1'),gen_random_uuid())$$,'error:appeal_event_mismatch');
select test.as_user('c4');
select test.check('B approve: member is active again',$$select my_appeal_status()->>'unavailable_reason'='account_active' and is_maak_active()$$,'true');
select test.as_user('a1');
select test.check('B history: newest first, event before decision before submission',$$
 select array_agg(x->>'action')=array['reactivated','appeal_approved','appeal_submitted','blocked']
 from admin_account_moderation_history(test.u('c4')) x$$,'true');
select test.check('B history: decision actor label, not email',$$
 select x->>'actor_name'='Admin Two' and not (x->>'actor_is_me')::boolean
 from admin_account_moderation_history(test.u('c4')) x where x->>'action'='appeal_approved'$$,'true');

------------------------------------------------------------------ H: decision guard combinations
-- c3 gets a pending appeal; every invalid way of deciding it is refused by the
-- trigger even with table privileges (test.rpc), then a valid decision works.
select test.as_user('a1');
select test.check('H setup: block c3',$$select admin_block_account(test.u('c3'),'Hardening test')$$,'ok');
select test.as_user('c3');
select test.check('H setup: c3 appeals',$$select submit_my_appeal('Hardening appeal')$$,'ok');
select test.act('postgres',null);
select test.check('H guard: approval without a signed-in admin (SQL editor) refused',$$
 update account_block_appeals set status='approved',decided_at=now(),decided_by=test.u('a1') where id=test.appeal_id('c3')$$,'error:appeal_decision_invalid');
select test.as_user('a1');
select test.check('H guard: admin cannot record another admin as decider',$$
 select test.rpc(format('update account_block_appeals set status=''approved'',decided_at=now(),decided_by=%L where id=%L',test.u('a2'),test.appeal_id('c3')))$$,'error:appeal_decision_invalid');
select test.check('H guard: rejection without a note refused',$$
 select test.rpc(format('update account_block_appeals set status=''rejected'',decided_at=now(),decided_by=%L where id=%L',test.u('a1'),test.appeal_id('c3')))$$,'error:appeal_decision_invalid');
select test.check('H guard: approval with a closed_reason refused',$$
 select test.rpc(format('update account_block_appeals set status=''approved'',decided_at=now(),decided_by=%L,closed_reason=''reactivated'' where id=%L',test.u('a1'),test.appeal_id('c3')))$$,'error:appeal_decision_invalid');
select test.check('H guard: decision dated before submission refused',$$
 select test.rpc(format('update account_block_appeals set status=''approved'',decided_at=submitted_at-interval ''1 day'',decided_by=%L where id=%L',test.u('a1'),test.appeal_id('c3')))$$,'error:appeal_decision_invalid');
select test.check('H guard: missing decided_at refused',$$
 select test.rpc(format('update account_block_appeals set status=''approved'',decided_by=%L where id=%L',test.u('a1'),test.appeal_id('c3')))$$,'error:appeal_decision_invalid');
select test.check('H guard: a decision cannot edit the explanation',$$
 select test.rpc(format('update account_block_appeals set status=''approved'',decided_at=now(),decided_by=%L,message=''edited'' where id=%L',test.u('a1'),test.appeal_id('c3')))$$,'error:appeal_decision_invalid');
select test.check('H guard: closed with a note refused',$$
 select test.rpc(format('update account_block_appeals set status=''closed'',closed_reason=''reactivated'',decided_at=now(),decided_by=%L,decision_note=''x'' where id=%L',test.u('a1'),test.appeal_id('c3')))$$,'error:appeal_decision_invalid');
select test.check('H guard: closed as account_deleted while the member exists refused',$$
 select test.rpc(format('update account_block_appeals set status=''closed'',closed_reason=''account_deleted'',decided_at=now(),decided_by=%L where id=%L',test.u('a1'),test.appeal_id('c3')))$$,'error:appeal_decision_invalid');
select test.check('H guard: closed recording another admin refused',$$
 select test.rpc(format('update account_block_appeals set status=''closed'',closed_reason=''reactivated'',decided_at=now(),decided_by=%L where id=%L',test.u('a2'),test.appeal_id('c3')))$$,'error:appeal_decision_invalid');
select test.as_user('c3');
select test.check('H guard: member cannot decide their own appeal',$$
 select test.rpc(format('update account_block_appeals set status=''approved'',decided_at=now(),decided_by=%L where id=%L',test.u('c3'),test.appeal_id('c3')))$$,'error:appeal_decision_invalid');
select test.act('postgres',null);
select test.check('H guard: appeal still pending after every refused attempt',$$select (test.appeal('c3',1)).status='pending'$$,'true');

------------------------------------------------------------------ H: approval is all-or-nothing
-- Make the approval's notification INSERT fail; nothing of the approval may remain.
alter table public.notifications add constraint test_no_account_kind check (kind<>'account') not valid;
select test.as_user('a1');
select test.check('H rollback: approval fails when its notification fails',$$select admin_decide_appeal(test.appeal_id('c3'),true,'Looks fine')$$,'error:test_no_account_kind');
select test.act('postgres',null);
select test.check('H rollback: appeal still pending',$$select (test.appeal('c3',1)).status='pending' and (test.appeal('c3',1)).decided_at is null$$,'true');
select test.check('H rollback: account still blocked',$$select test.blocked('c3')$$,'true');
select test.check('H rollback: no reactivation event left behind',$$
 select count(*)=0 from account_moderation_events where user_id=test.u('c3') and action='reactivated'$$,'true');
alter table public.notifications drop constraint test_no_account_kind;
select test.as_user('a1');
select test.check('H approval succeeds once notifications work',$$select admin_decide_appeal(test.appeal_id('c3'),true,'Looks fine')$$,'ok');
select test.act('postgres',null);
select test.check('H approval: notification row matches the table definition',$$
 select count(*)=1 and bool_and(kind='account' and not is_read and reference_id is null and title='Account reactivated')
 from notifications where user_id=test.u('c3') and kind='account'$$,'true');
select test.check('H approval: valid decision columns recorded',$$
 select a.status='approved' and a.decided_by=test.u('a1') and a.closed_reason is null and a.decided_at>=a.submitted_at
 from test.appeal('c3',1) a$$,'true');

------------------------------------------------------------------ P: own-row profiles_read regressions
select test.as_user('c1');
select test.check('P seeker: own name readable (getMyFullName)',$$select full_name='Seeker One' from profiles where id=auth.uid()$$,'true');
select test.check('P seeker: browse still shows volunteer names',$$
 select count(*)>0 and bool_and(x->>'full_name' is not null) from browse_volunteers() x$$,'true');
select test.check('P seeker: requests still show contact names',$$
 select count(*)>0 and bool_and(x->>'contact_name' is not null) from my_support_requests() x$$,'true');
select test.check('P seeker: profile save still works',$$
 select save_maak_profile_reviewable('Seeker One',(select coalesce(username,'seeker_one') from profiles where id=auth.uid()),
  'help_seeker',array['Diabetes'],'English','Looking for support',null,false,false,null)$$,'ok');
select test.check('P seeker: profile repair still returns the role',$$select ensure_maak_profile()='help_seeker'$$,'true');
select test.as_user('b2');
select test.check('P volunteer: requests still show seeker names',$$
 select count(*)>0 and bool_and(x->>'contact_name' is not null) from my_support_requests() x$$,'true');
select test.as_user('a1');
select test.check('P admin: applications still include volunteer names',$$
 select count(*)>0 and bool_and(x->'profiles'->>'full_name' is not null) from admin_volunteer_applications() x$$,'true');
select test.check('P admin: condition review list still readable',$$select count(*)>=0 from admin_condition_requests()$$,'true');
select test.check('P admin: Manage Accounts still lists member names',$$
 select count(*)>0 and bool_and(x->>'full_name' is not null) from admin_list_accounts() x$$,'true');

------------------------------------------------------------------ B: immutability
select test.act('postgres',null);
select test.check('B immutable: message cannot be edited',$$update account_block_appeals set message='edited' where user_id=test.u('c6')$$,'error:appeal_history_immutable');
select test.check('B immutable: decision cannot be changed',$$update account_block_appeals set status='approved' where user_id=test.u('c6') and attempt=1$$,'error:appeal_history_immutable');
select test.check('B immutable: redaction refused while the profile exists',$$
 update account_block_appeals set message=null,decision_note=null,redacted_at=now() where user_id=test.u('c6')$$,'error:appeal_history_immutable');
select test.check('B immutable: delete refused',$$delete from account_block_appeals$$,'error:appeal_history_immutable');
select test.check('B immutable: truncate refused',$$truncate account_block_appeals$$,'error:appeal_history_immutable');
select test.act('service_role',null);
select test.check('B immutable: service_role delete refused',$$delete from account_block_appeals$$,'error:appeal_history_immutable');

------------------------------------------------------------------ B: deletion (cascade order) closes and redacts
select test.as_user('c7');
select test.check('B deletion: c7 submits',$$select submit_my_appeal('Please reconsider, it was a misunderstanding.')$$,'ok');
select test.act('postgres',null);
select test.check('B deletion: account deletion cascade succeeds',$$delete from auth.users where id=test.u('c7')$$,'ok');
select test.check('B deletion: pending appeal closed as account_deleted',$$
 select a.status='closed' and a.closed_reason='account_deleted' from test.appeal('c7',1) a$$,'true');
select test.check('B deletion: free text redacted, metadata kept',$$
 select a.message is null and a.decision_note is null and a.redacted_at is not null and a.attempt=1 and a.block_event_id is not null
 from test.appeal('c7',1) a$$,'true');
select test.check('B deletion: decided appeals of a deleted member redacted',$$delete from auth.users where id=test.u('c6')$$,'ok');
select test.check('B deletion: c6 rejections keep status, lose text',$$
 select count(*)=3 and bool_and(status='rejected' and message is null and decision_note is null and redacted_at is not null)
 from account_block_appeals where user_id=test.u('c6')$$,'true');
select test.check('B deletion: moderation events kept',$$select count(*)>=3 from account_moderation_events where user_id=test.u('c6')$$,'true');

-- Reverse order: redaction first, closing second (simulated by deferring the
-- cascade with session_replication_role, which a superuser may set).
select test.as_user('b6');
select test.check('B reverse order: b6 submits',$$select submit_my_appeal('Credentials were valid.')$$,'ok');
select test.act('postgres',null);
set session_replication_role = replica;
delete from public.profiles where id=test.u('b6');
set session_replication_role = origin;
select test.check('B reverse order: redaction first is allowed',$$
 update account_block_appeals set message=null,decision_note=null,redacted_at=now() where user_id=test.u('b6')$$,'ok');
select test.check('B reverse order: closing afterwards is allowed',$$delete from account_blocks where user_id=test.u('b6')$$,'ok');
select test.check('B reverse order: result matches cascade order',$$
 select a.status='closed' and a.closed_reason='account_deleted' and a.message is null and a.redacted_at is not null from test.appeal('b6',1) a$$,'true');
delete from auth.users where id=test.u('b6');

------------------------------------------------------------------ grants
select test.check('Grants: internal functions not executable by clients',$$
 select bool_and(not has_function_privilege('authenticated',p.oid,'execute') and not has_function_privilege('anon',p.oid,'execute'))
 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('maak_admin_label','guard_account_block_event',
  'guard_appeal_insert','guard_appeal_update','guard_appeal_delete','close_appeals_on_unblock',
  'redact_appeals_on_profile_delete','guard_moderation_event_appeal')$$,'true');
select test.check('Grants: RPCs for authenticated only',$$
 select bool_and(has_function_privilege('authenticated',p.oid,'execute') and not has_function_privilege('anon',p.oid,'execute'))
 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('my_appeal_status','submit_my_appeal',
  'admin_pending_appeals','admin_account_appeals','admin_decide_appeal','admin_list_accounts','admin_blocked_accounts',
  'admin_account_moderation_history','admin_block_account')$$,'true');
select test.check('Grants: appeals table closed to clients',$$
 select not has_table_privilege('authenticated','public.account_block_appeals','select,insert,update,delete')
  and not has_table_privilege('anon','public.account_block_appeals','select')$$,'true');

select test.act('postgres',null);
select n,case when ok then 'PASS' else 'FAIL' end as result,name,detail from test.results order by n;
select count(*) filter (where ok) as passed,count(*) filter (where not ok) as failed from test.results;
