-- Apply in Supabase SQL Editor, with the existing Ma'ak base schema installed.
-- Preserves accounts, volunteer decisions and existing condition data.

-- Apply AFTER supabase_schema.sql. Idempotent, preserves existing decisions/data.
begin;
alter table public.volunteer_profiles add column if not exists ai_matching_consent boolean not null default false;
create table if not exists public.user_conditions (
 user_id uuid not null references public.profiles(id) on delete cascade,
 condition_id uuid not null references public.chronic_conditions(id) on delete restrict,
 primary key(user_id,condition_id)
);
alter table public.user_conditions enable row level security;
drop policy if exists user_conditions_read on public.user_conditions;
create policy user_conditions_read on public.user_conditions for select to authenticated
 using(user_id=auth.uid() or public.is_maak_admin());
grant select on public.user_conditions to authenticated;
revoke insert,update,delete on public.user_conditions from anon,authenticated;
insert into public.user_conditions(user_id,condition_id)
 select h.user_id,c.id from public.help_seeker_profiles h join public.profiles p on p.id=h.user_id
 join public.chronic_conditions c on c.name=h.chronic_condition on conflict do nothing;
insert into public.user_conditions(user_id,condition_id)
 select v.user_id,c.id from public.volunteer_profiles v join public.profiles p on p.id=v.user_id
 join public.chronic_conditions c on c.name=v.condition_experience on conflict do nothing;

create or replace function public.my_maak_conditions() returns setof jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('id',c.id,'name',c.name,'is_active',c.is_active)
 from user_conditions u join chronic_conditions c on c.id=u.condition_id
 where u.user_id=auth.uid() order by c.sort_order,c.name;
$$;

-- Reuses existing atomic registration/document/role checks; list save is in same transaction.
create or replace function public.save_maak_profile_multi(
 p_full_name text,p_username text,p_role text,p_conditions text[],p_language text,
 p_description text default '',p_document text default null,p_reapply boolean default false,
 p_ai_consent boolean default false)
returns void language plpgsql security definer set search_path=public as $$
declare chosen_ids uuid[]; me uuid:=auth.uid();
begin
 if me is null then raise exception 'not_allowed'; end if;
 perform 1 from profiles where id=me for update;
 if p_conditions is null or cardinality(p_conditions) not between 1 and 20
 or exists(select 1 from unnest(p_conditions) n where n is null or trim(n)='')
 or (select count(distinct n) from unnest(p_conditions) n)<>cardinality(p_conditions)
 then raise exception 'invalid_conditions'; end if;
 -- Disabled conditions may be retained by existing owners, never newly selected.
 perform 1 from chronic_conditions where name=any(p_conditions) for share;
 select array_agg(c.id) into chosen_ids from chronic_conditions c
 where c.name=any(p_conditions) and (c.is_active or exists(
 select 1 from user_conditions u where u.user_id=me and u.condition_id=c.id));
 if coalesce(cardinality(chosen_ids),0)<>cardinality(p_conditions) then raise exception 'condition_inactive'; end if;
 -- Legacy API allows retaining a disabled primary only if previously primary.
 -- Choose the previous primary when retained, otherwise an active selection.
 perform save_maak_profile(p_full_name,p_username,p_role,
 coalesce((select name from chronic_conditions where name=any(p_conditions) and is_active order by array_position(p_conditions,name) limit 1),
 case when p_role='volunteer' then (select condition_experience from volunteer_profiles where user_id=me)
 else (select chronic_condition from help_seeker_profiles where user_id=me) end),
 p_language,p_description,p_document,p_reapply);
 -- Preserve legacy single-condition projections, including retained inactive choices.
 if p_role='volunteer' then update volunteer_profiles set condition_experience=p_conditions[1] where user_id=me;
 else update help_seeker_profiles set chronic_condition=p_conditions[1] where user_id=me; end if;
 delete from user_conditions where user_id=me;
 insert into user_conditions(user_id,condition_id) select me,unnest(chosen_ids);
 if p_role='volunteer' then update volunteer_profiles set ai_matching_consent=coalesce(p_ai_consent,false) where user_id=me; end if;
end; $$;

