-- Production state for isolated tests, from the production SQL Editor export
-- (9 function definitions, 2026-10-21) and the read-only prechecks Q2-Q8.
-- Function bodies below are copied verbatim from that export. NOT for production.
\set ON_ERROR_STOP 1
begin;
-- Conversation restriction columns, and the support_requests constraints exactly
-- as reported by the production constraint check (pg_get_constraintdef).
alter table public.support_requests add column if not exists restricted_at timestamptz;
alter table public.support_requests add column if not exists restricted_by uuid;
alter table public.support_requests add column if not exists restriction_reason text;
alter table public.support_requests drop constraint if exists support_requests_restriction_consistent;
alter table public.support_requests add constraint support_requests_restriction_consistent
 check (((restricted_at is null and restriction_reason is null) or (restricted_at is not null and length(trim(restriction_reason)) between 1 and 500)));
alter table public.support_requests drop constraint if exists support_requests_restricted_by_fkey;
alter table public.support_requests add constraint support_requests_restricted_by_fkey
 foreign key (restricted_by) references auth.users(id) on delete set null;
alter table public.support_requests drop constraint if exists support_requests_status_check;
alter table public.support_requests add constraint support_requests_status_check
 check (status in ('pending','accepted','declined','canceled'));

CREATE OR REPLACE FUNCTION public.admin_restrict_conversation(p_request_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare seeker uuid; volunteer uuid; clean_reason text:=trim(coalesce(p_reason,''));
begin
  if not is_maak_admin() then raise exception 'not_allowed'; end if;
  if length(clean_reason) not between 1 and 500 then raise exception 'reason_required'; end if;
  update support_requests set restricted_at=now(),restricted_by=auth.uid(),restriction_reason=clean_reason
    where id=p_request_id and status='accepted' and restricted_at is null returning seeker_id,volunteer_id into seeker,volunteer;
  if not found then raise exception 'conversation_changed'; end if;
  insert into notifications(user_id,title,body,kind,reference_id)
    select u,'Conversation restricted','An admin restricted this conversation. Reason: '||clean_reason,'restricted',p_request_id
    from unnest(array[seeker,volunteer]) as u;
end; $$;

CREATE OR REPLACE FUNCTION public.admin_support_requests()
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
begin if not is_maak_admin() then raise exception 'not_allowed'; end if;
  return query select jsonb_build_object('id',r.id,'status',r.status,'created_at',r.created_at,
      'restricted_at',r.restricted_at,'restriction_reason',r.restriction_reason,
      'seeker_name',coalesce(s.full_name,'Unknown'),'volunteer_name',coalesce(v.full_name,'Unknown'),
      'message_count',(select count(*) from messages m where m.request_id=r.id))
    from support_requests r left join profiles s on s.id=r.seeker_id left join profiles v on v.id=r.volunteer_id
    order by r.created_at desc;
end; $$;

CREATE OR REPLACE FUNCTION public.book_support_session(p_request_id uuid, p_starts_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare recipient uuid;
begin
  select r.seeker_id into recipient from support_requests r join volunteer_profiles v on v.user_id=r.volunteer_id
    where r.id=p_request_id and r.volunteer_id=auth.uid() and r.status='accepted' and v.status='approved'
      and r.restricted_at is null for update of r;
  if not found or p_starts_at<=now() then raise exception 'invalid_session'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
  if exists(select 1 from support_sessions s join support_requests r on r.id=s.request_id where r.volunteer_id=auth.uid()
    and s.starts_at<p_starts_at+interval '1 hour' and s.starts_at+interval '1 hour'>p_starts_at) then raise exception 'session_overlap'; end if;
  insert into support_sessions(request_id,starts_at) values(p_request_id,p_starts_at);
  insert into notifications(user_id,title,body,kind,reference_id) values(recipient,'Support session scheduled','Check your journey for the session time.','session',p_request_id);
end; $$;

CREATE OR REPLACE FUNCTION public.browse_volunteers()
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
 select jsonb_build_object('user_id',v.user_id,'full_name',p.full_name,
 'condition',coalesce((select string_agg(c.name,', ' order by c.name) from user_conditions u join chronic_conditions c on c.id=u.condition_id where u.user_id=v.user_id and c.is_active),v.condition_experience),
 'language',v.preferred_language,'description',v.experience_description)
 from volunteer_profiles v join profiles p on p.id=v.user_id and p.role='volunteer'
 where auth.uid() is not null and v.status='approved' order by p.full_name;
$$;

CREATE OR REPLACE FUNCTION public.can_send_maak_message(p_request_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
  select exists(select 1 from support_requests r join volunteer_profiles v on v.user_id=r.volunteer_id
    where r.id=p_request_id and r.status='accepted' and v.status='approved' and r.restricted_at is null
      and (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid()));
$$;

CREATE OR REPLACE FUNCTION public.maak_matching_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare me uuid:=auth.uid(); own jsonb; candidates jsonb; general boolean;
begin
 if me is null or not exists(select 1 from profiles where id=me and role='help_seeker') then raise exception 'not_allowed'; end if;
 select jsonb_build_object('description',coalesce(h.description,''),'language',h.preferred_language,
 'conditions',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name)
 from user_conditions u join chronic_conditions c on c.id=u.condition_id where u.user_id=me and c.is_active and not c.is_other),'[]'::jsonb))
 into own from help_seeker_profiles h where h.user_id=me;
 if own is null then raise exception 'profile_incomplete'; end if;
 general:=jsonb_array_length(own->'conditions')=0;
 select coalesce(jsonb_agg(card order by card->>'user_id'),'[]'::jsonb) into candidates from (
 select jsonb_build_object('user_id',v.user_id,'full_name',p.full_name,'language',v.preferred_language,
 'condition',v.condition_experience,'description',v.experience_description,'ai_consent',v.ai_matching_consent,'status',v.status,
 'conditions',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name)
 from user_conditions u join chronic_conditions c on c.id=u.condition_id where u.user_id=v.user_id and c.is_active and not c.is_other),'[]'::jsonb)) card
 from volunteer_profiles v join profiles p on p.id=v.user_id and p.role='volunteer'
 where v.status='approved' and v.user_id<>me
 and not exists (
  select 1 from support_requests r
  where r.seeker_id=me and r.volunteer_id=v.user_id
   and r.status in ('pending','accepted')
 )
 and (general or exists(
 select 1 from user_conditions a join user_conditions b on b.condition_id=a.condition_id
 join chronic_conditions c on c.id=a.condition_id and c.is_active and not c.is_other
 where a.user_id=me and b.user_id=v.user_id))
 ) q;
 return jsonb_build_object('seeker',own,'candidates',candidates,'general_mode',general);
