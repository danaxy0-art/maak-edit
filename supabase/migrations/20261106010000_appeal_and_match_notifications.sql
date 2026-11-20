-- Apply after 20261106000000_push_notifications.sql (and the account appeals and
-- AI matching toggle migrations). Repeatable.
--
-- 1. New account appeal -> push to every admin.
--    The appellant is restricted, and guard_maak_blocked_actor rejects any write to
--    public.notifications made by a restricted caller, so this sends the push directly
--    instead of inserting notification rows. Admins already see pending appeals on
--    the admin overview.
--
-- 2. New matching volunteer -> notification (and push) to each help seeker who
--    would now see that volunteer in Find a volunteer. A volunteer is a match when
--    the volunteer is approved, not restricted, has AI matching on, and shares an
--    active, non-"Other" condition with the seeker; the seeker must have AI matching
--    on, not be restricted, and have no pending/accepted request with them
--    (the same rules as maak_matching_context / browse_volunteers).
--    Checked whenever a volunteer can newly become a match: approval, turning AI
--    matching on, adding a condition, and reactivation. Each seeker is told about a
--    given volunteer at most once (match_notifications_sent).
begin;

-- 1. Appeals --------------------------------------------------------------------
create or replace function public.push_maak_new_appeal() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare admin_id uuid;
begin
 for admin_id in select id from profiles where role='admin' loop
  perform send_maak_push(admin_id,'New account appeal',
   'A restricted member submitted an appeal for review.','appeal',new.id,null);
 end loop;
 return new;
end; $$;
drop trigger if exists maak_appeal_push on public.account_block_appeals;
create trigger maak_appeal_push after insert on public.account_block_appeals
 for each row execute function public.push_maak_new_appeal();

-- 2. New matches ------------------------------------------------------------------
create table if not exists public.match_notifications_sent (
 seeker_id uuid not null references public.profiles(id) on delete cascade,
 volunteer_id uuid not null references public.profiles(id) on delete cascade,
 sent_at timestamptz not null default now(),
 primary key (seeker_id, volunteer_id));
alter table public.match_notifications_sent enable row level security;
revoke all on public.match_notifications_sent from public,anon,authenticated;

create or replace function public.notify_maak_new_matches(p_volunteer uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if p_volunteer is null
  or not exists(select 1 from volunteer_profiles v join profiles p on p.id=v.user_id and p.role='volunteer'
                where v.user_id=p_volunteer and v.status='approved')
  or is_maak_account_blocked(p_volunteer)
  or not exists(select 1 from ai_matching_agreements where user_id=p_volunteer and version='2026-11-05' and enabled)
 then return; end if;

 with fresh as (
  insert into match_notifications_sent(seeker_id,volunteer_id)
  select h.user_id,p_volunteer from help_seeker_profiles h
  join profiles p on p.id=h.user_id and p.role='help_seeker'
  where h.user_id<>p_volunteer
   and not exists(select 1 from account_blocks b where b.user_id=h.user_id)
   and exists(select 1 from ai_matching_agreements a where a.user_id=h.user_id and a.version='2026-11-05' and a.enabled)
   and exists(select 1 from user_conditions s
              join user_conditions v on v.condition_id=s.condition_id and v.user_id=p_volunteer
              join chronic_conditions c on c.id=s.condition_id and c.is_active and not c.is_other
              where s.user_id=h.user_id)
   and not exists(select 1 from support_requests r where r.seeker_id=h.user_id and r.volunteer_id=p_volunteer
                  and r.status in ('pending','accepted'))
  on conflict do nothing
  returning seeker_id)
 insert into notifications(user_id,title,body,kind,reference_id)
 select seeker_id,'A new volunteer matches you',
  'A volunteer who shares your condition is now available. Open Find a volunteer to see them.',
  'match',p_volunteer
 from fresh;
end; $$;

create or replace function public.check_maak_new_matches() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if TG_TABLE_NAME='volunteer_profiles' then
  if new.status='approved' and (TG_OP='INSERT' or old.status is distinct from 'approved') then
   perform notify_maak_new_matches(new.user_id);
  end if;
 elsif TG_TABLE_NAME='ai_matching_agreements' then
  if new.enabled and (TG_OP='INSERT' or not old.enabled) then perform notify_maak_new_matches(new.user_id); end if;
 elsif TG_TABLE_NAME='user_conditions' then
  perform notify_maak_new_matches(new.user_id);
 elsif TG_TABLE_NAME='account_blocks' then
  perform notify_maak_new_matches(old.user_id);
  return old;
 end if;
 return new;
end; $$;

drop trigger if exists maak_match_on_approval on public.volunteer_profiles;
create trigger maak_match_on_approval after insert or update of status on public.volunteer_profiles
 for each row execute function public.check_maak_new_matches();
drop trigger if exists maak_match_on_ai_enabled on public.ai_matching_agreements;
create trigger maak_match_on_ai_enabled after insert or update of enabled on public.ai_matching_agreements
 for each row execute function public.check_maak_new_matches();
drop trigger if exists maak_match_on_condition on public.user_conditions;
create trigger maak_match_on_condition after insert on public.user_conditions
 for each row execute function public.check_maak_new_matches();
drop trigger if exists maak_match_on_reactivation on public.account_blocks;
create trigger maak_match_on_reactivation after delete on public.account_blocks
 for each row execute function public.check_maak_new_matches();

revoke all on function public.push_maak_new_appeal(),public.notify_maak_new_matches(uuid),
 public.check_maak_new_matches() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
