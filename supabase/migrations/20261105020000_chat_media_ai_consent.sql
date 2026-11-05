-- Apply AFTER the existing schema and migrations, including chat end/reopen.
-- Additive and repeatable. Existing text messages and matching decisions are retained.
begin;
alter table public.messages add column if not exists message_type text not null default 'text';
alter table public.messages add column if not exists attachment_path text;
alter table public.messages add column if not exists attachment_mime text;
alter table public.messages add column if not exists attachment_bytes integer;
alter table public.messages add column if not exists duration_ms integer;
alter table public.messages drop constraint if exists maak_message_media_shape;
alter table public.messages add constraint maak_message_media_shape check (
 (message_type='text' and attachment_path is null and attachment_mime is null and attachment_bytes is null and duration_ms is null)
 or (message_type='image' and attachment_mime is not null and attachment_bytes is not null and attachment_path is not null and attachment_mime in ('image/png','image/jpeg','image/webp') and attachment_bytes between 1 and 10485760 and duration_ms is null)
 or (message_type='voice' and attachment_mime is not null and attachment_bytes is not null and duration_ms is not null and attachment_path is not null and attachment_mime='audio/wav' and attachment_bytes between 16044 and 1920044 and duration_ms between 500 and 60000)
);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('chat-media','chat-media',false,10485760,array['image/png','image/jpeg','image/webp','audio/wav'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- A private object path is request UUID / sender UUID / message UUID.extension.
create or replace function public.can_access_maak_media(p_path text, p_write boolean default false)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select auth.uid() is not null and public.is_maak_active() and
 array_length(string_to_array(p_path,'/'),1)=3 and exists (
 select 1 from public.support_requests r
 where r.id::text=split_part(p_path,'/',1)
 and auth.uid() in (r.seeker_id,r.volunteer_id)
 and (not p_write or (split_part(p_path,'/',2)=auth.uid()::text
   and r.ended_at is null and public.can_send_maak_message(r.id)))
 );
$$;
revoke all on function public.can_access_maak_media(text,boolean) from public,anon;
grant execute on function public.can_access_maak_media(text,boolean) to authenticated;
drop policy if exists maak_chat_media_read on storage.objects;
create policy maak_chat_media_read on storage.objects for select to authenticated
 using(bucket_id='chat-media' and public.can_access_maak_media(name,false));
drop policy if exists maak_chat_media_upload on storage.objects;
create policy maak_chat_media_upload on storage.objects for insert to authenticated
 with check(bucket_id='chat-media' and public.can_access_maak_media(name,true));
-- No UPDATE/overwrite policy. Deletion is limited to the owner's orphan uploads.
drop policy if exists maak_chat_media_orphan_delete on storage.objects;
create policy maak_chat_media_orphan_delete on storage.objects for delete to authenticated
 using(bucket_id='chat-media' and split_part(name,'/',2)=auth.uid()::text
 and public.can_access_maak_media(name,false)
 and not exists(select 1 from public.messages m where m.attachment_path=name));

create or replace function public.validate_maak_chat_attachment() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare meta jsonb; suffix text;
begin
 if new.message_type='text' then return new; end if;
 if new.sender_id<>auth.uid() or not public.can_access_maak_media(new.attachment_path,true) then raise exception 'not_allowed'; end if;
 suffix := case new.attachment_mime when 'image/png' then 'png' when 'image/jpeg' then 'jpg' when 'image/webp' then 'webp' when 'audio/wav' then 'wav' else '' end;
 if new.attachment_path <> new.request_id::text||'/'||new.sender_id::text||'/'||new.id::text||'.'||suffix then raise exception 'invalid_attachment'; end if;
 select metadata into meta from storage.objects where bucket_id='chat-media' and name=new.attachment_path;
 if meta is null or (meta->>'size')::bigint is distinct from new.attachment_bytes::bigint
 or meta->>'mimetype' is distinct from new.attachment_mime then raise exception 'attachment_not_uploaded'; end if;
 if new.message_type='voice' and (new.attachment_bytes<>44+new.duration_ms*32 and abs(new.attachment_bytes-44-new.duration_ms*32)>32) then raise exception 'invalid_voice_duration'; end if;
 return new;
end; $$;
drop trigger if exists maak_validate_chat_attachment on public.messages;
create trigger maak_validate_chat_attachment before insert on public.messages for each row execute function public.validate_maak_chat_attachment();
revoke all on function public.validate_maak_chat_attachment() from public,anon,authenticated;

-- Server-written agreement record: never infer agreement for existing members.
create table if not exists public.ai_matching_agreements(
 user_id uuid primary key references public.profiles(id) on delete cascade,
 version text not null, accepted_at timestamptz not null default now()
);
alter table public.ai_matching_agreements enable row level security;
revoke all on public.ai_matching_agreements from anon,authenticated;
grant select on public.ai_matching_agreements to authenticated;
drop policy if exists maak_ai_agreement_self on public.ai_matching_agreements;
create policy maak_ai_agreement_self on public.ai_matching_agreements for select to authenticated using(user_id=auth.uid());
create or replace function public.accept_maak_ai_matching(p_version text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null or not public.is_maak_active() or not exists(select 1 from public.profiles where id=auth.uid() and role in ('volunteer','help_seeker')) then raise exception 'not_allowed'; end if;
 if p_version is distinct from '2026-11-05' then raise exception 'invalid_consent_version'; end if;
 insert into public.ai_matching_agreements(user_id,version) values(auth.uid(),p_version)
 on conflict(user_id) do update set version=excluded.version,accepted_at=now() where ai_matching_agreements.version<>excluded.version;
 update public.volunteer_profiles set ai_matching_consent=true where user_id=auth.uid();
end; $$;
create or replace function public.has_maak_ai_consent() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.ai_matching_agreements where user_id=auth.uid() and version='2026-11-05');
$$;
revoke all on function public.accept_maak_ai_matching(text),public.has_maak_ai_consent() from public,anon;
grant execute on function public.accept_maak_ai_matching(text),public.has_maak_ai_consent() to authenticated;
notify pgrst,'reload schema';
commit;
