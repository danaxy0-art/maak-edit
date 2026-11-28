-- =====================================================================================
-- Ma'ak | SWE 444 | Sprint 3 | Admin: lift a conversation restriction
-- NOT YET APPLIED anywhere. Apply after 20261106100000_admin_report_management.sql,
-- through the SQL Editor after team approval (never `supabase db push`). Idempotent.
-- Rollback: supabase/rollbacks/20261107110000_admin_lift_restriction_rollback.sql
-- Verify (read-only): supabase/checks/20261107110000_admin_lift_restriction_verify.sql
-- =====================================================================================
-- * conversation_restriction_events: append-only history of every restriction and
--   every lift (who, when, why). No client access; no foreign keys, so history
--   outlives conversations and accounts (like account_moderation_events).
-- * A trigger on support_requests records each change of restricted_at, so
--   restrictions made by ANY path (production admin_restrict_conversation, which
--   admin_end_reported_conversation calls, or SQL) are recorded the same way. The
--   production restriction function itself is NOT changed.
-- * admin_lift_conversation_restriction(request_id, reason): admin-only. Clears the
--   three restriction columns and nothing else: ended_at/ended_by (a participant's
--   End Chat), account blocks and every chat eligibility check are untouched, so
--   can_send_maak_message still decides who may chat. Participants with an account
--   get a generic 'restriction_lifted' notification; the admin's reason is never
--   shown to them.
-- * admin_conversation_restriction_history(request_id): admin-only read of the events.
begin;
set local lock_timeout = '10s';

do $$ begin
 if to_regprocedure('public.admin_end_reported_conversation(uuid,text)') is null then
  raise exception 'Apply 20261106100000_admin_report_management.sql first';
 end if;
 if to_regprocedure('public.guard_moderation_history()') is null
    or to_regprocedure('public.maak_admin_label(uuid)') is null then
  raise exception 'Apply 20261021_account_blocking.sql and 20261022_account_moderation_visibility.sql first';
 end if;
end $$;

-- 1. History table ------------------------------------------------------------------------
create table if not exists public.conversation_restriction_events (
 id uuid primary key default gen_random_uuid(),
 request_id uuid not null,
 action text not null check (action in ('restricted','lifted')),
 reason text not null check (char_length(reason) between 1 and 500),
 actor_id uuid,
 created_at timestamptz not null default now()
);
create index if not exists restriction_events_request_date
 on public.conversation_restriction_events(request_id, created_at desc);
alter table public.conversation_restriction_events enable row level security;
revoke all on public.conversation_restriction_events from public, anon, authenticated;
-- Same immutability as the account moderation history.
drop trigger if exists maak_restriction_events_immutable on public.conversation_restriction_events;
create trigger maak_restriction_events_immutable before update or delete on public.conversation_restriction_events
 for each row execute function public.guard_moderation_history();
drop trigger if exists maak_restriction_events_no_truncate on public.conversation_restriction_events;
create trigger maak_restriction_events_no_truncate before truncate on public.conversation_restriction_events
 for each statement execute function public.guard_moderation_history();

-- 2. Record every restriction change, whatever made it ------------------------------------
create or replace function public.record_maak_restriction_event() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.restricted_at is not null and new.restricted_at is distinct from old.restricted_at then
  insert into conversation_restriction_events(request_id, action, reason, actor_id, created_at)
   values (new.id, 'restricted', coalesce(nullif(trim(new.restriction_reason), ''), 'No reason recorded'),
           new.restricted_by, new.restricted_at);
 elsif old.restricted_at is not null and new.restricted_at is null then
  insert into conversation_restriction_events(request_id, action, reason, actor_id)
   values (new.id, 'lifted',
           coalesce(nullif(current_setting('maak.restriction_lift_reason', true), ''), 'Lifted outside the Ma''ak app'),
           auth.uid());
 end if;
 return null;
end; $$;
drop trigger if exists maak_record_restriction_event on public.support_requests;
create trigger maak_record_restriction_event after update of restricted_at on public.support_requests
 for each row when (old.restricted_at is distinct from new.restricted_at)
 execute function public.record_maak_restriction_event();

-- Restrictions that already exist get their 'restricted' event once (idempotent).
insert into public.conversation_restriction_events(request_id, action, reason, actor_id, created_at)
select s.id, 'restricted', coalesce(nullif(trim(s.restriction_reason), ''), 'No reason recorded'),
       s.restricted_by, s.restricted_at
from public.support_requests s
where s.restricted_at is not null
  and not exists(select 1 from public.conversation_restriction_events e
                 where e.request_id = s.id and e.action = 'restricted' and e.created_at = s.restricted_at);

-- 3. Lift RPC ---------------------------------------------------------------------------------
create or replace function public.admin_lift_conversation_restriction(p_request_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare clean text := trim_maak_reason(p_reason); r support_requests%rowtype;
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if clean is null or char_length(clean) > 500 then raise exception 'invalid_lift_reason'; end if;
 -- Same row lock as admin_restrict_conversation and End Chat, so they serialise.
 select * into r from support_requests where id = p_request_id for update;
 if not found then raise exception 'conversation_unavailable'; end if;
 if r.restricted_at is null then raise exception 'conversation_not_restricted'; end if;
 perform set_config('maak.restriction_lift_reason', clean, true);
 update support_requests set restricted_at = null, restricted_by = null, restriction_reason = null
  where id = p_request_id;
 perform set_config('maak.restriction_lift_reason', '', true);
 -- Generic notice; the admin's reason stays admin-only.
 insert into notifications(user_id, title, body, kind, reference_id)
 select u, 'Conversation restriction lifted',
        'An administrator lifted the restriction on your conversation.', 'restriction_lifted', p_request_id
 from unnest(array[r.seeker_id, r.volunteer_id]) as u
 where exists(select 1 from profiles p where p.id = u);
 return jsonb_build_object('request_id', p_request_id, 'lifted', true,
  'participant_ended', r.ended_at is not null);
end; $$;

-- 4. History read (admin only; admin UUIDs are never returned, only labels) ------------------
create or replace function public.admin_conversation_restriction_history(p_request_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 return query select jsonb_build_object('id', e.id, 'action', e.action, 'reason', e.reason,
   'actor_name', case when e.actor_id is null then 'Outside the app' else maak_admin_label(e.actor_id) end,
   'actor_is_me', coalesce(e.actor_id = auth.uid(), false), 'created_at', e.created_at)
  from conversation_restriction_events e
  where e.request_id = p_request_id
  order by e.created_at desc, e.action desc;
end; $$;

-- 5. Privileges -----------------------------------------------------------------------------
revoke all on function public.record_maak_restriction_event() from public, anon, authenticated;
revoke all on function public.admin_lift_conversation_restriction(uuid, text),
 public.admin_conversation_restriction_history(uuid) from public, anon;
grant execute on function public.admin_lift_conversation_restriction(uuid, text),
 public.admin_conversation_restriction_history(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
