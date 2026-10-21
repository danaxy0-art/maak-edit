-- POST-DEPLOY SMOKE TEST for 20261021_account_blocking.sql. Calls the admin RPCs as a
-- real admin through the API role, then ROLLS BACK: nothing is written.
-- Replace REPLACE-WITH-ADMIN-PROFILE-ID with an admin's profiles.id first; left
-- unchanged, the uuid cast fails and nothing runs.
-- Expect: i_am_admin = true, account counts, my_status = {"blocked": false}.
begin;
select set_config('request.jwt.claims',json_build_object('sub','REPLACE-WITH-ADMIN-PROFILE-ID'::uuid,'role','authenticated')::text,true);
set local role authenticated;
select public.is_maak_admin() as i_am_admin,
 (select count(*) from public.admin_list_accounts()) as accounts_visible,
 (select count(*) from public.admin_blocked_accounts()) as currently_blocked,
 public.my_block_status() as my_status;
rollback;
