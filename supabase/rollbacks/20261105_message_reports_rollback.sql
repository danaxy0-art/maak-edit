-- Rollback for 20261105_message_reports.sql. Deletes all reports.
begin;
drop function if exists public.report_maak_message(uuid, text, text);
drop table if exists public.reports;
notify pgrst, 'reload schema';
commit;
