-- Apply after 20261105010000_chat_reopen.sql and 20261106000000_push_notifications.sql.
-- Repeatable.
--
-- Puts the other participant's name in chat reopen notifications, for both the
-- in-app list and the push:
--   reopen request ... title stays "Chat reopen request" (the app shows the
--                      Accept/Decline buttons on that title),
--                      body  "<name> would like to reopen your conversation."
--   accepted ......... "<name> accepted your reopen request"
--                      "You can continue chatting."
--   declined ......... "<name> declined your reopen request"
--                      "The conversation remains closed."
--
-- It does not replace request_maak_chat_reopen or decide_maak_chat_reopen. A
-- BEFORE INSERT trigger on public.notifications rewrites the rows they insert,
-- using the request in reference_id. Rows it can't resolve keep their text.
begin;

create or replace function public.name_maak_chat_reopen_notification() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare r support_requests%rowtype; other_id uuid; other_name text; ev text;
begin
 if new.kind<>'chat_reopen' or new.reference_id is null then return new; end if;
 select * into r from support_requests where id=new.reference_id;
 if not found or new.user_id not in (r.seeker_id,r.volunteer_id) then return new; end if;
 other_id:=case when new.user_id=r.seeker_id then r.volunteer_id else r.seeker_id end;
 select nullif(trim(full_name),'') into other_name from profiles where id=other_id;
 if other_name is null then return new; end if;
 if char_length(other_name)>60 then other_name:=left(other_name,59)||'…'; end if;

 -- Newer databases store the event; older ones only have the original title.
 ev:=coalesce(to_jsonb(new)->>'event', case new.title
   when 'Chat reopen request' then 'chat_reopen_requested'
   when 'Conversation reopened' then 'chat_reopen_accepted'
   when 'Reopen request declined' then 'chat_reopen_declined' end);

 if ev='chat_reopen_requested' then
  new.title:='Chat reopen request';
  new.body:=other_name||' would like to reopen your conversation.';
 elsif ev='chat_reopen_accepted' then
  new.title:=other_name||' accepted your reopen request';
  new.body:='You can continue chatting.';
 elsif ev='chat_reopen_declined' then
  new.title:=other_name||' declined your reopen request';
  new.body:='The conversation remains closed.';
 end if;
 return new;
end; $$;

drop trigger if exists maak_chat_reopen_names on public.notifications;
create trigger maak_chat_reopen_names before insert on public.notifications
 for each row execute function public.name_maak_chat_reopen_notification();

revoke all on function public.name_maak_chat_reopen_notification() from public,anon,authenticated;
commit;
