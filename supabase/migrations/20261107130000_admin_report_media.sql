-- =====================================================================================
-- Ma'ak | Sprint 3 | Admin report media viewer
-- NOT YET APPLIED anywhere. Apply through the Supabase SQL Editor after approval,
-- never `db push`. Idempotent (safe to run twice).
-- Rollback: supabase/rollbacks/20261107130000_admin_report_media_rollback.sql
-- Verify (read-only): supabase/checks/20261107130000_admin_report_media_verify.sql
-- Independent of 20261107110000_admin_lift_restriction.sql and
-- 20261107120000_appeal_cooldown.sql (no shared objects); apply after them.
-- =====================================================================================
-- Lets an Admin view the photos, voice messages and videos of REPORTED messages in the
-- private chat-media bucket, through short-lived signed URLs created by the app.
--
--  * Reported media (the path saved in the report snapshot): readable for any report
--    status, also after the sender deleted the message for everyone (participants
--    stay blocked by chat_media_revocations in their own policy).
--  * Context media: only for an OPEN report, only live (not deleted, not revoked)
--    media within 5 messages before/after the reported message, same conversation.
--  * Nothing once the conversation no longer exists (for example account deletion),
--    even if an orphaned Storage file remains.
--  * Admin only (is_maak_admin(), which excludes blocked admins). Read only: no
--    upload, overwrite or delete rule is added for Admins.
--
-- Changes: one helper, one Admin RPC, two internal helpers, and ONE ADDITIONAL Storage
-- SELECT policy. Existing policies (maak_chat_media_read/upload/orphan_delete),
-- can_access_maak_media, the bucket, admin_report_details, reports and messages are
-- not changed. Policies are OR-ed, so participant access is exactly as before.
begin;
set local lock_timeout = '10s';

-- 0. Prerequisites -----------------------------------------------------------------
do $$ begin
 if to_regprocedure('public.admin_report_details(uuid)') is null
    or to_regprocedure('public.admin_dismiss_report(uuid,text)') is null then
  raise exception 'Apply 20261106100000_admin_report_management.sql first';
 end if;
 if not exists(select 1 from information_schema.columns where table_schema='public'
      and table_name='reports' and column_name='attachment_path') then
  raise exception 'Apply 20261105_message_reports.sql (with message snapshots) first';
 end if;
 if to_regprocedure('public.can_access_maak_media(text,boolean)') is null
    or to_regclass('public.chat_media_revocations') is null then
  raise exception 'Apply 20261105030000_message_deletion_video.sql first';
 end if;
 if to_regprocedure('public.is_maak_admin()') is null then
  raise exception 'Apply 20261021_account_blocking.sql first';
 end if;
 if not exists(select 1 from storage.buckets where id='chat-media' and public = false) then
  raise exception 'The chat-media bucket must exist and be private';
 end if;
end $$;

-- 1. Internal: MIME type from the file extension (the app only uploads these). ------
create or replace function public.maak_report_media_mime(p_path text) returns text
language sql immutable set search_path=public,pg_temp as $$
 select case lower(substring(p_path from '\.([A-Za-z0-9]+)$'))
  when 'png' then 'image/png' when 'jpg' then 'image/jpeg' when 'jpeg' then 'image/jpeg'
  when 'webp' then 'image/webp' when 'wav' then 'audio/wav' when 'mp4' then 'video/mp4' end;
$$;

-- 2. The single authorization rule, used by the Storage policy and by the RPC. --------
create or replace function public.can_admin_view_report_media(p_path text) returns boolean
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_req uuid;
begin
 if p_path is null or not public.is_maak_admin() then return false; end if;
 -- request UUID / sender UUID / message UUID.extension, as written by the chat.
 if p_path !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[a-z0-9]+$'
 then return false; end if;
 v_req := split_part(p_path, '/', 1)::uuid;
 -- The conversation must still exist (account deletion removes it).
 if not exists(select 1 from support_requests s where s.id = v_req) then return false; end if;
 -- Reported media: the server-written snapshot path, for any report status.
 if exists(select 1 from reports r where r.request_id = v_req and r.attachment_path = p_path
     and split_part(p_path, '/', 2) = r.reported_user_id::text
     and split_part(p_path, '/', 3) like r.message_id::text || '.%') then
  return true;
 end if;
 -- Context media: OPEN reports only; live media within 5 messages either side.
 if exists(select 1 from chat_media_revocations v where v.path = p_path) then return false; end if;
 return exists(
  with o as (
   select x.id, x.attachment_path, x.deleted_at, row_number() over (order by x.created_at, x.id) as n
   from messages x where x.request_id = v_req)
  select 1 from reports r
  join o rp on rp.id = r.message_id
  join o c on c.attachment_path = p_path and c.deleted_at is null
  where r.request_id = v_req and r.status = 'open' and c.n between rp.n - 5 and rp.n + 5);
