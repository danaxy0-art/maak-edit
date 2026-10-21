-- PRODUCTION ONLY. Apply immediately after supabase/migrations/20261021_account_blocking.sql
-- and before 20261022/20261023, in the main Supabase project. Idempotent; changes no data.
-- Not for maak-testing: its matching function and grants differ from production.
--
-- 20261021 was written against the repository definitions. Production differs in
-- two places (production SQL Editor export and prechecks, 2026-10-21):
--  1. maak_matching_context() in production also excludes volunteers the seeker
--     already has a pending or accepted request with. 20261021's replacement lacks
--     that rule. This restores the production body verbatim and adds only the two
--     account-blocking checks (blocked caller refused; blocked volunteers hidden).
--  2. my_support_sessions() has no EXECUTE for anon or authenticated in production;
--     20261021 grants it to authenticated. This puts production's privileges back,
--     so the deployment does not silently widen access. Granting it is a separate
--     team decision: supabase/production/optional_grant_my_support_sessions.sql.
begin;
set local lock_timeout = '10s';

do $$ begin
 if to_regprocedure('public.is_maak_active()') is null or to_regclass('public.account_blocks') is null then
  raise exception 'Apply 20261021_account_blocking.sql before this patch';
 end if;
end $$;

-- 1. Production body plus account-blocking checks (marked "account blocking").
create or replace function public.maak_matching_context() returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); own jsonb; candidates jsonb; general boolean;
begin
 if me is null or not exists(select 1 from profiles where id=me and role='help_seeker') then raise exception 'not_allowed'; end if;
 -- account blocking: a blocked seeker gets no matches
 if not is_maak_active() then raise exception 'account_blocked'; end if;
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
 -- account blocking: blocked volunteers are never suggested
 and not exists(select 1 from account_blocks b where b.user_id=v.user_id)
 and (general or exists(
 select 1 from user_conditions a join user_conditions b on b.condition_id=a.condition_id
 join chronic_conditions c on c.id=a.condition_id and c.is_active and not c.is_other
 where a.user_id=me and b.user_id=v.user_id))
 ) q;
 return jsonb_build_object('seeker',own,'candidates',candidates,'general_mode',general);
end; $$;
revoke all on function public.maak_matching_context() from public,anon;
grant execute on function public.maak_matching_context() to authenticated;

-- 2. Restore production's EXECUTE privileges on my_support_sessions(): none for
-- anon or authenticated (20261021 granted authenticated). The body keeps 20261021's
-- account-blocking filter; only who may call it is put back.
revoke all on function public.my_support_sessions() from public,anon,authenticated;

notify pgrst,'reload schema';
commit;