end; $$;

CREATE OR REPLACE FUNCTION public.my_maak_conditions()
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
 select jsonb_build_object('id',c.id,'name',c.name,'is_active',c.is_active)
 from user_conditions u join chronic_conditions c on c.id=u.condition_id
 where u.user_id=auth.uid() order by c.sort_order,c.name;
$$;

CREATE OR REPLACE FUNCTION public.my_support_requests()
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
  select to_jsonb(r)||jsonb_build_object('contact_name',p.full_name,'condition',h.chronic_condition,
    'description',h.description,'last_message',(select body from messages where request_id=r.id order by created_at desc limit 1))
  from support_requests r join profiles p on p.id=case when r.seeker_id=auth.uid() then r.volunteer_id else r.seeker_id end
  join help_seeker_profiles h on h.user_id=r.seeker_id where r.seeker_id=auth.uid() or r.volunteer_id=auth.uid() order by r.created_at desc;
$$;

CREATE OR REPLACE FUNCTION public.my_support_sessions()
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
  select to_jsonb(s)||jsonb_build_object('contact_name',p.full_name) from support_sessions s join support_requests r on r.id=s.request_id
    join profiles p on p.id=case when r.seeker_id=auth.uid() then r.volunteer_id else r.seeker_id end
    where r.seeker_id=auth.uid() or r.volunteer_id=auth.uid() order by s.starts_at;
$$;

-- Grants as reported by Q4: six functions as expected; my_support_sessions has
-- no EXECUTE for anon or authenticated in production.
revoke all on function public.admin_restrict_conversation(uuid,text),public.admin_support_requests() from public,anon;
grant execute on function public.admin_restrict_conversation(uuid,text),public.admin_support_requests() to authenticated;
revoke all on function public.my_support_sessions() from public,anon,authenticated;
commit;
