-- =====================================================================================
-- DEPLOYED TO PRODUCTION ON 2026-10-21 - DO NOT RE-RUN ON THE MAIN MA'AK PROJECT.
-- Re-running this file there would overwrite the 20261023 version of
-- admin_account_moderation_history; if it is ever re-run, re-apply 20261023 and run
-- the verification scripts.
-- Applied through the Supabase SQL Editor: migration history may not list it. Do not
-- run `supabase db push` or `supabase migration repair` against production until the
-- team has reconciled the history. Never run supabase_schema.sql or APPLY_UPDATES.sql
-- on production without review. Fresh databases: see supabase/production/README.md.
-- =====================================================================================
-- Apply after 20261021_account_blocking.sql. Idempotent; changes no data.
-- Account moderation visibility and verified administrator labels.
--
-- Security model:
--  * Manage Accounts RPCs return only help seekers and volunteers. Admin
--    accounts, admin emails and admin UUIDs are never returned by them.
--  * profiles_read: every user, admins included, may read only their own
--    profile row directly. Admin features use SECURITY DEFINER RPCs that check
--    is_maak_admin(); none read other profiles through RLS.
--  * Audit attribution ("Blocked by", history actors) uses maak_admin_label():
--    a display label derived from the stored UUID, never an email.
-- Root cause fixed here: a blocking admin whose profile has full_name = '' and
-- no username was returned as an empty name, shown as "Not provided".
-- WARNING: re-running 20261021_account_blocking.sql replaces the three
-- functions redefined here. Re-apply this file (and 20261023) afterwards.
begin;
set local lock_timeout = '10s';

do $$ begin
 if to_regprocedure('public.admin_block_account(uuid,text)') is null then
  raise exception 'Apply 20261021_account_blocking.sql before this migration';
 end if;
end $$;

-- 1. Verified administrator label --------------------------------------------
-- Trimmed full name; else a chosen username (not the auto-generated user_<hex>
-- from seed_maak_account / ensure_maak_profile); else 'Administrator'.
-- 'Former administrator' when the UUID is null or its profile no longer exists.
-- Never reads auth.users, so it cannot return an email. Internal only.
create or replace function public.maak_admin_label(p_id uuid) returns text
language sql stable security definer set search_path=public,pg_temp as $$
 select coalesce(
  (select coalesce(
    nullif(trim(p.full_name), ''),
    case when nullif(trim(p.username), '') is not null
          and trim(p.username) !~ '^user_[0-9a-f]{6,}$' then trim(p.username) end,
    'Administrator')
   from profiles p where p.id = p_id),
  'Former administrator');
$$;

-- 2. Own-profile-only direct reads ---------------------------------------------
-- Previously admins could read every profile, including other admins'. All app
-- reads of profiles are of the caller's own row; admin screens use RPCs.
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
 using (id = auth.uid());

-- 3. Manage Accounts RPCs: members only ---------------------------------------
-- Same signatures and output keys as 20261021, except where noted.
create or replace function public.admin_list_accounts() returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 return query select jsonb_build_object('user_id',p.id,'full_name',p.full_name,'username',p.username,
  'email',u.email,'role',p.role,'created_at',p.created_at,'volunteer_status',v.status,
  'is_blocked',b.user_id is not null,'blocked_at',b.blocked_at,
  'can_block',b.user_id is null)
 from profiles p left join auth.users u on u.id=p.id left join volunteer_profiles v on v.user_id=p.id
 left join account_blocks b on b.user_id=p.id
 where p.role in ('help_seeker','volunteer')
 order by p.created_at desc nulls last;
end; $$;

-- blocked_by_name is always a label; blocked_by_is_me is true only when the
-- stored blocker UUID is the caller. The blocker's UUID is no longer returned.
create or replace function public.admin_blocked_accounts() returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 return query select jsonb_build_object('user_id',b.user_id,'full_name',p.full_name,'username',p.username,
  'email',u.email,'role',p.role,'reason',b.reason,'blocked_at',b.blocked_at,
  'blocked_by_name',maak_admin_label(b.blocked_by),
  'blocked_by_is_me',coalesce(b.blocked_by=auth.uid(),false),
  'times_blocked',(select count(*) from account_moderation_events e where e.user_id=b.user_id and e.action='blocked'))
 from account_blocks b join profiles p on p.id=b.user_id and p.role in ('help_seeker','volunteer')
 left join auth.users u on u.id=b.user_id
 order by b.blocked_at desc;
end; $$;

-- Only for existing members; an admin (or unknown) target is account_not_found.
-- actor_id is replaced by actor_name / actor_is_me.
create or replace function public.admin_account_moderation_history(p_user_id uuid) returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if not exists(select 1 from profiles where id=p_user_id and role in ('help_seeker','volunteer')) then
  raise exception 'account_not_found';
 end if;
 return query select jsonb_build_object('id',e.id,'action',e.action,'reason',e.reason,
  'actor_name',maak_admin_label(e.actor_id),'actor_is_me',e.actor_id=auth.uid(),'created_at',e.created_at)
 from account_moderation_events e
 where e.user_id=p_user_id order by e.created_at desc;
end; $$;

-- 4. Function privileges -------------------------------------------------------
revoke all on function public.maak_admin_label(uuid) from public,anon,authenticated;
revoke all on function public.admin_list_accounts(),public.admin_blocked_accounts(),
 public.admin_account_moderation_history(uuid) from public,anon;
grant execute on function public.admin_list_accounts(),public.admin_blocked_accounts(),
 public.admin_account_moderation_history(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
