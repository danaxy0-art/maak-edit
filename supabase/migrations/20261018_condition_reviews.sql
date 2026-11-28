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
