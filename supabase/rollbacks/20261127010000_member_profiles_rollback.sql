-- Rollback for 20261127010000_member_profiles.sql.
begin;
drop function if exists public.get_maak_member_profile(uuid);
notify pgrst, 'reload schema';
commit;
