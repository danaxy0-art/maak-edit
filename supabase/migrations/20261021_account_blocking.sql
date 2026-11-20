-- =====================================================================================
-- DEPLOYED TO PRODUCTION ON 2026-10-21 - DO NOT RE-RUN ON THE MAIN MA'AK PROJECT.
-- Production also received supabase/production/20261021_production_compat.sql right
-- after this file. Re-running this file there would remove production's open-request
-- rule from maak_matching_context(), grant my_support_sessions() to authenticated, and
-- overwrite the later versions of admin_list_accounts, admin_blocked_accounts and
-- admin_account_moderation_history (20261022) and admin_block_account (20261023).
-- If it is ever re-run, immediately re-apply the compat patch, then 20261022 and
-- 20261023, and run their verification scripts.
-- Applied through the Supabase SQL Editor: migration history may not list it. Do not
-- run `supabase db push` or `supabase migration repair` against production until the
-- team has reconciled the history. Never run supabase_schema.sql or APPLY_UPDATES.sql
-- on production without review. Fresh databases: see supabase/production/README.md.
-- =====================================================================================
-- Apply after 20261020_profile_repair.sql. Idempotent; preserves existing data.
-- Also requires the live-only support_requests.restricted_at column (see can_send_maak_message).
-- Admin account blocking (SWE 444): block with reason, list blocked, reactivate.
--
-- Security model:
--  * Block state lives in tables users cannot write or read directly. It is NOT
--    a profiles column, because users may update their own profiles row.
--  * Only active admins can change it, through SECURITY DEFINER RPCs that write
--    the current state and the audit event in one transaction.
--  * Writes by a blocked user are stopped by triggers on the protected tables.
--    Triggers also fire inside SECURITY DEFINER RPCs, so every existing write
--    path (profile saves, requests, sessions, messages) is covered.
--  * Reads are stopped by RLS (is_maak_active) and by filters in the
--    SECURITY DEFINER read RPCs, which bypass RLS.
--  * Existing JWTs stay valid until they expire; this migration makes them
--    useless for protected data. Auth-level banning is a separate step.
-- Only the policies, triggers and functions named below are replaced.
-- WARNING: re-running supabase_schema.sql or 20261018_*.sql replaces the policies
-- and functions redefined here. Re-apply this file after any such re-run.
begin;
-- Triggers and policies take brief exclusive table locks. Fail fast (and roll back
-- everything) instead of queueing app traffic behind a long-running transaction.
set local lock_timeout = '10s';

-- 1. Protected tables --------------------------------------------------------
-- Current state: one row per blocked account. Deleting the account removes it.
create table if not exists public.account_blocks (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 reason text not null,
 blocked_by uuid references public.profiles(id) on delete set null,
 blocked_at timestamptz not null default now()
);
-- Same rule as Flutter validateReason(): non-empty after trimming, at most 500.
alter table public.account_blocks drop constraint if exists account_blocks_reason_check;
alter table public.account_blocks add constraint account_blocks_reason_check check(char_length(reason) between 1 and 500);

-- Append-only audit trail. No foreign keys, so history survives account deletion.
create table if not exists public.account_moderation_events (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null,
 action text not null check(action in ('blocked','reactivated')),
 reason text check(reason is null or char_length(reason) between 1 and 500),
 actor_id uuid not null,
 created_at timestamptz not null default now(),
 check(action<>'blocked' or reason is not null)
);
create index if not exists moderation_events_user_date on public.account_moderation_events(user_id,created_at desc);

-- RLS on with no policies: deny all direct client access. Supabase grants
-- table privileges to anon/authenticated by default, so revoke them as well.
alter table public.account_blocks enable row level security;
alter table public.account_moderation_events enable row level security;
revoke all on public.account_blocks,public.account_moderation_events from public,anon,authenticated;

-- History is immutable for every role except a superuser who disables the trigger.
create or replace function public.guard_moderation_history() returns trigger
language plpgsql set search_path=public,pg_temp as $$
begin raise exception 'moderation_history_immutable'; end; $$;
drop trigger if exists maak_moderation_history_immutable on public.account_moderation_events;
create trigger maak_moderation_history_immutable before update or delete on public.account_moderation_events
 for each row execute function public.guard_moderation_history();
