-- POST-DEPLOY SMOKE TEST for 20261022 + 20261023. Calls the moderation RPCs as a
-- real admin through the API role, then ROLLS BACK: nothing is written.
-- Replace REPLACE-WITH-ADMIN-PROFILE-ID with an admin's profiles.id first; left
-- unchanged, the uuid cast fails and nothing runs.
-- Expect: i_am_admin = true; admins_listed = 0; profiles_visible = 1 (own row);
-- pending_appeals >= 0; my_appeal_status says account_active.
begin;
select set_config('request.jwt.claims',json_build_object('sub','REPLACE-WITH-ADMIN-PROFILE-ID'::uuid,'role','authenticated')::text,true);
set local role authenticated;
select public.is_maak_admin() as i_am_admin,
 (select count(*) from public.admin_list_accounts() x where x->>'role' not in ('help_seeker','volunteer')) as admins_listed,
 (select count(*) from public.profiles) as profiles_visible,
 (select count(*) from public.admin_pending_appeals()) as pending_appeals,
 (select string_agg(distinct x->>'blocked_by_name', ', ') from public.admin_blocked_accounts() x) as blocked_by_labels,
 public.my_appeal_status()->>'unavailable_reason' as my_appeal_status;
rollback;
