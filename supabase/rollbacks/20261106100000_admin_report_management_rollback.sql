-- Rollback for 20261106100000_admin_report_management.sql.
-- Restores Razan's 20261105_message_reports.sql state exactly (status open/reviewed/
-- dismissed, no admin RPCs). Report rows and their snapshots are not touched.
-- Refuses to run once any report has been decided, so moderation history is never lost
-- silently: export report_decisions first and get a team decision.
-- Conversations ended through admin_end_reported_conversation STAY restricted: that state
-- belongs to the production restriction feature (support_requests.restricted_*).
begin;
set local lock_timeout = '10s';
do $$ begin
 if to_regclass('public.report_decisions') is not null
    and exists(select 1 from public.report_decisions) then
  raise exception 'report_decisions has moderation decisions; export them and get a team decision before rolling back';
 end if;
end $$;
drop function if exists public.admin_end_reported_conversation(uuid, text);
drop function if exists public.admin_dismiss_report(uuid, text);
drop function if exists public.admin_report_details(uuid);
drop function if exists public.admin_list_reports(text);
drop function if exists public.maak_report_card(public.reports);
drop function if exists public.maak_report_member(uuid);
drop trigger if exists maak_report_guard on public.reports;
drop trigger if exists maak_report_no_truncate on public.reports;
drop function if exists public.guard_maak_report_change();
drop table if exists public.report_decisions;
drop function if exists public.guard_maak_report_decision();
drop index if exists public.reports_reported_user;
alter table public.reports drop constraint if exists reports_status_check;
alter table public.reports add constraint reports_status_check
 check (status in ('open','reviewed','dismissed'));
notify pgrst, 'reload schema';
commit;