drop trigger if exists maak_moderation_history_no_truncate on public.account_moderation_events;
create trigger maak_moderation_history_no_truncate before truncate on public.account_moderation_events
 for each statement execute function public.guard_moderation_history();

-- Admins can never be blocked, even by a direct SQL insert. Only checked when the
-- target changes, so ON DELETE SET NULL of blocked_by can never fail.
create or replace function public.guard_account_block_target() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if exists(select 1 from profiles where id=new.user_id and role='admin') then raise exception 'cannot_block_admin'; end if;
 return new;
end; $$;
drop trigger if exists maak_account_block_target on public.account_blocks;
create trigger maak_account_block_target before insert or update of user_id on public.account_blocks
 for each row execute function public.guard_account_block_target();

-- 2. Status helpers ----------------------------------------------------------
-- Internal: reveals any user's block state, so clients cannot execute it.
create or replace function public.is_maak_account_blocked(p_user_id uuid) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from account_blocks where user_id=p_user_id);
$$;
-- The caller is signed in and not blocked. Used by RLS policies.
create or replace function public.is_maak_active() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select auth.uid() is not null and not exists(select 1 from account_blocks where user_id=auth.uid());
$$;
-- Defence in depth: a blocked row also removes admin rights. Same signature,
-- return type and grants as supabase_schema.sql.
create or replace function public.is_maak_admin() returns boolean language sql stable security definer
set search_path=public,pg_temp as $$
 select exists(select 1 from profiles p where p.id=auth.uid() and p.role='admin'
  and not exists(select 1 from account_blocks b where b.user_id=p.id));
$$;
-- Matches Dart String.trim(): strips leading/trailing whitespace, keeps line breaks inside.
create or replace function public.trim_maak_reason(value text) returns text
language sql immutable set search_path=public,pg_temp as $$
 select nullif(regexp_replace(coalesce(value,''),'^[[:space:]]+|[[:space:]]+$','','g'),'');
$$;

-- 3. Write enforcement (triggers) --------------------------------------------
-- A blocked caller cannot insert, update or delete rows in these tables, either
-- directly or through any RPC. Calls with no user (auth.uid() null: service role,
-- Auth sign-up trigger, SQL editor, cascades from account deletion) are allowed,
-- as are admin actions on a blocked user's rows (e.g. reviewing an application).
-- The KEY SHARE lock waits for an in-flight admin_block_account (which holds
-- FOR UPDATE on the same profiles row), so a write cannot slip past a block.
create or replace function public.guard_maak_blocked_actor() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid();
begin
 if me is not null then
  perform 1 from profiles where id=me for key share;
  if is_maak_account_blocked(me) then raise exception 'account_blocked'; end if;
 end if;
 if TG_OP='DELETE' then return old; end if;
 return new;
end; $$;
do $$ declare t text; begin
 foreach t in array array['profiles','help_seeker_profiles','volunteer_profiles','user_conditions',
  'condition_review_requests','support_requests','support_sessions','messages','notifications'] loop
  execute format('drop trigger if exists maak_blocked_actor_guard on public.%I',t);
  execute format('create trigger maak_blocked_actor_guard before insert or update or delete on public.%I for each row execute function public.guard_maak_blocked_actor()',t);
 end loop;
end $$;

