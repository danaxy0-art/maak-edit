-- Member profiles opened from a chat or a Health Library comment (tap the
-- photo or name). Apply after 20261021_account_blocking.sql and
-- 20261018_matching.sql. Repeatable (safe to run twice).
--
-- get_maak_member_profile(p_user_id) returns what the caller may see:
--   * Everyone signed in (and not restricted): name, role, member since.
--   * Approved volunteer: also conditions, language and lived experience,
--     the same details help seekers already see when browsing volunteers.
--   * Help seeker: conditions and language only for someone they have had a
--     support request with (that volunteer already saw them in the request),
--     for themselves, and for administrators. Nobody else sees health details.
-- Admin accounts, restricted accounts and volunteers who are not approved
-- (unless connected) raise 'profile_unavailable'.
begin;

create or replace function public.get_maak_member_profile(p_user_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  me uuid := auth.uid();
  v_admin boolean := is_maak_admin();
  v_profile profiles%rowtype;
  v_volunteer volunteer_profiles%rowtype;
  v_seeker help_seeker_profiles%rowtype;
  v_connected boolean;
  v_self boolean;
  v_conditions text;
  v_result jsonb;
begin
  if me is null then raise exception 'not_allowed'; end if;
  if not v_admin and not is_maak_active() then raise exception 'account_blocked'; end if;

  select * into v_profile from profiles where id = p_user_id;
  if v_profile.id is null or v_profile.role is null
     or v_profile.role not in ('help_seeker', 'volunteer') then
    raise exception 'profile_unavailable';
  end if;
  v_self := p_user_id = me;
  if not v_admin and not v_self and is_maak_account_blocked(p_user_id) then
    raise exception 'profile_unavailable';
  end if;
  v_connected := exists(select 1 from support_requests r
    where (r.seeker_id = me and r.volunteer_id = p_user_id)
       or (r.volunteer_id = me and r.seeker_id = p_user_id));

  select string_agg(c.name, ', ' order by c.name) into v_conditions
  from user_conditions u join chronic_conditions c on c.id = u.condition_id
  where u.user_id = p_user_id and c.is_active and not c.is_other;

  v_result := jsonb_build_object(
    'user_id', v_profile.id,
    'full_name', coalesce(nullif(btrim(v_profile.full_name), ''), 'A member'),
    'role', v_profile.role,
    'member_since', v_profile.created_at,
    'is_self', v_self,
    'connected', v_connected);

  if v_profile.role = 'volunteer' then
    select * into v_volunteer from volunteer_profiles where user_id = p_user_id;
    if v_volunteer.status is distinct from 'approved'
       and not (v_admin or v_self or v_connected) then
      raise exception 'profile_unavailable';
    end if;
    -- Same keys as browse_volunteers, so the app can open the volunteer page.
    v_result := v_result || jsonb_build_object(
      'approved', v_volunteer.status = 'approved',
      'condition', coalesce(v_conditions, v_volunteer.condition_experience),
      'language', v_volunteer.preferred_language,
      'description', v_volunteer.experience_description);
  elsif v_admin or v_self or v_connected then
    select * into v_seeker from help_seeker_profiles where user_id = p_user_id;
    v_result := v_result || jsonb_build_object(
      'condition', coalesce(v_conditions, v_seeker.chronic_condition),
      'language', v_seeker.preferred_language);
  end if;
  return v_result;
end; $$;

revoke all on function public.get_maak_member_profile(uuid) from public, anon;
grant execute on function public.get_maak_member_profile(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