create or replace function public.maak_matching_context() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare me uuid:=auth.uid(); own jsonb; candidates jsonb;
begin
 if me is null or not exists(select 1 from profiles where id=me and role='help_seeker')
 then raise exception 'not_allowed'; end if;
 select jsonb_build_object('description',coalesce(h.description,''),'language',h.preferred_language,
 'conditions',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name)
 from user_conditions u join chronic_conditions c on c.id=u.condition_id where u.user_id=me and c.is_active),'[]'::jsonb))
 into own from help_seeker_profiles h where h.user_id=me;
 if own is null then raise exception 'profile_incomplete'; end if;
 select coalesce(jsonb_agg(card order by card->>'user_id'),'[]'::jsonb) into candidates from (
 select jsonb_build_object('user_id',v.user_id,'full_name',p.full_name,'language',v.preferred_language,
 'condition',v.condition_experience,'description',v.experience_description,
 'ai_consent',v.ai_matching_consent,'status',v.status,
 'conditions',(select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name)
 from user_conditions u join chronic_conditions c on c.id=u.condition_id where u.user_id=v.user_id and c.is_active)) card
 from volunteer_profiles v join profiles p on p.id=v.user_id and p.role='volunteer'
 where v.status='approved' and v.user_id<>me and exists(
 select 1 from user_conditions a join user_conditions b on b.condition_id=a.condition_id
 join chronic_conditions c on c.id=a.condition_id and c.is_active
 where a.user_id=me and b.user_id=v.user_id)
 ) q;
 return jsonb_build_object('seeker',own,'candidates',candidates);
end; $$;
-- Multi-condition labels are available to existing directory/detail screens too.
create or replace function public.browse_volunteers() returns setof jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('user_id',v.user_id,'full_name',p.full_name,
 'condition',coalesce((select string_agg(c.name,', ' order by c.name) from user_conditions u join chronic_conditions c on c.id=u.condition_id where u.user_id=v.user_id and c.is_active),v.condition_experience),
 'language',v.preferred_language,'description',v.experience_description)
 from volunteer_profiles v join profiles p on p.id=v.user_id and p.role='volunteer'
 where auth.uid() is not null and v.status='approved' order by p.full_name;
$$;
-- Admin reviewers see the complete disease experience list as well.
create or replace function public.admin_volunteer_applications() returns setof jsonb
language plpgsql security definer set search_path=public as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 return query select to_jsonb(v)||jsonb_build_object(
 'profiles',jsonb_build_object('full_name',p.full_name,'username',p.username),
 'condition_experience',coalesce((select string_agg(c.name,', ' order by c.name)
 from user_conditions u join chronic_conditions c on c.id=u.condition_id where u.user_id=v.user_id),v.condition_experience))
 from volunteer_profiles v left join profiles p on p.id=v.user_id order by v.created_at desc;
end; $$;
revoke all on function public.my_maak_conditions(),public.maak_matching_context() from public,anon;
revoke all on function public.save_maak_profile_multi(text,text,text,text[],text,text,text,boolean,boolean) from public,anon;
grant execute on function public.my_maak_conditions(),public.maak_matching_context() to authenticated;
grant execute on function public.save_maak_profile_multi(text,text,text,text[],text,text,text,boolean,boolean) to authenticated;
notify pgrst,'reload schema';
commit;


-- Apply after 20261018_matching.sql. Keeps account/application approval independent.
begin;
alter table public.chronic_conditions add column if not exists aliases text[] not null default '{}';
alter table public.chronic_conditions add column if not exists is_other boolean not null default false;
update public.chronic_conditions set is_other=true where lower(name)='other';
insert into public.chronic_conditions(name,is_other) select 'Other',true where not exists(select 1 from public.chronic_conditions where is_other) on conflict do nothing;
create unique index if not exists one_other_condition on public.chronic_conditions(is_other) where is_other;
create or replace function public.guard_other_condition_name() returns trigger language plpgsql set search_path=public as $$
begin
 if old.is_other and (new.name is distinct from old.name or new.is_other is distinct from old.is_other) then raise exception 'reserved_condition'; end if;
 return new;
