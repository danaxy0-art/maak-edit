-- =====================================================================================
-- Ma'ak | SWE 444 | Sprint 3 | Admin Report Management (US1-US5)
-- NOT YET APPLIED anywhere. Test on a separate Supabase project first; apply to
-- production only after team approval, through the SQL Editor, never `db push`.
-- Idempotent. Rollback: supabase/rollbacks/20261106100000_admin_report_management_rollback.sql
-- Verify (read-only): supabase/checks/20261106100000_admin_report_management_verify.sql
-- =====================================================================================
-- Builds on Razan's 20261105_message_reports.sql (reports table, report_maak_message,
-- message snapshot). That file and its RPC are not changed. This file only:
--  * extends reports.status by one value, 'conversation_ended' (open/reviewed/dismissed
--    are kept); adds no column to reports and does not change its policies or grants;
--  * records who decided, when and why in report_decisions (no client access, because
--    reporters can read every column of their own reports rows);
--  * makes report evidence immutable and a decision final (one decision per report);
--  * adds four admin-only RPCs: list, details, dismiss, end reported conversation.
--
-- Ending a conversation reuses the PRODUCTION admin_restrict_conversation(uuid,text),
-- verified below by its body fingerprint (the 2026-10-21 production export in
-- tests/database/production_compat/05_production_definitions.sql). It sets
-- support_requests.restricted_at/restricted_by/restriction_reason and notifies both
-- participants (kind 'restricted', the reason is included in the notification).
-- Already in the database, a restricted conversation refuses: new messages and media
-- uploads (can_send_maak_message), reactions (toggle_maak_reaction), and reopen
-- requests and decisions (request_/decide_maak_chat_reopen). Messages are kept.
-- Accounts are never blocked or deleted by these RPCs.
--
-- Security model (same as account moderation):
--  * Every RPC is SECURITY DEFINER and raises not_allowed unless is_maak_admin().
--  * No new client grants on tables. Admins read conversation content only through
--    admin_report_details: at most 5 messages either side of a REPORTED message, in
--    that report's conversation; message text and type only, never attachment paths.
--  * Lock order: support_requests row -> reports rows (by id). Dismiss locks one report.
--    A report is decided once: a second or concurrent decision raises
--    report_already_decided. The decided_by admin UUID is never returned (label only).
begin;
set local lock_timeout = '10s';

-- 0. Prerequisites ----------------------------------------------------------------
do $$ declare fp text; begin
 if to_regclass('public.reports') is null
    or not exists(select 1 from information_schema.columns where table_schema='public'
      and table_name='reports' and column_name='message_body') then
  raise exception 'Apply the revised 20261105_message_reports.sql (with message snapshots) first';
 end if;
 if to_regprocedure('public.maak_admin_label(uuid)') is null
    or to_regprocedure('public.trim_maak_reason(text)') is null
    or to_regprocedure('public.guard_maak_blocked_actor()') is null then
  raise exception 'Apply 20261021_account_blocking.sql and 20261022_account_moderation_visibility.sql first';
 end if;
 if (select count(*) from information_schema.columns where table_schema='public'
      and table_name='support_requests' and column_name in ('restricted_at','restricted_by','restriction_reason')) <> 3 then
  raise exception 'support_requests restriction columns are missing (production conversation restriction feature)';
 end if;
 if not exists(select 1 from information_schema.columns where table_schema='public'
      and table_name='messages' and column_name='deleted_at') then
  raise exception 'Apply 20261105030000_message_deletion_video.sql first';
 end if;
 select md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g'))) into fp
 from pg_proc p where p.oid=to_regprocedure('public.admin_restrict_conversation(uuid,text)');
 if fp is null then
  raise exception 'admin_restrict_conversation(uuid,text) is missing (production conversation restriction feature)';
 end if;
 if fp <> 'e35f98d16de40df5da9220db57732216' then
  raise exception 'admin_restrict_conversation() has an unexpected definition (%); stop and review', fp;
 end if;
end $$;

