-- Additional recommendations exclude this seeker's pending requests and accepted connections.
-- No requests, messages, approvals, or profile data are modified.
begin;
create or replace function public.maak_matching_context() returns jsonb
language plpgsql stable security definer set search_path=public as $$
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
revoke all on function public.maak_matching_context() from public,anon;
grant execute on function public.maak_matching_context() to authenticated;
notify pgrst,'reload schema';
commit;
