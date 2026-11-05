-- Shapes the shared test data (../account_blocking/10_seed.sql) like production
-- (precheck Q7): 4 active conversations, none pending or restricted, no upcoming
-- sessions, notifications of kinds application/message/request. Runs before any
-- moderation migration, as the SQL-editor superuser.
\set ON_ERROR_STOP 1
update public.support_requests set status='accepted' where id=test.u('e2');
update public.support_requests set status='declined' where id in (test.u('e4'),test.u('e5'));
update public.support_sessions set starts_at=now()-interval '2 days';
insert into public.messages(request_id,sender_id,body) values(test.u('e2'),test.u('c2'),'Thank you for accepting');
insert into public.notifications(user_id,title,body,kind) values
 (test.u('a1'),'New volunteer application','A volunteer application is ready for review.','application'),
 (test.u('b1'),'New support request','Someone would like to connect with you.','request');
