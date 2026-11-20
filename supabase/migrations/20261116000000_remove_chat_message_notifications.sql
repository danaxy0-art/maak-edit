-- Apply after 20261106020000_detailed_chat_request_notifications.sql. Repeatable.
--
-- Chat messages no longer create notifications: no row in the in-app list, no
-- pop-up banner and no push. Unread chat badges are unaffected (they count
-- unread messages directly, not notifications).
--
--  * Drops the AFTER INSERT trigger on public.messages that inserted them.
--  * A BEFORE INSERT guard on public.notifications drops any 'message' row that
--    another version of the function (for example production's own) still
--    inserts, so nothing reaches the push trigger either.
--  * Removes the chat notifications already stored.
--
-- New-message alerts now come from the app itself, without FCM:
-- lib/backend/services/chat_alert_service.dart listens to public.messages
-- through Supabase Realtime and shows local notifications. Keep this migration
-- applied, or members would get every chat message twice.
begin;

drop trigger if exists maak_message_notification on public.messages;

create or replace function public.skip_maak_message_notification() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.kind='message' then return null; end if;
 return new;
end; $$;
drop trigger if exists maak_notification_skip_messages on public.notifications;
create trigger maak_notification_skip_messages before insert on public.notifications
 for each row execute function public.skip_maak_message_notification();
revoke all on function public.skip_maak_message_notification() from public,anon,authenticated;

delete from public.notifications where kind='message';

notify pgrst,'reload schema';
commit;
