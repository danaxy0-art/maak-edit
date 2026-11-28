-- Requires 20261105020000_chat_media_ai_consent.sql. No whole-chat deletion.
begin;
alter table public.messages add column if not exists deleted_at timestamptz;
alter table public.messages add column if not exists deleted_by uuid references public.profiles(id) on delete set null;
create table if not exists public.chat_message_hides (
 user_id uuid not null references public.profiles(id) on delete cascade,
 message_id uuid not null references public.messages(id) on delete cascade,
 hidden_at timestamptz not null default now(), primary key(user_id,message_id)
);
alter table public.chat_message_hides enable row level security;
revoke all on public.chat_message_hides from public,anon,authenticated;
grant select on public.chat_message_hides to authenticated;
drop policy if exists maak_message_hides_self on public.chat_message_hides;
create policy maak_message_hides_self on public.chat_message_hides for select to authenticated using(user_id=auth.uid() and public.is_maak_active());
-- Keeps old media inaccessible to new signed URLs after deletion for everyone.
create table if not exists public.chat_media_revocations(path text primary key,revoked_at timestamptz not null default now());
alter table public.chat_media_revocations enable row level security;
revoke all on public.chat_media_revocations from public,anon,authenticated;

create or replace function public.my_maak_chat_messages(p_request_id uuid) returns setof public.messages
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null or not public.is_maak_active() or not exists(select 1 from support_requests where id=p_request_id and auth.uid() in (seeker_id,volunteer_id)) then raise exception 'not_allowed'; end if;
 return query select (case when h.message_id is not null then
  jsonb_populate_record(m,jsonb_build_object('body','You deleted this message.','message_type','text',
   'attachment_path',null,'attachment_mime',null,'attachment_bytes',null,'duration_ms',null,
   'deleted_at',coalesce(m.deleted_at,h.hidden_at),'deleted_by',auth.uid()))
  else m end).*
 from messages m left join chat_message_hides h on h.message_id=m.id and h.user_id=auth.uid()
 where m.request_id=p_request_id order by m.created_at,m.id;
end; $$;
-- Apply the same personal hiding rules to direct queries/Realtime.
drop policy if exists messages_read on public.messages;
create policy messages_read on public.messages for select to authenticated
 using(public.is_maak_active() and exists(select 1 from public.support_requests r where r.id=messages.request_id and auth.uid() in (r.seeker_id,r.volunteer_id))
 and not exists(select 1 from public.chat_message_hides h where h.user_id=auth.uid() and h.message_id=messages.id));

create or replace function public.delete_maak_message(p_message_id uuid,p_for_everyone boolean default false) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare m public.messages; me uuid:=auth.uid();
begin
 if me is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
 select * into m from messages where id=p_message_id for update;
 if not found or not exists(select 1 from support_requests r where r.id=m.request_id and me in (r.seeker_id,r.volunteer_id)) then raise exception 'message_unavailable'; end if;
 if coalesce(p_for_everyone,false) then
  -- A recipient can only hide a received message from their own account.
  if m.sender_id<>me then raise exception 'sender_only'; end if;
  if m.deleted_at is not null then return; end if;
  if m.attachment_path is not null then
   insert into chat_media_revocations(path) values(m.attachment_path) on conflict do nothing;
  end if;
  update messages set body='This message was deleted.',message_type='text',attachment_path=null,
   attachment_mime=null,attachment_bytes=null,duration_ms=null,deleted_at=clock_timestamp(),deleted_by=me where id=m.id;
  delete from public.message_reactions where message_id=m.id;
 else
  insert into chat_message_hides(user_id,message_id) values(me,m.id) on conflict do nothing;
 end if;
 -- Only dismiss this account's notices when no visible unread message remains.
 update public.notifications n set is_read=true where n.kind='message' and n.reference_id=m.request_id
 and (n.user_id=me or (coalesce(p_for_everyone,false) and exists(select 1 from support_requests r where r.id=m.request_id and n.user_id in (r.seeker_id,r.volunteer_id)))) and not n.is_read and not exists(
  select 1 from messages x where x.request_id=m.request_id and x.sender_id<>n.user_id and x.read_at is null and x.deleted_at is null
  and x.created_at<=n.created_at and not exists(select 1 from chat_message_hides h where h.user_id=n.user_id and h.message_id=x.id));
end; $$;
revoke all on function public.my_maak_chat_messages(uuid),public.delete_maak_message(uuid,boolean) from public,anon;
grant execute on function public.my_maak_chat_messages(uuid),public.delete_maak_message(uuid,boolean) to authenticated;
-- No direct client UPDATE/DELETE permission on messages; mutations use the RPC.
revoke update,delete on public.messages from authenticated,anon;

create or replace function public.my_maak_unread_message_count() returns bigint
language sql stable security definer set search_path=public,pg_temp as $$
 select count(*) from messages m join support_requests r on r.id=m.request_id
 where auth.uid() is not null and public.is_maak_active() and auth.uid() in (r.seeker_id,r.volunteer_id)
 and m.sender_id<>auth.uid() and m.read_at is null and m.deleted_at is null
 and not exists(select 1 from chat_message_hides h where h.user_id=auth.uid() and h.message_id=m.id);