-- 1. Status value and the private decision record --------------------------------------
-- Smallest extension of Razan's model: one new outcome. 'reviewed' stays valid but no
-- RPC sets it; only 'open' reports can be decided. No column is added to reports:
-- reports_read_own lets a reporter read every column of their own rows, so the deciding
-- admin and the internal note live in report_decisions, which no client can read.
-- The reporter can still see their report's status.
alter table public.reports drop constraint if exists reports_status_check;
alter table public.reports add constraint reports_status_check
 check (status in ('open','reviewed','dismissed','conversation_ended'));
create index if not exists reports_reported_user on public.reports(reported_user_id, created_at desc);

-- One immutable row per decided report. Plain ids, no foreign keys (like reports and
-- account_moderation_events), so history outlives accounts and Razan's rollback still works.
create table if not exists public.report_decisions (
 report_id uuid primary key,
 outcome text not null check (outcome in ('dismissed','conversation_ended')),
 note text not null check (char_length(note) between 1 and 500),
 decided_by uuid not null,
 decided_at timestamptz not null default now()
);
alter table public.report_decisions enable row level security;
revoke all on public.report_decisions from public, anon, authenticated;

-- 2. Evidence is immutable; a decision is final ---------------------------------------
-- Applies to every role (also SECURITY DEFINER RPCs and the SQL Editor), like the
-- moderation history. DROP TABLE (Razan's rollback) is not affected.
-- reports: evidence never changes; status changes once, from open, to the outcome
-- already recorded in report_decisions. Rows are never deleted.
create or replace function public.guard_maak_report_change() returns trigger
language plpgsql set search_path=public,pg_temp as $$
begin
 if TG_OP <> 'UPDATE' then raise exception 'report_history_immutable'; end if;
 if (new.id, new.message_id, new.request_id, new.reporter_id, new.reported_user_id, new.reason,
     new.description, new.message_body, new.message_type, new.attachment_path, new.message_sent_at,
     new.created_at)
    is distinct from
    (old.id, old.message_id, old.request_id, old.reporter_id, old.reported_user_id, old.reason,
     old.description, old.message_body, old.message_type, old.attachment_path, old.message_sent_at,
     old.created_at) then
  raise exception 'report_evidence_immutable';
 end if;
 if new.status is distinct from old.status then
  if old.status <> 'open' then raise exception 'report_already_decided'; end if;
  if not exists(select 1 from report_decisions d where d.report_id = new.id and d.outcome = new.status) then
   raise exception 'report_decision_missing';
  end if;
 end if;
 return new;
end; $$;
drop trigger if exists maak_report_guard on public.reports;
create trigger maak_report_guard before update or delete on public.reports
 for each row execute function public.guard_maak_report_change();
drop trigger if exists maak_report_no_truncate on public.reports;
create trigger maak_report_no_truncate before truncate on public.reports
 for each statement execute function public.guard_maak_report_change();

-- report_decisions: insert once, for an existing open report; never updated or deleted.
create or replace function public.guard_maak_report_decision() returns trigger
language plpgsql set search_path=public,pg_temp as $$
declare current_status text;
begin
 if TG_OP <> 'INSERT' then raise exception 'report_history_immutable'; end if;
 select status into current_status from reports where id = new.report_id;
 if not found then raise exception 'report_not_found'; end if;
 if current_status <> 'open' then raise exception 'report_already_decided'; end if;
 return new;
end; $$;
drop trigger if exists maak_report_decision_guard on public.report_decisions;
create trigger maak_report_decision_guard before insert or update or delete on public.report_decisions
 for each row execute function public.guard_maak_report_decision();
drop trigger if exists maak_report_decision_no_truncate on public.report_decisions;
create trigger maak_report_decision_no_truncate before truncate on public.report_decisions
 for each statement execute function public.guard_maak_report_decision();

-- 3. Internal: a member's display card (never an email) -------------------------------
create or replace function public.maak_report_member(p_user_id uuid) returns jsonb
language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object(
  'user_id', p_user_id,
  'account_exists', p.id is not null,
  'name', case when p.id is null then null else coalesce(
    nullif(trim(p.full_name), ''),
    case when nullif(trim(p.username), '') is not null
          and trim(p.username) !~ '^user_[0-9a-f]{6,}$' then trim(p.username) end,
    'Ma''ak member') end,
  'role', p.role,
  'is_blocked', exists(select 1 from account_blocks b where b.user_id = p_user_id))
 from (select 1) one left join profiles p on p.id = p_user_id;
$$;

-- Internal: one report as returned to the admin list and detail screens.
create or replace function public.maak_report_card(r public.reports) returns jsonb
language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object(
  'report_id', r.id, 'status', r.status, 'reason', r.reason, 'description', r.description,
  'created_at', r.created_at, 'request_id', r.request_id, 'message_id', r.message_id,
  'message_type', r.message_type, 'message_preview', left(r.message_body, 160),
  'message_sent_at', r.message_sent_at,
  'reporter', maak_report_member(r.reporter_id), 'reported', maak_report_member(r.reported_user_id),
  'decided_at', d.decided_at, 'decision_note', d.note,
  'decided_by_name', case when d.report_id is null then null else maak_admin_label(d.decided_by) end,
  'decided_by_is_me', coalesce(d.decided_by = auth.uid(), false),
  'conversation_open_reports', (select count(*) from reports x where x.request_id = r.request_id and x.status = 'open'),
  'conversation_restricted', exists(select 1 from support_requests s where s.id = r.request_id and s.restricted_at is not null))
 from (select 1) one left join report_decisions d on d.report_id = r.id;
$$;

-- 4. US1: list reports, optionally by status ------------------------------------------
create or replace function public.admin_list_reports(p_status text default null) returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if p_status is not null and p_status not in ('open','reviewed','dismissed','conversation_ended') then
  raise exception 'invalid_report_status';
 end if;
 return query select maak_report_card(r) from reports r
  where p_status is null or r.status = p_status
  order by r.created_at desc, r.id;
end; $$;

-- 5. US2 + US5: one report with its evidence, narrow context and decision -------------
create or replace function public.admin_report_details(p_report_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare r public.reports; s public.support_requests; m public.messages; pos bigint; ctx jsonb; others jsonb;
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 select * into r from reports where id = p_report_id;
 if not found then raise exception 'report_not_found'; end if;
 select * into s from support_requests where id = r.request_id;
 select * into m from messages where id = r.message_id;
 -- Context: the reported message and up to 5 messages before and after it, from this
 -- conversation only. Text and type only; deleted messages keep their placeholder text.
 if m.id is not null then
  with ordered as (
   select x.*, row_number() over (order by x.created_at, x.id) as n
   from messages x where x.request_id = r.request_id)
  select n into pos from ordered where id = r.message_id;
  with ordered as (
   select x.*, row_number() over (order by x.created_at, x.id) as n
   from messages x where x.request_id = r.request_id)
  select coalesce(jsonb_agg(jsonb_build_object(
    'message_id', o.id, 'body', o.body, 'message_type', o.message_type, 'created_at', o.created_at,
    'deleted', o.deleted_at is not null, 'is_reported', o.id = r.message_id,
    'sender', case when o.sender_id = r.reported_user_id then 'reported'
                   when o.sender_id = r.reporter_id then 'reporter' else 'other' end)
    order by o.n), '[]'::jsonb)
  into ctx from ordered o where o.n between pos - 5 and pos + 5;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'report_id', x.id, 'reason', x.reason, 'status', x.status, 'created_at', x.created_at,
   'same_message', x.message_id = r.message_id,
   'reporter_name', maak_report_member(x.reporter_id)->>'name') order by x.created_at desc), '[]'::jsonb)
 into others from reports x where x.request_id = r.request_id and x.id <> r.id;
 return maak_report_card(r) || jsonb_build_object(
  'message_body', r.message_body,
  'attachment_present', r.attachment_path is not null,
  'message_now', jsonb_build_object('exists', m.id is not null, 'deleted', m.deleted_at is not null,
    'deleted_at', m.deleted_at),
  'conversation', jsonb_build_object(
    'exists', s.id is not null, 'status', s.status, 'created_at', s.created_at, 'ended_at', s.ended_at,
    'restricted_at', s.restricted_at, 'restriction_reason', s.restriction_reason,
    'restricted_by_name', case when s.restricted_at is null then null else maak_admin_label(s.restricted_by) end,
    'restricted_by_is_me', coalesce(s.restricted_by = auth.uid(), false),
    'help_seeker', case when s.id is null then null else maak_report_member(s.seeker_id) end,
    'volunteer', case when s.id is null then null else maak_report_member(s.volunteer_id) end),
  'context', coalesce(ctx, '[]'::jsonb),
  'other_reports', others);