-- Participant rules for ordinary users (admin and service-role maintenance is exempt).
-- Runs after maak_blocked_actor_guard (same-event BEFORE triggers fire in name
-- order), so a blocked caller is always rejected first with account_blocked.
--  * seeker_id/volunteer_id (requests) and request_id (messages, sessions) are
--    immutable after creation. This also applies inside SECURITY DEFINER RPCs,
--    because auth.uid() is still the calling user there.
--  * New contact with a blocked participant is denied: creating a request, message
--    or session, any request status change except declining, and rescheduling.
--  * Other updates pass, e.g. the team's restricted_at restriction/unrestriction
--    and declining, so an active user can always end contact with a blocked one.
-- Changes to the columns compared here are found by value, whichever columns an
-- UPDATE names, so the trigger fires on every update.
create or replace function public.guard_maak_blocked_participants() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare seeker uuid; volunteer uuid;
begin
 if auth.uid() is null or is_maak_admin() then return new; end if;
 if TG_OP='UPDATE' then
  if TG_TABLE_NAME='support_requests' then
   if new.seeker_id is distinct from old.seeker_id or new.volunteer_id is distinct from old.volunteer_id then
    raise exception 'request_participants_immutable'; end if;
   if new.status is not distinct from old.status or new.status='declined' then return new; end if;
  else
   if new.request_id is distinct from old.request_id then raise exception 'request_link_immutable'; end if;
   if TG_TABLE_NAME='messages' then return new; end if;
   -- support_sessions: only a reschedule is new contact.
   if new.starts_at is not distinct from old.starts_at
    and new.duration_minutes is not distinct from old.duration_minutes then return new; end if;
  end if;
 end if;
 if TG_TABLE_NAME='support_requests' then seeker:=new.seeker_id; volunteer:=new.volunteer_id;
 else select r.seeker_id,r.volunteer_id into seeker,volunteer from support_requests r where r.id=new.request_id; end if;
 -- Waits for an in-flight admin_block_account on either participant (see actor guard).
 perform 1 from profiles where id in (seeker,volunteer) order by id for key share;
 if is_maak_account_blocked(seeker) or is_maak_account_blocked(volunteer) then raise exception 'participant_unavailable'; end if;
 return new;
end; $$;
do $$ declare t text; begin
 foreach t in array array['support_requests','support_sessions','messages'] loop
  execute format('drop trigger if exists maak_blocked_participant_guard on public.%I',t);
  execute format('create trigger maak_blocked_participant_guard before insert or update on public.%I for each row execute function public.guard_maak_blocked_participants()',t);
 end loop;
end $$;

-- A blocked account cannot be promoted to admin (e.g. in the SQL editor). It
-- would otherwise hold an admin role it cannot use and that nobody can unblock.
create or replace function public.guard_blocked_admin_promotion() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.role='admin' and is_maak_account_blocked(new.id) then raise exception 'account_blocked'; end if;
 return new;
end; $$;
drop trigger if exists maak_blocked_role_guard on public.profiles;
create trigger maak_blocked_role_guard before update of role on public.profiles
 for each row execute function public.guard_blocked_admin_promotion();

-- 4. RLS policies (read and direct-write access) -----------------------------
-- Each policy is dropped and recreated with its original name, roles and
-- command; only the block check is added. (select ...) evaluates it once per query.
-- profiles_read is intentionally unchanged: a blocked user may still read their
-- own role and name, so the app can route them to the blocked screen.
-- conditions_read stays public (anon catalogue). Admin policies use is_maak_admin().
drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert to authenticated
 with check(id=auth.uid() and role in ('help_seeker','volunteer') and (select is_maak_active()));
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
 using(id=auth.uid() and (select is_maak_active())) with check(id=auth.uid() and (select is_maak_active()));
drop policy if exists seekers_owner_read on public.help_seeker_profiles;
create policy seekers_owner_read on public.help_seeker_profiles for select to authenticated
 using(user_id=auth.uid() and (select is_maak_active()));
drop policy if exists volunteers_read on public.volunteer_profiles;
create policy volunteers_read on public.volunteer_profiles for select to authenticated
 using((user_id=auth.uid() and (select is_maak_active())) or is_maak_admin());
drop policy if exists user_conditions_read on public.user_conditions;
create policy user_conditions_read on public.user_conditions for select to authenticated
 using((user_id=auth.uid() and (select is_maak_active())) or is_maak_admin());
drop policy if exists condition_requests_read on public.condition_review_requests;
create policy condition_requests_read on public.condition_review_requests for select to authenticated
 using((user_id=auth.uid() and (select is_maak_active())) or is_maak_admin());
-- Notifications and messages are also streamed by Realtime, which applies these.
drop policy if exists notification_read on public.notifications;
create policy notification_read on public.notifications for select to authenticated
 using(user_id=auth.uid() and (select is_maak_active()));