$$;
-- Same original request data/authorization; previews respect each reader's hidden messages.
create or replace function public.my_support_requests() returns setof jsonb
language sql stable security definer set search_path=public,pg_temp as $$
 select to_jsonb(r)||jsonb_build_object('contact_name',p.full_name,'condition',h.chronic_condition,
 'description',h.description,'last_message',(select case when exists(select 1 from chat_message_hides x where x.user_id=auth.uid() and x.message_id=m.id)
 then 'You deleted this message.' else m.body end from messages m where m.request_id=r.id
 order by m.created_at desc,m.id desc limit 1),
 'contact_available',not exists(select 1 from account_blocks b where b.user_id=p.id))
 from support_requests r join profiles p on p.id=case when r.seeker_id=auth.uid() then r.volunteer_id else r.seeker_id end
 join help_seeker_profiles h on h.user_id=r.seeker_id
 where auth.uid() in (r.seeker_id,r.volunteer_id) and public.is_maak_active() order by r.created_at desc;
$$;

-- Reads: live visible message, or the sender's own uncommitted upload for retry.
-- Writes: original chat authorization, including ended/restricted/blocked checks.
create or replace function public.can_access_maak_media(p_path text,p_write boolean default false)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select auth.uid() is not null and public.is_maak_active() and array_length(string_to_array(p_path,'/'),1)=3
 and not exists(select 1 from chat_media_revocations v where v.path=p_path)
 and exists(select 1 from support_requests r where r.id::text=split_part(p_path,'/',1) and auth.uid() in (r.seeker_id,r.volunteer_id)
 and case when p_write then split_part(p_path,'/',2)=auth.uid()::text and r.ended_at is null and public.can_send_maak_message(r.id)
 else exists(select 1 from messages m where m.attachment_path=p_path and m.deleted_at is null
  and not exists(select 1 from chat_message_hides h where h.user_id=auth.uid() and h.message_id=m.id))
  or (split_part(p_path,'/',2)=auth.uid()::text and not exists(select 1 from messages m where m.attachment_path=p_path)) end);
$$;
-- Existing reaction RPC locks messages, so this check serializes with deletion.
create or replace function public.guard_maak_deleted_reaction() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform 1 from messages m where m.id=new.message_id and m.deleted_at is null
 and not exists(select 1 from chat_message_hides h where h.user_id=auth.uid() and h.message_id=m.id) for update;
 if not found then raise exception 'message_unavailable'; end if;
 return new;
end; $$;
drop trigger if exists maak_deleted_reaction_guard on public.message_reactions;
create trigger maak_deleted_reaction_guard before insert or update on public.message_reactions for each row execute function public.guard_maak_deleted_reaction();
revoke all on function public.guard_maak_deleted_reaction() from public,anon,authenticated;

-- Add MP4 videos without changing existing image/voice limits.
alter table public.messages drop constraint if exists maak_message_media_shape;
alter table public.messages add constraint maak_message_media_shape check (
 (message_type='text' and attachment_path is null and attachment_mime is null and attachment_bytes is null and duration_ms is null)
 or (message_type='image' and attachment_path is not null and attachment_mime is not null and attachment_mime in ('image/png','image/jpeg','image/webp') and attachment_bytes is not null and attachment_bytes between 1 and 10485760 and duration_ms is null)
 or (message_type='voice' and attachment_path is not null and attachment_mime='audio/wav' and attachment_mime is not null and attachment_bytes is not null and attachment_bytes between 16044 and 1920044 and duration_ms is not null and duration_ms between 500 and 60000)
 or (message_type='video' and attachment_path is not null and attachment_mime is not null and attachment_mime='video/mp4' and attachment_bytes is not null and attachment_bytes between 12 and 10485760 and duration_ms is null)
);
update storage.buckets set allowed_mime_types=array['image/png','image/jpeg','image/webp','audio/wav','video/mp4'] where id='chat-media';
create or replace function public.validate_maak_chat_attachment() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare meta jsonb; suffix text;
begin
 if new.deleted_at is not null or new.deleted_by is not null then raise exception 'invalid_message_state'; end if;
 if new.message_type='text' then return new; end if;
 if new.sender_id<>auth.uid() or not public.can_access_maak_media(new.attachment_path,true) then raise exception 'not_allowed'; end if;
 suffix:=case new.attachment_mime when 'image/png' then 'png' when 'image/jpeg' then 'jpg' when 'image/webp' then 'webp' when 'audio/wav' then 'wav' when 'video/mp4' then 'mp4' else '' end;
 if new.attachment_path<>new.request_id::text||'/'||new.sender_id::text||'/'||new.id::text||'.'||suffix then raise exception 'invalid_attachment'; end if;
 select metadata into meta from storage.objects where bucket_id='chat-media' and name=new.attachment_path;
 if meta is null or (meta->>'size')::bigint is distinct from new.attachment_bytes::bigint or meta->>'mimetype' is distinct from new.attachment_mime then raise exception 'attachment_not_uploaded'; end if;
 if new.message_type='voice' and abs(new.attachment_bytes-44-new.duration_ms*32)>32 then raise exception 'invalid_voice_duration'; end if;
 return new;
end; $$;
notify pgrst,'reload schema';
commit;
