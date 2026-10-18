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