drop policy if exists notification_update on public.notifications;
create policy notification_update on public.notifications for update to authenticated
 using(user_id=auth.uid() and (select is_maak_active())) with check(user_id=auth.uid() and (select is_maak_active()));
drop policy if exists requests_read on public.support_requests;
create policy requests_read on public.support_requests for select to authenticated
 using((seeker_id=auth.uid() or volunteer_id=auth.uid()) and (select is_maak_active()));
drop policy if exists messages_read on public.messages;
create policy messages_read on public.messages for select to authenticated
 using((select is_maak_active()) and exists(select 1 from support_requests r where r.id=request_id and (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid())));
drop policy if exists sessions_read on public.support_sessions;
create policy sessions_read on public.support_sessions for select to authenticated
 using((select is_maak_active()) and exists(select 1 from support_requests r where r.id=request_id and (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid())));
drop policy if exists resources_read on public.resources;
create policy resources_read on public.resources for select to authenticated using((select is_maak_active()));

-- Latest: the LIVE database, which adds the team's restricted-request check
-- (support_requests.restricted_at). That change is not in the repository; it is kept
-- unchanged here. Messaging additionally requires both participants to be active.
-- Requires support_requests.restricted_at: this function fails to compile without it.
create or replace function public.can_send_maak_message(p_request_id uuid) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select is_maak_active() and exists(select 1 from support_requests r join volunteer_profiles v on v.user_id=r.volunteer_id
  where r.id=p_request_id and r.status='accepted' and v.status='approved'
   and r.restricted_at is null
   and (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid())
   and not exists(select 1 from account_blocks b where b.user_id in (r.seeker_id,r.volunteer_id)));
$$;
drop policy if exists messages_send on public.messages;
create policy messages_send on public.messages for insert to authenticated
 with check(sender_id=auth.uid() and (select is_maak_active()) and can_send_maak_message(request_id));

-- Verification documents: blocked users cannot upload or download their files.
drop policy if exists maak_document_upload on storage.objects;
create policy maak_document_upload on storage.objects for insert to authenticated
 with check(bucket_id='verification-documents' and auth.uid()::text=(storage.foldername(name))[1] and (select public.is_maak_active()));
drop policy if exists maak_document_read on storage.objects;
create policy maak_document_read on storage.objects for select to authenticated
 using(bucket_id='verification-documents' and ((auth.uid()::text=(storage.foldername(name))[1] and (select public.is_maak_active())) or public.is_maak_admin()));

-- 5. SECURITY DEFINER read RPCs (bypass RLS, so filter explicitly) -----------
-- Bodies are copied from their latest Sprint 2 versions; only block checks are
-- added. Signatures, return types and volatility are unchanged, and
-- CREATE OR REPLACE keeps existing grants (re-asserted in section 7).
-- Latest: 20261018_matching.sql. Blocked callers get nothing; blocked volunteers are hidden.
create or replace function public.browse_volunteers() returns setof jsonb language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object('user_id',v.user_id,'full_name',p.full_name,
 'condition',coalesce((select string_agg(c.name,', ' order by c.name) from user_conditions u join chronic_conditions c on c.id=u.condition_id where u.user_id=v.user_id and c.is_active),v.condition_experience),
 'language',v.preferred_language,'description',v.experience_description)
 from volunteer_profiles v join profiles p on p.id=v.user_id and p.role='volunteer'
 where is_maak_active() and v.status='approved'
 and not exists(select 1 from account_blocks b where b.user_id=v.user_id)
 order by p.full_name;
$$;

