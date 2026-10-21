-- Test data, inserted as the SQL-editor superuser (auth.uid() null).
-- IDs: admins a1,a2; seekers c1,c2,c3; approved volunteers b1-b4, pending b5;
-- requests e1-e6; messages f1,f6; sessions d1,d6.
\set ON_ERROR_STOP 1
create schema test;
create function test.u(text) returns uuid language sql immutable as $$ select ('00000000-0000-0000-0000-0000000000'||$1)::uuid $$;
begin;
insert into auth.users(id,email,raw_user_meta_data) values
 (test.u('a1'),'a1@test','{"full_name":"Admin One"}'),(test.u('a2'),'a2@test','{"full_name":"Admin Two"}'),
 (test.u('c1'),'c1@test','{"full_name":"Seeker One"}'),(test.u('c2'),'c2@test','{"full_name":"Seeker Two"}'),
 (test.u('c3'),'c3@test','{"full_name":"Seeker Three"}'),
 (test.u('b1'),'b1@test','{"full_name":"Vol One","role":"volunteer"}'),(test.u('b2'),'b2@test','{"full_name":"Vol Two","role":"volunteer"}'),
 (test.u('b3'),'b3@test','{"full_name":"Vol Three","role":"volunteer"}'),(test.u('b4'),'b4@test','{"full_name":"Vol Four","role":"volunteer"}'),
 (test.u('b5'),'b5@test','{"full_name":"Vol Five","role":"volunteer"}');
update public.profiles set role='admin' where id in (test.u('a1'),test.u('a2'));
insert into public.help_seeker_profiles(user_id,chronic_condition,preferred_language,description)
 select test.u(x),'Diabetes','English','Looking for support' from unnest(array['c1','c2','c3']) x;
insert into public.volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,verification_document_url,status)
 select test.u(x),'Diabetes','English','Lived experience',x||'/doc.pdf',case when x='b5' then 'pending_review' else 'approved' end
 from unnest(array['b1','b2','b3','b4','b5']) x;
insert into public.user_conditions(user_id,condition_id)
 select test.u(x),(select id from public.chronic_conditions where name='Diabetes') from unnest(array['c1','c2','c3','b1','b2','b3','b4','b5']) x;
insert into public.support_requests(id,seeker_id,volunteer_id,status) values
 (test.u('e1'),test.u('c1'),test.u('b1'),'accepted'),(test.u('e2'),test.u('c2'),test.u('b1'),'pending'),
 (test.u('e3'),test.u('c1'),test.u('b2'),'accepted'),(test.u('e4'),test.u('c3'),test.u('b2'),'pending'),
 (test.u('e5'),test.u('c3'),test.u('b3'),'pending'),(test.u('e6'),test.u('c3'),test.u('b4'),'accepted');
insert into public.messages(id,request_id,sender_id,body) values
 (test.u('f1'),test.u('e1'),test.u('c1'),'Hello'),(test.u('f6'),test.u('e6'),test.u('c3'),'Hi there');
insert into public.support_sessions(id,request_id,starts_at) values
 (test.u('d1'),test.u('e1'),now()+interval '2 days'),(test.u('d6'),test.u('e6'),now()+interval '3 days');
insert into public.resources(title,summary,url) values('Guide','Summary','https://example.org');
insert into storage.objects(bucket_id,name) values('verification-documents','b1/doc.pdf');
commit;
