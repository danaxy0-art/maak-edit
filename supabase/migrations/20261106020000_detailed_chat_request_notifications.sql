-- Apply after 20261106000000_push_notifications.sql. Repeatable.
--
-- Fills in names and message text on chat and request notifications, for both
-- the in-app list and the push:
--   chat ............ title = sender's name, body = the message text; media shows
--                     an icon plus its caption ("📷 Look at this"), or
--                     "📷 Photo" / "🎤 Voice message" / "🎥 Video" without one
--   new request ..... "New support request from <help seeker>"     -> volunteer
--   accepted ........ "<volunteer> accepted your support request"   -> help seeker
--   declined ........ "<volunteer> declined your support request"   -> help seeker
--   canceled ........ "<help seeker> canceled their support request" -> volunteer
--
-- It does not replace notify_maak_message, request_peer_support,
-- decide_support_request or cancel_support_request (production has its own
-- versions of some of them). A BEFORE INSERT trigger on public.notifications
-- rewrites the title and body of the rows those functions insert, using the
-- request in reference_id. Rows it can't resolve keep their original text.
--
-- Deleted messages: each chat notification records which message it shows. When
-- that message is deleted for everyone, or hidden by the recipient, the stored
-- notification text is replaced. A push already delivered to a phone can't be recalled.
begin;

alter table public.notifications add column if not exists message_id uuid
 references public.messages(id) on delete set null;
create index if not exists notifications_message on public.notifications(message_id) where message_id is not null;

create or replace function public.maak_short_text(value text, max_len int) returns text
language sql immutable set search_path=public,pg_temp as $$
 select case when char_length(t)>max_len then left(t,max_len-1)||'…' else t end
 from (select regexp_replace(trim(coalesce(value,'')),'\s+',' ','g') t) s;
$$;

create or replace function public.detail_maak_notification() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare r support_requests%rowtype; seeker_name text; volunteer_name text; msg messages%rowtype; sender_name text;
begin
 if new.kind not in ('message','request') or new.reference_id is null then return new; end if;
 select * into r from support_requests where id=new.reference_id;
 if not found or new.user_id not in (r.seeker_id,r.volunteer_id) then return new; end if;

 if new.kind='message' then
  -- The message being notified is the newest one from the other participant.
  select * into msg from messages m
   where m.request_id=r.id and m.sender_id<>new.user_id and m.deleted_at is null
   order by m.created_at desc, m.id desc limit 1;
  if not found then return new; end if;
  select nullif(trim(full_name),'') into sender_name from profiles where id=msg.sender_id;
  new.message_id:=msg.id;
  new.title:=maak_short_text(coalesce(sender_name,'New message'),80);
  -- Media: an icon plus the caption, or the media type when there's no caption
  -- (media sent without one stores 'Photo' / 'Video' / 'Voice message').
  new.body:=case
   when msg.message_type in ('image','voice','video') then
    (case msg.message_type when 'image' then '📷 ' when 'voice' then '🎤 ' else '🎥 ' end)||
    case when nullif(trim(msg.body),'') is null or trim(msg.body) in ('Photo','Video','Voice message')
     then case msg.message_type when 'image' then 'Photo' when 'voice' then 'Voice message' else 'Video' end
     else maak_short_text(msg.body,198) end
   else coalesce(nullif(maak_short_text(msg.body,200),''),'New message') end;
  return new;
 end if;

 -- Requests: the wording follows the request's current status and who receives it.
 select nullif(trim(full_name),'') into seeker_name from profiles where id=r.seeker_id;
 select nullif(trim(full_name),'') into volunteer_name from profiles where id=r.volunteer_id;
 seeker_name:=maak_short_text(coalesce(seeker_name,'A help seeker'),60);
 volunteer_name:=maak_short_text(coalesce(volunteer_name,'The volunteer'),60);
 if new.user_id=r.volunteer_id and r.status='pending' then
  new.title:='New support request from '||seeker_name;
  new.body:=seeker_name||' would like to connect with you.';
 elsif new.user_id=r.seeker_id and r.status='accepted' then
  new.title:=volunteer_name||' accepted your support request';
  new.body:='You can now start a conversation with '||volunteer_name||'.';
 elsif new.user_id=r.seeker_id and r.status='declined' then
  new.title:=volunteer_name||' declined your support request';
  new.body:='You can choose another volunteer.';
 elsif new.user_id=r.volunteer_id and r.status='canceled' then
  new.title:=seeker_name||' canceled their support request';
  new.body:='The pending request was canceled.';
 end if;
 return new;
end; $$;
drop trigger if exists maak_notification_details on public.notifications;
create trigger maak_notification_details before insert on public.notifications
 for each row execute function public.detail_maak_notification();

-- Deleted for everyone: no one keeps the text in their notification list.
create or replace function public.scrub_maak_deleted_message_notice() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if TG_TABLE_NAME='messages' then
  if new.deleted_at is not null and old.deleted_at is null then
   update notifications set body='This message was deleted.' where message_id=new.id;
  end if;
  return new;
 end if;
 -- chat_message_hides: the recipient hid it from their own account only.
 update notifications set body='This message was deleted.' where message_id=new.message_id and user_id=new.user_id;
 return new;
end; $$;
drop trigger if exists maak_message_delete_scrub on public.messages;
create trigger maak_message_delete_scrub after update of deleted_at on public.messages
 for each row execute function public.scrub_maak_deleted_message_notice();
drop trigger if exists maak_message_hide_scrub on public.chat_message_hides;
create trigger maak_message_hide_scrub after insert on public.chat_message_hides
 for each row execute function public.scrub_maak_deleted_message_notice();

revoke all on function public.detail_maak_notification(),public.scrub_maak_deleted_message_notice(),
 public.maak_short_text(text,int) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