end; $$;

-- 6. US3: dismiss one open report ----------------------------------------------------
create or replace function public.admin_dismiss_report(p_report_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid := auth.uid(); clean text := trim_maak_reason(p_note); current_status text; v_at timestamptz;
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if clean is null or char_length(clean) > 500 then raise exception 'invalid_report_decision_note'; end if;
 select status into current_status from reports where id = p_report_id for update;
 if not found then raise exception 'report_not_found'; end if;
 if current_status <> 'open' then raise exception 'report_already_decided'; end if;
 insert into report_decisions(report_id, outcome, note, decided_by)
  values (p_report_id, 'dismissed', clean, me) returning decided_at into v_at;
 update reports set status = 'dismissed' where id = p_report_id;
 return jsonb_build_object('report_id', p_report_id, 'status', 'dismissed', 'decided_at', v_at);
end; $$;

-- 7. US4: end (restrict) the reported conversation ----------------------------------------
-- Resolves every open report on the same conversation as 'conversation_ended' with this
-- decision. The reason is shown to both participants by admin_restrict_conversation.
create or replace function public.admin_end_reported_conversation(p_report_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid := auth.uid(); clean text := trim_maak_reason(p_reason); v_request uuid;
 v_status text; v_restricted timestamptz; current_status text; resolved int; v_at timestamptz;
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if clean is null or char_length(clean) > 500 then raise exception 'invalid_report_decision_note'; end if;
 select request_id into v_request from reports where id = p_report_id;
 if not found then raise exception 'report_not_found'; end if;
 select status, restricted_at into v_status, v_restricted from support_requests where id = v_request for update;
 if not found then raise exception 'conversation_unavailable'; end if;
 perform 1 from reports where request_id = v_request and status = 'open' order by id for update;
 select status into current_status from reports where id = p_report_id;
 if current_status <> 'open' then raise exception 'report_already_decided'; end if;
 if v_restricted is not null then raise exception 'conversation_already_restricted'; end if;
 if v_status <> 'accepted' then raise exception 'conversation_unavailable'; end if;
 perform admin_restrict_conversation(v_request, clean);
 v_at := now();
 insert into report_decisions(report_id, outcome, note, decided_by, decided_at)
  select id, 'conversation_ended', clean, me, v_at from reports where request_id = v_request and status = 'open';
 update reports set status = 'conversation_ended' where request_id = v_request and status = 'open';
 get diagnostics resolved = row_count;
 return jsonb_build_object('report_id', p_report_id, 'request_id', v_request, 'status', 'conversation_ended',
  'resolved_reports', resolved, 'decided_at', v_at);
end; $$;

-- 8. Privileges -------------------------------------------------------------------------
revoke all on function public.guard_maak_report_change(), public.guard_maak_report_decision(),
 public.maak_report_member(uuid),
 public.maak_report_card(public.reports) from public, anon, authenticated;
revoke all on function public.admin_list_reports(text), public.admin_report_details(uuid),
 public.admin_dismiss_report(uuid, text), public.admin_end_reported_conversation(uuid, text) from public, anon;
grant execute on function public.admin_list_reports(text), public.admin_report_details(uuid),
 public.admin_dismiss_report(uuid, text), public.admin_end_reported_conversation(uuid, text) to authenticated;

notify pgrst, 'reload schema';
commit;
