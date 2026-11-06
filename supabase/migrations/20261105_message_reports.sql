-- ADDED: message reports (Report a message / Select a reason / Optional description).
-- NOT YET APPLIED anywhere. Run once in the Supabase SQL Editor after the team agrees.
-- Idempotent. Adds a new table and one RPC; changes no existing data.
begin;
set local lock_timeout = '10s';

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  request_id uuid not null references public.support_requests(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_user_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (reason in
    ('inappropriate_language','unwanted_medical_advice','harassment','spam','other')),
  description text check (description is null or length(description) <= 500),
  status text not null default 'open' check (status in ('open','reviewed','dismissed')),
  created_at timestamptz not null default now(),
  unique (message_id, reporter_id)
);
create index if not exists reports_status_date on public.reports(status, created_at desc);

alter table public.reports enable row level security;
drop policy if exists reports_read_own on public.reports;
drop policy if exists reports_admin_read on public.reports;
create policy reports_read_own on public.reports for select to authenticated using (reporter_id = auth.uid());
create policy reports_admin_read on public.reports for select to authenticated using (is_maak_admin());
revoke all on public.reports from anon, authenticated;
grant select on public.reports to authenticated;

create or replace function public.report_maak_message(
  p_message_id uuid, p_reason text, p_description text default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_request uuid; v_sender uuid; v_desc text := nullif(trim(coalesce(p_description, '')), '');
begin
  if auth.uid() is null then raise exception 'not_allowed'; end if;
  if p_reason is null or p_reason not in
    ('inappropriate_language','unwanted_medical_advice','harassment','spam','other')
    then raise exception 'invalid_report_reason'; end if;
  if v_desc is not null and length(v_desc) > 500 then raise exception 'invalid_report_description'; end if;
  select m.request_id, m.sender_id into v_request, v_sender
    from messages m join support_requests r on r.id = m.request_id
    where m.id = p_message_id and (r.seeker_id = auth.uid() or r.volunteer_id = auth.uid());
  if not found then raise exception 'not_allowed'; end if;
  if v_sender = auth.uid() then raise exception 'cannot_report_own_message'; end if;
  begin
    insert into reports(message_id, request_id, reporter_id, reported_user_id, reason, description)
      values (p_message_id, v_request, auth.uid(), v_sender, p_reason, v_desc);
  exception when unique_violation then raise exception 'already_reported';
  end;
end; $$;
revoke all on function public.report_maak_message(uuid, text, text) from public, anon;
grant execute on function public.report_maak_message(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
commit;