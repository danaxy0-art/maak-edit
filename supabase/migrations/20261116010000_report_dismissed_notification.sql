-- Apply after 20261106100000_admin_report_management.sql and
-- 20261106000000_push_notifications.sql. Repeatable.
--
-- When an administrator dismisses a report, the member who filed it gets a
-- notification (in-app list, banner and push, kind 'report', reference_id = the
-- report). The admin's decision note is internal and is never included.
--
-- An AFTER UPDATE trigger on public.reports fires on the status change to
-- 'dismissed', so it works with any version of admin_dismiss_report. A decision
-- is final (guard_maak_report_change), so each report notifies at most once.
begin;

create or replace function public.notify_maak_report_dismissed() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.status='dismissed' and old.status is distinct from 'dismissed' and new.reporter_id is not null then
  insert into notifications(user_id,title,body,kind,reference_id) values(
   new.reporter_id,
   'Your report was reviewed',
   'Thank you for reporting. An administrator reviewed the message you reported and dismissed the report.',
   'report', new.id);
 end if;
 return new;
end; $$;
drop trigger if exists maak_report_dismissed_notification on public.reports;
create trigger maak_report_dismissed_notification after update of status on public.reports
 for each row execute function public.notify_maak_report_dismissed();
revoke all on function public.notify_maak_report_dismissed() from public,anon,authenticated;

notify pgrst,'reload schema';
commit;
