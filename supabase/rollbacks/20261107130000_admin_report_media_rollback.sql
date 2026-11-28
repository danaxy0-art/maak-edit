-- Rollback for 20261107130000_admin_report_media.sql. Removes ONLY what it added: the
-- Admin Storage read policy and its four functions. Participant policies, the bucket,
-- files, reports and messages are not touched. Admins return to the placeholders.
begin;
set local lock_timeout = '10s';
drop policy if exists maak_chat_media_admin_report_read on storage.objects;
drop function if exists public.admin_report_media(uuid);
drop function if exists public.maak_report_media_item(text, text, integer, boolean);
drop function if exists public.can_admin_view_report_media(text);
drop function if exists public.maak_report_media_mime(text);
notify pgrst, 'reload schema';
commit;
