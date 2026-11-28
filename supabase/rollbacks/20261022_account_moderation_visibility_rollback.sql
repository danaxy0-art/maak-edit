-- ROLLBACK for supabase/migrations/20261022_account_moderation_visibility.sql.
-- Roll back 20261023 FIRST. Run once, as one transaction, in the SQL Editor.
-- Restores the 20261021 versions exactly: admins appear in Manage Accounts again,
-- profiles_read lets admins read every profile again, and "Blocked by" shows the
-- raw full_name (empty for unnamed admins). Tested to restore every object exactly.
begin;
set local lock_timeout = '10s';

do $$ begin
 if to_regprocedure('public.submit_my_appeal(text)') is not null then
  raise exception 'Roll back 20261023_account_appeals.sql before this rollback';
 end if;
end $$;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or is_maak_admin());

create or replace function public.admin_list_accounts() returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 return query select jsonb_build_object('user_id',p.id,'full_name',p.full_name,'username',p.username,
  'email',u.email,'role',p.role,'created_at',p.created_at,'volunteer_status',v.status,
  'is_blocked',b.user_id is not null,'blocked_at',b.blocked_at,
  'can_block',p.role<>'admin' and p.id<>auth.uid() and b.user_id is null)
 from profiles p left join auth.users u on u.id=p.id left join volunteer_profiles v on v.user_id=p.id
 left join account_blocks b on b.user_id=p.id
 order by p.created_at desc nulls last;
end; $$;

create or replace function public.admin_blocked_accounts() returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 return query select jsonb_build_object('user_id',b.user_id,'full_name',p.full_name,'username',p.username,
  'email',u.email,'role',p.role,'reason',b.reason,'blocked_at',b.blocked_at,
  'blocked_by',b.blocked_by,'blocked_by_name',a.full_name,
  'times_blocked',(select count(*) from account_moderation_events e where e.user_id=b.user_id and e.action='blocked'))
 from account_blocks b join profiles p on p.id=b.user_id left join auth.users u on u.id=b.user_id
 left join profiles a on a.id=b.blocked_by
 order by b.blocked_at desc;
end; $$;

create or replace function public.admin_account_moderation_history(p_user_id uuid) returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 return query select jsonb_build_object('id',e.id,'action',e.action,'reason',e.reason,
  'actor_id',e.actor_id,'actor_name',a.full_name,'created_at',e.created_at)
 from account_moderation_events e left join profiles a on a.id=e.actor_id
 where e.user_id=p_user_id order by e.created_at desc;
end; $$;

drop function if exists public.maak_admin_label(uuid);
revoke all on function public.admin_list_accounts(),public.admin_blocked_accounts(),
 public.admin_account_moderation_history(uuid) from public,anon;
grant execute on function public.admin_list_accounts(),public.admin_blocked_accounts(),
 public.admin_account_moderation_history(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