-- Latest: 20261018_condition_reviews.sql (general mode). Also feeds match-volunteers.
create or replace function public.maak_matching_context() returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); own jsonb; candidates jsonb; general boolean;
begin
 if me is null or not exists(select 1 from profiles where id=me and role='help_seeker') then raise exception 'not_allowed'; end if;
 if not is_maak_active() then raise exception 'account_blocked'; end if;
 select jsonb_build_object('description',coalesce(h.description,''),'language',h.preferred_language,
 'conditions',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name)
 from user_conditions u join chronic_conditions c on c.id=u.condition_id where u.user_id=me and c.is_active and not c.is_other),'[]'::jsonb))
 into own from help_seeker_profiles h where h.user_id=me;
 if own is null then raise exception 'profile_incomplete'; end if;
 general:=jsonb_array_length(own->'conditions')=0;
 select coalesce(jsonb_agg(card order by card->>'user_id'),'[]'::jsonb) into candidates from (
 select jsonb_build_object('user_id',v.user_id,'full_name',p.full_name,'language',v.preferred_language,
 'condition',v.condition_experience,'description',v.experience_description,'ai_consent',v.ai_matching_consent,'status',v.status,
 'conditions',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name)
 from user_conditions u join chronic_conditions c on c.id=u.condition_id where u.user_id=v.user_id and c.is_active and not c.is_other),'[]'::jsonb)) card
 from volunteer_profiles v join profiles p on p.id=v.user_id and p.role='volunteer'
 where v.status='approved' and v.user_id<>me
 and not exists(select 1 from account_blocks b where b.user_id=v.user_id)
 and (general or exists(
 select 1 from user_conditions a join user_conditions b on b.condition_id=a.condition_id
 join chronic_conditions c on c.id=a.condition_id and c.is_active and not c.is_other
 where a.user_id=me and b.user_id=v.user_id))
 ) q;
 return jsonb_build_object('seeker',own,'candidates',candidates,'general_mode',general);
end; $$;

-- Latest: 20261018_matching.sql.
create or replace function public.my_maak_conditions() returns setof jsonb
language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object('id',c.id,'name',c.name,'is_active',c.is_active)
 from user_conditions u join chronic_conditions c on c.id=u.condition_id
 where u.user_id=auth.uid() and is_maak_active() order by c.sort_order,c.name;
$$;

-- Latest: supabase_schema.sql. Active users keep their history with a blocked
-- contact; the additive contact_available key lets the UI disable chat and booking.
create or replace function public.my_support_requests() returns setof jsonb language sql stable security definer set search_path=public,pg_temp as $$
 select to_jsonb(r)||jsonb_build_object('contact_name',p.full_name,'condition',h.chronic_condition,
  'description',h.description,'last_message',(select body from messages where request_id=r.id order by created_at desc limit 1),
  'contact_available',not exists(select 1 from account_blocks b where b.user_id=p.id))
 from support_requests r join profiles p on p.id=case when r.seeker_id=auth.uid() then r.volunteer_id else r.seeker_id end
 join help_seeker_profiles h on h.user_id=r.seeker_id
 where (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid()) and is_maak_active() order by r.created_at desc;
$$;

-- Latest: supabase_schema.sql.
create or replace function public.my_support_sessions() returns setof jsonb language sql stable security definer set search_path=public,pg_temp as $$
 select to_jsonb(s)||jsonb_build_object('contact_name',p.full_name) from support_sessions s join support_requests r on r.id=s.request_id
  join profiles p on p.id=case when r.seeker_id=auth.uid() then r.volunteer_id else r.seeker_id end
  where (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid()) and is_maak_active() order by s.starts_at;
$$;
-- Write RPCs (save_maak_profile*, request_peer_support, decide_support_request,
-- book_support_session) are unchanged; the triggers in section 3 stop them.
-- ensure_maak_profile is unchanged: it only returns or repairs the caller's own role.

-- 6. Moderation RPCs ---------------------------------------------------------
-- Error codes avoid substrings already mapped by Flutter friendlyError()
-- (e.g. 'not_allowed', 'reason_required').
-- Admin: every account with its block state. Includes email so admins can identify people.
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

-- Admin: currently blocked accounts with blocking details.
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

-- Admin: full block/reactivation history for one account, newest first.
create or replace function public.admin_account_moderation_history(p_user_id uuid) returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 return query select jsonb_build_object('id',e.id,'action',e.action,'reason',e.reason,
  'actor_id',e.actor_id,'actor_name',a.full_name,'created_at',e.created_at)
 from account_moderation_events e left join profiles a on a.id=e.actor_id
 where e.user_id=p_user_id order by e.created_at desc;
end; $$;

