-- Rollback for 20261126100000_volunteer_ratings.sql. Removes only the objects
-- that file created. Deleting the table deletes all submitted ratings.
-- Roll back 20261126110000_volunteer_badges.sql first if it is applied.
begin;
drop function if exists public.maak_volunteer_stats(uuid[]);
drop function if exists public.correct_maak_rating(uuid,integer);
drop function if exists public.rate_maak_volunteer(uuid,integer);
drop function if exists public.my_maak_rating(uuid);
drop function if exists public.maak_can_correct_rating(uuid);
drop function if exists public.maak_rating_state(uuid);
drop function if exists public.maak_rateable_volunteer(uuid);
drop function if exists public.maak_request_had_support(uuid);
drop function if exists public.maak_rating_correction_window();
drop function if exists public.maak_rating_min_for_average();
drop table if exists public.volunteer_ratings;
notify pgrst, 'reload schema';
commit;
