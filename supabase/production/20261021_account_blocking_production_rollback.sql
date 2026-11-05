-- PRODUCTION ROLLBACK for supabase/migrations/20261021_account_blocking.sql together with
-- supabase/production/20261021_production_compat.sql. Roll back 20261023, then 20261022,
-- first. Run once, as one transaction, in the production SQL Editor. Blocked users are
-- unrestricted immediately.
--
-- Differs from supabase/rollbacks/20261021_account_blocking_rollback.sql (the tested,
-- repository-based rollback) only in what it restores:
--  * can_send_maak_message, browse_volunteers, maak_matching_context, my_maak_conditions,
--    my_support_requests and my_support_sessions get the exact production definitions
--    from the production export (2026-10-21), including matching's open-request rule;
--  * EXECUTE privileges are put back exactly as production had them.
-- is_maak_admin is restored to the repository body; precheck P1 confirms production
-- uses that body before deployment. The 15 policies are restored to the repository
-- definitions; precheck P2 confirms production matches them.
--
-- By default the two moderation tables and their data are KEPT (still closed to
-- clients); remove them with the optional block at the end, after exporting data.
-- Tested on production definitions: tests/database/production_compat.
begin;
-- Fail fast (and change nothing) instead of queueing app traffic behind a lock.
set local lock_timeout = '10s';

-- 1. Restore the 15 replaced policies to their pre-migration definitions.
drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert to authenticated with check(id=auth.uid() and role in ('help_seeker','volunteer'));
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
drop policy if exists seekers_owner_read on public.help_seeker_profiles;
create policy seekers_owner_read on public.help_seeker_profiles for select to authenticated using(user_id=auth.uid());
drop policy if exists volunteers_read on public.volunteer_profiles;
create policy volunteers_read on public.volunteer_profiles for select to authenticated using(user_id=auth.uid() or is_maak_admin());
drop policy if exists user_conditions_read on public.user_conditions;
create policy user_conditions_read on public.user_conditions for select to authenticated
 using(user_id=auth.uid() or public.is_maak_admin());
drop policy if exists condition_requests_read on public.condition_review_requests;
create policy condition_requests_read on public.condition_review_requests for select to authenticated using(user_id=auth.uid() or is_maak_admin());
drop policy if exists notification_read on public.notifications;
create policy notification_read on public.notifications for select to authenticated using(user_id=auth.uid());
drop policy if exists notification_update on public.notifications;
create policy notification_update on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists requests_read on public.support_requests;
create policy requests_read on public.support_requests for select to authenticated using(seeker_id=auth.uid() or volunteer_id=auth.uid());
drop policy if exists messages_read on public.messages;
create policy messages_read on public.messages for select to authenticated using(exists(select 1 from support_requests r where r.id=request_id and (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid())));
drop policy if exists messages_send on public.messages;
create policy messages_send on public.messages for insert to authenticated
  with check(sender_id=auth.uid() and can_send_maak_message(request_id));
drop policy if exists sessions_read on public.support_sessions;
create policy sessions_read on public.support_sessions for select to authenticated using(exists(select 1 from support_requests r where r.id=request_id and (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid())));
drop policy if exists resources_read on public.resources;
create policy resources_read on public.resources for select to authenticated using(true);
drop policy if exists maak_document_upload on storage.objects;
create policy maak_document_upload on storage.objects for insert to authenticated with check(bucket_id='verification-documents' and auth.uid()::text=(storage.foldername(name))[1]);
drop policy if exists maak_document_read on storage.objects;
create policy maak_document_read on storage.objects for select to authenticated using(bucket_id='verification-documents' and (auth.uid()::text=(storage.foldername(name))[1] or is_maak_admin()));

-- 2. Remove the guard triggers.
do $$ declare t text; begin
 foreach t in array array['profiles','help_seeker_profiles','volunteer_profiles','user_conditions',
  'condition_review_requests','support_requests','support_sessions','messages','notifications'] loop
  execute format('drop trigger if exists maak_blocked_actor_guard on public.%I',t);
 end loop;
 foreach t in array array['support_requests','support_sessions','messages'] loop
  execute format('drop trigger if exists maak_blocked_participant_guard on public.%I',t);
 end loop;
end $$;
drop trigger if exists maak_blocked_role_guard on public.profiles;

-- 3. Restore the 7 redefined functions (bodies, search_path and grants as before).
create or replace function public.is_maak_admin() returns boolean language sql stable security definer
set search_path = public as $$ select exists(select 1 from profiles where id=auth.uid() and role='admin'); $$;

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

-- Production EXECUTE privileges before 20261021 (prechecks Q4): authenticated
-- only, plus anon for is_maak_admin; none at all for my_support_sessions.
revoke all on function public.is_maak_admin(),public.can_send_maak_message(uuid),public.browse_volunteers(),
 public.maak_matching_context(),public.my_maak_conditions(),public.my_support_requests(),public.my_support_sessions()
 from public,anon,authenticated;
grant execute on function public.is_maak_admin() to anon,authenticated;
grant execute on function public.can_send_maak_message(uuid),public.browse_volunteers(),public.maak_matching_context(),
 public.my_maak_conditions(),public.my_support_requests() to authenticated;

-- 4. Remove the new functions (nothing depends on them after steps 1-3).
drop function if exists public.admin_list_accounts();
drop function if exists public.admin_blocked_accounts();
drop function if exists public.admin_account_moderation_history(uuid);
drop function if exists public.admin_block_account(uuid,text);
drop function if exists public.admin_reactivate_account(uuid,text);
drop function if exists public.my_block_status();
drop function if exists public.guard_maak_blocked_actor();
drop function if exists public.guard_maak_blocked_participants();
drop function if exists public.guard_blocked_admin_promotion();
drop function if exists public.is_maak_active();
drop function if exists public.is_maak_account_blocked(uuid);
drop function if exists public.trim_maak_reason(text);
-- guard_account_block_target and guard_moderation_history stay: they protect the kept tables.
notify pgrst,'reload schema';
commit;

-- OPTIONAL, run separately only after exporting the data (this destroys the audit history):
-- begin;
-- drop table if exists public.account_moderation_events;  -- triggers drop with the table
-- drop table if exists public.account_blocks;
-- drop function if exists public.guard_moderation_history();
-- drop function if exists public.guard_account_block_target();
-- commit;