end; $$;
drop trigger if exists maak_other_condition_guard on public.chronic_conditions;
create trigger maak_other_condition_guard before update on public.chronic_conditions for each row execute function public.guard_other_condition_name();

update public.chronic_conditions set aliases=array(select distinct unnest(aliases||array['سكر','سكري','السكري','مرض السكري'])) where lower(name)='diabetes';
update public.chronic_conditions set aliases=array(select distinct unnest(aliases||array['ربو','الربو'])) where lower(name)='asthma';
update public.chronic_conditions set aliases=array(select distinct unnest(aliases||array['ضغط','ضغط الدم','ارتفاع ضغط الدم'])) where lower(name)='hypertension';
create table if not exists public.condition_review_requests (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,
 submitted_name text not null,status text not null default 'pending' check(status in ('pending','accepted','linked','rejected','withdrawn')),
 condition_id uuid references public.chronic_conditions(id),reason text,
 ai_state text not null default 'not_checked' check(ai_state in ('not_checked','health','warning','unknown')),
 ai_checked_at timestamptz, reviewed_by uuid references public.profiles(id),
 created_at timestamptz not null default now(),reviewed_at timestamptz
);
create unique index if not exists one_pending_condition_request on public.condition_review_requests(user_id) where status='pending';
alter table public.condition_review_requests enable row level security;
drop policy if exists condition_requests_read on public.condition_review_requests;
create policy condition_requests_read on public.condition_review_requests for select to authenticated using(user_id=auth.uid() or is_maak_admin());
grant select on public.condition_review_requests to authenticated;
revoke insert,update,delete on public.condition_review_requests from anon,authenticated;

create or replace function public.valid_maak_other_name(value text) returns boolean
language sql immutable set search_path=public as $$
 select coalesce(char_length(trim(value)) between 3 and 60
 and value ~ '[A-Za-zء-ي]'
 and value !~* '(https?://|www\.|@)'
 and value ~ '^[A-Za-zء-يً-ْ٠-٩0-9 ()''’/-]+$',false);
$$;

create or replace function public.save_maak_profile_reviewable(
 p_full_name text,p_username text,p_role text,p_conditions text[],p_language text,
 p_description text default '',p_document text default null,p_reapply boolean default false,
 p_ai_consent boolean default false,p_other_name text default null)
returns void language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); other_selected boolean; normalized text; pending_name text;
begin
 if me is null then raise exception 'not_allowed'; end if;
 perform 1 from profiles where id=me for update;
 select exists(select 1 from chronic_conditions where name=any(p_conditions) and is_other) into other_selected;
 normalized:=regexp_replace(trim(coalesce(p_other_name,'')),'\s+',' ','g');
 if other_selected then
  if not valid_maak_other_name(normalized) then raise exception 'invalid_other_name'; end if;
  if exists(select 1 from chronic_conditions c where c.is_active and not c.is_other
   and (lower(trim(c.name))=lower(normalized) or exists(select 1 from unnest(c.aliases) a where lower(trim(a))=lower(normalized))))
  then raise exception 'condition_already_listed'; end if;
 end if;
 perform save_maak_profile_multi(p_full_name,p_username,p_role,p_conditions,p_language,p_description,p_document,p_reapply,p_ai_consent);
 select submitted_name into pending_name from condition_review_requests where user_id=me and status='pending' for update;
 if other_selected then
  if pending_name is distinct from normalized then
   update condition_review_requests set status='withdrawn',reviewed_at=now() where user_id=me and status='pending';
   insert into condition_review_requests(user_id,submitted_name) values(me,normalized);
  end if;
 else
  update condition_review_requests set status='withdrawn',reviewed_at=now() where user_id=me and status='pending';
 end if;
end; $$;

create or replace function public.admin_condition_requests() returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 return query select to_jsonb(r)||jsonb_build_object('full_name',p.full_name)
 from condition_review_requests r join profiles p on p.id=r.user_id
 order by (r.status='pending') desc,r.created_at desc;
end; $$;

