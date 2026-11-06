-- ADDED: message reports (Report a message / Select a reason / Optional description).
-- NOT YET APPLIED anywhere. Run once in the Supabase SQL Editor after the team agrees.
-- Idempotent. Adds a new table and one RPC; changes no existing data.
--
-- Revision after team review of the Admin side:
--  * Evidence is kept: each report stores a snapshot of the message and has NO
--    cascade foreign keys (like account_moderation_events), so "delete for
--    everyone" or deleting an account cannot erase a report.
--  * A blocked account cannot file a report (RPC check + maak_blocked_actor_guard).
--  * A message that was deleted for everyone cannot be reported.
--  * Reports can be grouped per conversation (request_id index).
--  NOT decided here (team to agree): the final status list and the columns for
--  who decided / when / why, and how an Admin-ended conversation is shown.
begin;
set local lock_timeout = '10s';

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  -- Plain ids on purpose: no foreign keys, so nothing here cascades away.
  message_id uuid not null,
  request_id uuid not null,
  reporter_id uuid not null,
  reported_user_id uuid not null,
  reason text not null check (reason in
    ('inappropriate_language','unwanted_medical_advice','harassment','spam','other')),
  description text check (description is null or length(description) <= 500),
  -- Snapshot of the reported message, taken when the report is filed.
  message_body text not null,
  message_type text not null default 'text',
  attachment_path text,
  message_sent_at timestamptz not null,
  status text not null default 'open' check (status in ('open','reviewed','dismissed')),
  created_at timestamptz not null default now(),
  unique (message_id, reporter_id)
);
-- If an earlier version of this file was run, bring that table up to date.
alter table public.reports add column if not exists message_body text;
alter table public.reports add column if not exists message_type text not null default 'text';
alter table public.reports add column if not exists attachment_path text;
alter table public.reports add column if not exists message_sent_at timestamptz;
alter table public.reports drop constraint if exists reports_message_id_fkey;
alter table public.reports drop constraint if exists reports_request_id_fkey;
alter table public.reports drop constraint if exists reports_reporter_id_fkey;
alter table public.reports drop constraint if exists reports_reported_user_id_fkey;

create index if not exists reports_status_date on public.reports(status, created_at desc);
create index if not exists reports_request on public.reports(request_id, created_at desc);

alter table public.reports enable row level security;
drop policy if exists reports_read_own on public.reports;
drop policy if exists reports_admin_read on public.reports;
create policy reports_read_own on public.reports for select to authenticated using (reporter_id = auth.uid());
create policy reports_admin_read on public.reports for select to authenticated using (is_maak_admin());
revoke all on public.reports from anon, authenticated;
grant select on public.reports to authenticated;

-- A blocked account cannot write to reports, same as the other user-facing tables.
drop trigger if exists maak_blocked_actor_guard on public.reports;
create trigger maak_blocked_actor_guard before insert or update or delete on public.reports
  for each row execute function public.guard_maak_blocked_actor();

create or replace function public.report_maak_message(
  p_message_id uuid, p_reason text, p_description text default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_request uuid; v_sender uuid; v_body text; v_type text; v_path text;
  v_sent timestamptz; v_deleted timestamptz;
  v_desc text := nullif(trim(coalesce(p_description, '')), '');
begin
  if auth.uid() is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
  if p_reason is null or p_reason not in
    ('inappropriate_language','unwanted_medical_advice','harassment','spam','other')
    then raise exception 'invalid_report_reason'; end if;
  if v_desc is not null and length(v_desc) > 500 then raise exception 'invalid_report_description'; end if;
  select m.request_id, m.sender_id, m.body, m.message_type, m.attachment_path, m.created_at, m.deleted_at
    into v_request, v_sender, v_body, v_type, v_path, v_sent, v_deleted
    from messages m join support_requests r on r.id = m.request_id
    where m.id = p_message_id and (r.seeker_id = auth.uid() or r.volunteer_id = auth.uid());
  if not found then raise exception 'not_allowed'; end if;
  if v_deleted is not null then raise exception 'message_deleted'; end if;
  if v_sender = auth.uid() then raise exception 'cannot_report_own_message'; end if;
  begin
    insert into reports(message_id, request_id, reporter_id, reported_user_id, reason, description,
                        message_body, message_type, attachment_path, message_sent_at)
      values (p_message_id, v_request, auth.uid(), v_sender, p_reason, v_desc,
              v_body, v_type, v_path, v_sent);
  exception when unique_violation then raise exception 'already_reported';
  end;
end; $$;
revoke all on function public.report_maak_message(uuid, text, text) from public, anon;
grant execute on function public.report_maak_message(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
commit;
