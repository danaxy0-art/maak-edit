-- Apply to the existing Ma'ak database. Safe to run again.
begin;
alter table public.messages add column if not exists read_at timestamptz;
create index if not exists maak_unread_messages on public.messages(request_id,sender_id) where read_at is null;
create or replace function public.mark_maak_messages_read(p_request_id uuid,p_message_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or not exists(select 1 from support_requests where id=p_request_id and (seeker_id=auth.uid() or volunteer_id=auth.uid())) then raise exception 'not_allowed'; end if;
 if p_message_ids is null or cardinality(p_message_ids)>500 then raise exception 'invalid_messages'; end if;
 update messages set read_at=now() where request_id=p_request_id and id=any(p_message_ids) and sender_id<>auth.uid() and read_at is null;
 -- Acknowledges only the displayed messages; messages arriving concurrently stay unread.
 update notifications n set is_read=true where n.user_id=auth.uid() and n.kind='message' and n.reference_id=p_request_id and not n.is_read
 and not exists(select 1 from messages m where m.request_id=p_request_id and m.sender_id<>auth.uid() and m.read_at is null and m.created_at<=n.created_at);
end; $$;
revoke all on function public.mark_maak_messages_read(uuid,uuid[]) from public,anon;
grant execute on function public.mark_maak_messages_read(uuid,uuid[]) to authenticated;
-- Retain historical records; remove access to the unused booking feature.
revoke all on function public.book_support_session(uuid,timestamptz),public.my_support_sessions() from public,anon,authenticated;
create or replace function public.my_maak_unread_message_count() returns bigint
language sql stable security definer set search_path=public as $$
 select count(*) from messages m join support_requests r on r.id=m.request_id
 where auth.uid() is not null and (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid())
 and m.sender_id<>auth.uid() and m.read_at is null;
$$;
revoke all on function public.my_maak_unread_message_count() from public,anon;
grant execute on function public.my_maak_unread_message_count() to authenticated;
notify pgrst,'reload schema';
commit;