create or replace function public.review_maak_condition(p_request_id uuid,p_action text,p_condition_id uuid default null,p_name text default null,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare request condition_review_requests%rowtype; target uuid; canonical text; selected_role text; other_id uuid;
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 -- Same lock order as profile saves: account first, then request.
 select user_id into target from condition_review_requests where id=p_request_id;
 if target is null then raise exception 'request_changed'; end if;
 perform 1 from profiles where id=target for update;
 select * into request from condition_review_requests where id=p_request_id for update;
 if request.status<>'pending' then raise exception 'request_changed'; end if;
 if p_action='accept' then
  canonical:=regexp_replace(trim(coalesce(p_name,request.submitted_name)),'\s+',' ','g');
  if not valid_maak_other_name(canonical) then raise exception 'invalid_other_name'; end if;
  if exists(select 1 from chronic_conditions where lower(name)=lower(canonical)) then raise exception 'condition_already_listed'; end if;
  insert into chronic_conditions(name,aliases) values(canonical,array[request.submitted_name]) returning id into target;
 elsif p_action='link' then
  select id,name into target,canonical from chronic_conditions where id=p_condition_id and is_active and not is_other for share;
  if target is null then raise exception 'condition_inactive'; end if;
  update chronic_conditions set aliases=array(select distinct unnest(aliases||array[request.submitted_name])) where id=target;
 elsif p_action='reject' then
  if char_length(trim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'reason_required'; end if;
 else raise exception 'invalid_review_action'; end if;
 if p_action in ('accept','link') then
  insert into user_conditions(user_id,condition_id) values(request.user_id,target) on conflict do nothing;
 end if;
 select id into other_id from chronic_conditions where is_other;
 delete from user_conditions where user_id=request.user_id and condition_id=other_id;
 -- Keep legacy projection usable; fallback Other remains only a compatibility label.
 if p_action='reject' then
  select c.name into canonical from user_conditions u join chronic_conditions c on c.id=u.condition_id where u.user_id=request.user_id and not c.is_other order by c.is_active desc,c.sort_order,c.name limit 1;
 end if;
 if canonical is not null then
  update help_seeker_profiles set chronic_condition=canonical where user_id=request.user_id and chronic_condition=(select name from chronic_conditions where id=other_id);
  update volunteer_profiles set condition_experience=canonical where user_id=request.user_id and condition_experience=(select name from chronic_conditions where id=other_id);
 end if;
 update condition_review_requests set status=case p_action when 'accept' then 'accepted' when 'link' then 'linked' else 'rejected' end,
 condition_id=case when p_action in ('accept','link') then target end,reason=case when p_action='reject' then trim(p_reason) end,
 reviewed_by=auth.uid(),reviewed_at=now() where id=p_request_id;
end; $$;

create or replace function public.record_condition_name_check(p_request_id uuid,p_state text) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if p_state not in ('health','warning','unknown') or p_state is null then raise exception 'invalid_ai_state'; end if;
 update condition_review_requests set ai_state=p_state,ai_checked_at=now() where id=p_request_id and status='pending';
 if not found then raise exception 'request_changed'; end if;
end; $$;

-- Generic suggestions: no disease score, no AI, no free text when seeker has no approved condition.
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
 where v.status='approved' and v.user_id<>me and (general or exists(
 select 1 from user_conditions a join user_conditions b on b.condition_id=a.condition_id
 join chronic_conditions c on c.id=a.condition_id and c.is_active and not c.is_other
 where a.user_id=me and b.user_id=v.user_id))
 ) q;
 return jsonb_build_object('seeker',own,'candidates',candidates,'general_mode',general);
end; $$;
revoke all on function public.save_maak_profile_reviewable(text,text,text,text[],text,text,text,boolean,boolean,text),public.admin_condition_requests(),public.review_maak_condition(uuid,text,uuid,text,text),public.record_condition_name_check(uuid,text) from public,anon;
grant execute on function public.save_maak_profile_reviewable(text,text,text,text[],text,text,text,boolean,boolean,text),public.admin_condition_requests(),public.review_maak_condition(uuid,text,uuid,text,text),public.record_condition_name_check(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;


-- Apply after the matching and condition-review migrations. Preserves decisions.
begin;
create or replace function public.ensure_maak_profile() returns text
language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); saved_role text; metadata jsonb;
begin
 if me is null then raise exception 'not_allowed'; end if;
 select role into saved_role from profiles where id=me;
 if found then return saved_role; end if;
 select raw_user_meta_data into metadata from auth.users where id=me;
 if not found then raise exception 'not_allowed'; end if;
 -- Never infer or grant admin privileges from user-editable auth metadata.
 saved_role:=case when exists(select 1 from volunteer_profiles where user_id=me)
   or metadata->>'role'='volunteer' then 'volunteer' else 'help_seeker' end;
 insert into profiles(id,role,full_name,username) values(me,saved_role,
   left(coalesce(metadata->>'full_name',''),80),
   'user_'||right(replace(me::text,'-',''),25)) on conflict(id) do nothing;
 select role into saved_role from profiles where id=me;
 return saved_role;
end; $$;
revoke all on function public.ensure_maak_profile() from public,anon;
grant execute on function public.ensure_maak_profile() to authenticated;
notify pgrst,'reload schema';
commit;


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
-- Apply to the existing Ma'ak database. Safe to run again.
begin;
alter table public.messages add column if not exists read_at timestamptz;
create index if not exists maak_unread_messages on public.messages(request_id,sender_id) where read_at is null;
create or replace function public.mark_maak_messages_read(p_request_id uuid,p_message_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or not exists(select 1 from support_requests where id=p_request_id and (seeker_id=auth.uid() or volunteer_id=auth.uid())) then raise exception 'not_allowed'; end if;
 if p_message_ids is null or cardinality(p_message_ids)>500 then raise exception 'invalid_messages'; end if;
 update messages set read_at=now() where request_id=p_request_id and id=any(p_message_ids) and sender_id<>auth.uid() and read_at is null;
 -- Acknowledges only the displayed messages; messages arriving concurrently stay unread.
 update notifications n set is_read=true where n.user_id=auth.uid() and n.kind='message' and n.reference_id=p_request_id and not n.is_read
 and not exists(select 1 from messages m where m.request_id=p_request_id and m.sender_id<>auth.uid() and m.read_at is null and m.created_at<=n.created_at);
end; $$;
revoke all on function public.mark_maak_messages_read(uuid,uuid[]) from public,anon;
grant execute on function public.mark_maak_messages_read(uuid,uuid[]) to authenticated;
-- Retain historical records; remove access to the unused booking feature.
revoke all on function public.book_support_session(uuid,timestamptz),public.my_support_sessions() from public,anon,authenticated;
create or replace function public.my_maak_unread_message_count() returns bigint
language sql stable security definer set search_path=public as $$
 select count(*) from messages m join support_requests r on r.id=m.request_id
 where auth.uid() is not null and (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid())
 and m.sender_id<>auth.uid() and m.read_at is null;
$$;
revoke all on function public.my_maak_unread_message_count() from public,anon;
grant execute on function public.my_maak_unread_message_count() to authenticated;
notify pgrst,'reload schema';
commit;
begin;
create table if not exists public.maak_registration_check_limits (
 client_hash text primary key,
 window_start timestamptz not null,
 attempts integer not null
);
alter table public.maak_registration_check_limits enable row level security;
revoke all on public.maak_registration_check_limits from public,anon,authenticated;
create or replace function public.check_maak_registration_email(p_email text,p_client_hash text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare n integer; normalized text:=lower(trim(p_email));
begin
 if normalized is null or length(normalized)>254 or normalized !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
 or p_client_hash is null or p_client_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_email'; end if;
 insert into maak_registration_check_limits as rate(client_hash,window_start,attempts)
 values(p_client_hash,now(),1)
 on conflict(client_hash) do update set
 attempts=case when rate.window_start<now()-interval '10 minutes' then 1 else rate.attempts+1 end,
 window_start=case when rate.window_start<now()-interval '10 minutes' then now() else rate.window_start end
 returning attempts into n;
 delete from maak_registration_check_limits where window_start<now()-interval '1 day';
 if n>30 then return jsonb_build_object('limited',true); end if;
 return jsonb_build_object('exists',exists(select 1 from auth.users where lower(email)=normalized));
end; $$;
revoke all on function public.check_maak_registration_email(text,text) from public,anon,authenticated;
grant execute on function public.check_maak_registration_email(text,text) to service_role;
notify pgrst,'reload schema';
commit;