end; $$;

-- 3. Internal: one media item for the RPC. The path is returned only when allowed. ---
create or replace function public.maak_report_media_item(
  p_type text, p_path text, p_duration_ms integer, p_conversation_exists boolean
) returns jsonb language sql stable set search_path=public,pg_temp as $$
 select jsonb_build_object(
  'message_type', p_type, 'mime', t.mime, 'duration_ms', p_duration_ms,
  'available', t.ok, 'path', case when t.ok then p_path end,
  'unavailable_reason', case when t.ok then null
    when not p_conversation_exists then 'conversation_deleted'
    when p_path is null then 'missing'
    when not t.supported then 'unsupported'
    when not t.stored then 'file_missing'
    else 'not_allowed' end)
 from (select s.*, s.supported and s.stored and p_conversation_exists
                   and public.can_admin_view_report_media(p_path) as ok
       from (select m.mime,
               coalesce(case p_type when 'image' then m.mime like 'image/%'
                 when 'voice' then m.mime = 'audio/wav' when 'video' then m.mime = 'video/mp4' end, false) as supported,
               p_path is not null and exists(select 1 from storage.objects o
                 where o.bucket_id = 'chat-media' and o.name = p_path) as stored
             from (select public.maak_report_media_mime(p_path) as mime) m) s) t;
$$;

-- 4. Admin RPC: the media of one report (reported item + open-report context). ------
create or replace function public.admin_report_media(p_report_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare r public.reports; m public.messages; conv boolean; pos bigint;
        reported jsonb; ctx jsonb := '[]'::jsonb;
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 select * into r from reports where id = p_report_id;
 if not found then raise exception 'report_not_found'; end if;
 conv := exists(select 1 from support_requests where id = r.request_id);
 if r.message_type in ('image', 'voice', 'video') or r.attachment_path is not null then
  select * into m from messages where id = r.message_id;
  reported := maak_report_media_item(r.message_type, r.attachment_path,
                case when m.deleted_at is null then m.duration_ms end, conv)
              || jsonb_build_object('message_id', r.message_id,
                   'deleted_for_everyone', coalesce(m.deleted_at is not null, false));
 end if;
 if conv and r.status = 'open' then
  with o as (select x.id, row_number() over (order by x.created_at, x.id) as n
             from messages x where x.request_id = r.request_id)
  select n into pos from o where id = r.message_id;
  if pos is not null then
   with o as (select x.*, row_number() over (order by x.created_at, x.id) as n
              from messages x where x.request_id = r.request_id)
   select coalesce(jsonb_agg(maak_report_media_item(o.message_type, o.attachment_path, o.duration_ms, true)
            || jsonb_build_object('message_id', o.id) order by o.n), '[]'::jsonb)
   into ctx from o
   where o.n between pos - 5 and pos + 5 and o.id <> r.message_id
     and o.deleted_at is null and o.attachment_path is not null;
  end if;
 end if;
 return jsonb_build_object('report_id', r.id, 'conversation_exists', conv,
  'context_media_allowed', conv and r.status = 'open', 'reported', reported, 'context', ctx);
end; $$;

revoke all on function public.maak_report_media_mime(text),
  public.maak_report_media_item(text, text, integer, boolean) from public, anon, authenticated;
-- The Storage policy runs as the signed-in user, so authenticated needs EXECUTE; the
-- function returns false for everyone who is not an active Admin.
revoke all on function public.can_admin_view_report_media(text), public.admin_report_media(uuid) from public, anon;
grant execute on function public.can_admin_view_report_media(text), public.admin_report_media(uuid) to authenticated;

-- 5. Additional, read-only Storage policy for Admins (signed URLs need SELECT). -------
drop policy if exists maak_chat_media_admin_report_read on storage.objects;
create policy maak_chat_media_admin_report_read on storage.objects for select to authenticated
 using (bucket_id = 'chat-media' and public.can_admin_view_report_media(name));

notify pgrst, 'reload schema';
commit;
