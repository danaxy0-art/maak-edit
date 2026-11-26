-- Rollback for 20261126110000_volunteer_badges.sql. Removes the badge objects,
-- including all recorded completions, and restores maak_volunteer_stats as
-- 20261126100000_volunteer_ratings.sql defines it (without 'badge').
-- Ratings are not touched. Re-applying the migration backfills only
-- conversations that are ended at that time (see its header).
begin;
create or replace function public.maak_volunteer_stats(p_volunteer_ids uuid[]) returns setof jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
  if coalesce(cardinality(p_volunteer_ids), 0) > 100 then raise exception 'too_many_volunteers'; end if;
  return query
  select jsonb_build_object('volunteer_id', v.user_id, 'rating_count', coalesce(s.n, 0),
           'average_rating', case when coalesce(s.n, 0) >= public.maak_rating_min_for_average()
                                  then round(s.avg_stars, 1) end)
  from (select distinct unnest(p_volunteer_ids) as id) ids
  join volunteer_profiles v on v.user_id = ids.id and v.status = 'approved'
  left join lateral (select count(*)::int as n, avg(stars)::numeric as avg_stars
                     from volunteer_ratings x where x.volunteer_id = v.user_id) s on true
  where not public.is_maak_account_blocked(v.user_id);
end; $$;
drop function if exists public.my_maak_badge_progress();
drop function if exists public.maak_badge_for(integer);
drop function if exists public.maak_volunteer_supported_counts(uuid[]);
drop table if exists public.volunteer_badge_levels;
drop function if exists public.guard_maak_badge_progression();
drop trigger if exists maak_record_support_completion on public.support_requests;
drop function if exists public.record_maak_support_completion();
drop table if exists public.volunteer_support_completions;
notify pgrst, 'reload schema';
commit;
