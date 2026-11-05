-- Records a checksum of all existing user data before deployment, so tests can
-- prove the migrations leave every account, conversation, message, session and
-- notification unchanged.
\set ON_ERROR_STOP 1
create function test.data_checksum() returns text language sql stable security definer as $$
 select md5(concat_ws('|',
  (select string_agg(concat_ws(',',id,role,full_name,username),';' order by id) from public.profiles),
  (select string_agg(concat_ws(',',id,seeker_id,volunteer_id,status,restricted_at,restricted_by,restriction_reason),';' order by id) from public.support_requests),
  (select string_agg(concat_ws(',',id,request_id,sender_id,body,created_at),';' order by id) from public.messages),
  (select string_agg(concat_ws(',',id,request_id,starts_at,duration_minutes),';' order by id) from public.support_sessions),
  (select string_agg(concat_ws(',',id,user_id,kind,title,body,is_read),';' order by id) from public.notifications),
  (select string_agg(concat_ws(',',user_id,status,condition_experience),';' order by user_id) from public.volunteer_profiles),
  (select string_agg(concat_ws(',',user_id,chronic_condition),';' order by user_id) from public.help_seeker_profiles)))
$$;
-- can_send_maak_message() evaluated as the given user (sets the JWT subject first).
create function test.can_send_as(p_user text,p_request text) returns boolean language plpgsql as $$
begin
 perform set_config('request.jwt.claims',json_build_object('sub',test.u(p_user))::text,true);
 return public.can_send_maak_message(test.u(p_request));
end $$;
create function test.all_requests() returns setof public.support_requests language sql stable security definer as $$
 select * from public.support_requests $$;
create table test.baseline as select test.data_checksum() as checksum,
 (select count(*) from public.support_requests where status='accepted' and restricted_at is null) as active_conversations;
