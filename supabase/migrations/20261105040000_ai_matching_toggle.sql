-- Apply after 20261105030000_message_deletion_video.sql. Repeatable.
begin;
alter table public.ai_matching_agreements add column if not exists enabled boolean not null default true;

create or replace function public.has_maak_ai_consent() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select auth.uid() is not null and public.is_maak_active() and exists(
 select 1 from ai_matching_agreements where user_id=auth.uid() and version='2026-11-05' and enabled);
$$;
create or replace function public.set_maak_ai_matching_enabled(p_enabled boolean) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null or not public.is_maak_active() or not exists(select 1 from profiles where id=auth.uid() and role in ('help_seeker','volunteer')) then raise exception 'not_allowed'; end if;
 if p_enabled is null then raise exception 'invalid_setting'; end if;
 -- Serializes enable/disable with profile updates for this account.
 perform 1 from profiles where id=auth.uid() for update;
 if p_enabled then
  insert into ai_matching_agreements(user_id,version,enabled) values(auth.uid(),'2026-11-05',true)
  on conflict(user_id) do update set enabled=true,version=excluded.version,
   accepted_at=case when ai_matching_agreements.version=excluded.version then ai_matching_agreements.accepted_at else now() end;
 else
  update ai_matching_agreements set enabled=false where user_id=auth.uid();
 end if;
 update volunteer_profiles set ai_matching_consent=p_enabled where user_id=auth.uid();
end; $$;
create or replace function public.accept_maak_ai_matching(p_version text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if p_version is distinct from '2026-11-05' then raise exception 'invalid_consent_version'; end if;
 perform public.set_maak_ai_matching_enabled(true);
end; $$;
-- A stale profile form must never override the saved toggle.
create or replace function public.sync_maak_volunteer_ai_setting() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 new.ai_matching_consent:=exists(select 1 from ai_matching_agreements where user_id=new.user_id and version='2026-11-05' and enabled);
 return new;
end; $$;
drop trigger if exists maak_sync_volunteer_ai on public.volunteer_profiles;
create trigger maak_sync_volunteer_ai before insert or update on public.volunteer_profiles for each row execute function public.sync_maak_volunteer_ai_setting();
update public.volunteer_profiles v set ai_matching_consent=a.enabled from public.ai_matching_agreements a where a.user_id=v.user_id and a.version='2026-11-05';
revoke all on function public.sync_maak_volunteer_ai_setting() from public,anon,authenticated;
revoke all on function public.set_maak_ai_matching_enabled(boolean) from public,anon;
grant execute on function public.set_maak_ai_matching_enabled(boolean) to authenticated;

-- Wrap installed implementations to preserve the team's latest request,
-- approval, shared-condition, blocking and existing-connection checks.
do $$ begin
 if to_regprocedure('public.maak_matching_context_before_toggle()') is null then
  alter function public.maak_matching_context() rename to maak_matching_context_before_toggle;
 end if;
 if to_regprocedure('public.browse_volunteers_before_toggle()') is null then
  alter function public.browse_volunteers() rename to browse_volunteers_before_toggle;
 end if;
 if to_regprocedure('public.request_peer_support_before_toggle(uuid)') is null then
  alter function public.request_peer_support(uuid) rename to request_peer_support_before_toggle;
 end if;
end; $$;
revoke all on function public.maak_matching_context_before_toggle(),public.browse_volunteers_before_toggle(),public.request_peer_support_before_toggle(uuid) from public,anon,authenticated;

create or replace function public.maak_matching_context() returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare context jsonb; candidates jsonb;
begin
 if auth.uid() is null then raise exception 'not_allowed'; end if;
 if not public.is_maak_active() then raise exception 'account_blocked'; end if;
 if not public.has_maak_ai_consent() then raise exception 'ai_matching_disabled'; end if;
 context:=public.maak_matching_context_before_toggle();
 select coalesce(jsonb_agg(card),'[]'::jsonb) into candidates
 from jsonb_array_elements(context->'candidates') card
 where exists(select 1 from ai_matching_agreements a where a.user_id::text=card->>'user_id' and a.version='2026-11-05' and a.enabled)
 and not exists(select 1 from account_blocks b where b.user_id::text=card->>'user_id');
 return jsonb_set(context,'{candidates}',candidates);
end; $$;
create or replace function public.browse_volunteers() returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'not_allowed'; end if;
 if not public.is_maak_active() then raise exception 'account_blocked'; end if;
 if exists(select 1 from profiles where id=auth.uid() and role='help_seeker') and not public.has_maak_ai_consent() then raise exception 'ai_matching_disabled'; end if;
 return query select card from public.browse_volunteers_before_toggle() card
 where exists(select 1 from ai_matching_agreements a where a.user_id::text=card->>'user_id' and a.version='2026-11-05' and a.enabled)
 and not exists(select 1 from account_blocks b where b.user_id::text=card->>'user_id');
end; $$;
create or replace function public.request_peer_support(p_volunteer_id uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not public.has_maak_ai_consent() then raise exception 'ai_matching_disabled'; end if;
 if not exists(select 1 from ai_matching_agreements where user_id=p_volunteer_id and version='2026-11-05' and enabled) then raise exception 'volunteer_matching_disabled'; end if;
 perform public.request_peer_support_before_toggle(p_volunteer_id);
end; $$;
revoke all on function public.maak_matching_context(),public.browse_volunteers(),public.request_peer_support(uuid) from public,anon;
grant execute on function public.maak_matching_context(),public.browse_volunteers(),public.request_peer_support(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