-- Admin: block a non-admin account other than your own. State and audit event are
-- written in this function's single transaction. The FOR UPDATE lock on the target
-- profile serialises concurrent block/reactivate calls and in-flight user writes.
create or replace function public.admin_block_account(p_user_id uuid,p_reason text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); target_role text; clean text:=trim_maak_reason(p_reason);
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if p_user_id is null then raise exception 'account_not_found'; end if;
 if p_user_id=me then raise exception 'cannot_block_self'; end if;
 if clean is null or char_length(clean)>500 then raise exception 'invalid_block_reason'; end if;
 select role into target_role from profiles where id=p_user_id for update;
 if not found then raise exception 'account_not_found'; end if;
 if target_role='admin' then raise exception 'cannot_block_admin'; end if;
 insert into account_blocks(user_id,reason,blocked_by) values(p_user_id,clean,me) on conflict(user_id) do nothing;
 if not found then raise exception 'already_blocked'; end if;
 insert into account_moderation_events(user_id,action,reason,actor_id) values(p_user_id,'blocked',clean,me);
end; $$;

-- Admin: reactivate a blocked account. The note is optional (at most 500 characters).
-- The history row is kept; the user is notified. Same locking as admin_block_account.
create or replace function public.admin_reactivate_account(p_user_id uuid,p_note text default null) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); clean text:=trim_maak_reason(p_note);
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if clean is not null and char_length(clean)>500 then raise exception 'invalid_block_reason'; end if;
 perform 1 from profiles where id=p_user_id for update;
 if not found then raise exception 'account_not_found'; end if;
 delete from account_blocks where user_id=p_user_id;
 if not found then raise exception 'not_blocked'; end if;
 insert into account_moderation_events(user_id,action,reason,actor_id) values(p_user_id,'reactivated',clean,me);
 insert into notifications(user_id,title,body,kind) values(p_user_id,'Account reactivated',
  'Your Ma''ak account has been reactivated. Welcome back.','account');
end; $$;

-- Any signed-in user, including a blocked one: their own status. Does not reveal which admin blocked them.
create or replace function public.my_block_status() returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'not_allowed'; end if;
 select jsonb_build_object('blocked',true,'reason',reason,'blocked_at',blocked_at) into result
 from account_blocks where user_id=auth.uid();
 return coalesce(result,jsonb_build_object('blocked',false));
end; $$;

-- 7. Function privileges -----------------------------------------------------
-- Supabase default privileges grant EXECUTE to anon/authenticated on new
-- functions, so revoke from them explicitly, not only from public.
-- Internal helpers and trigger functions: no client execution.
revoke all on function public.is_maak_account_blocked(uuid),public.trim_maak_reason(text),
 public.guard_maak_blocked_actor(),public.guard_maak_blocked_participants(),public.guard_blocked_admin_promotion(),
 public.guard_account_block_target(),public.guard_moderation_history() from public,anon,authenticated;
-- is_maak_active is evaluated inside authenticated RLS policies.
revoke all on function public.is_maak_active() from public,anon;
grant execute on function public.is_maak_active() to authenticated;
-- Unchanged from schema: anon needs is_maak_admin for the public conditions policy.
revoke all on function public.is_maak_admin() from public;
grant execute on function public.is_maak_admin() to anon,authenticated;
revoke all on function public.can_send_maak_message(uuid),public.browse_volunteers(),public.maak_matching_context(),
 public.my_maak_conditions(),public.my_support_requests(),public.my_support_sessions(),
 public.admin_list_accounts(),public.admin_blocked_accounts(),public.admin_account_moderation_history(uuid),
 public.admin_block_account(uuid,text),public.admin_reactivate_account(uuid,text),public.my_block_status() from public,anon;
grant execute on function public.can_send_maak_message(uuid),public.browse_volunteers(),public.maak_matching_context(),
 public.my_maak_conditions(),public.my_support_requests(),public.my_support_sessions(),
 public.admin_list_accounts(),public.admin_blocked_accounts(),public.admin_account_moderation_history(uuid),
 public.admin_block_account(uuid,text),public.admin_reactivate_account(uuid,text),public.my_block_status() to authenticated;
notify pgrst,'reload schema';
commit;
