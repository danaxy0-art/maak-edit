-- Profile pictures. Apply after the account blocking migration. Repeatable.
--
-- * profiles.avatar_path holds the picture's path in the private "avatars" bucket,
--   or null for no picture (the profile then shows initials).
-- * Files live at <user id>/<random uuid>.<jpg|png|webp>. A new file is uploaded
--   on every change, so phones never show a cached old picture; the app removes
--   the previous file afterwards.
-- * Any signed-in, unrestricted member (and admins) can view pictures, through
--   short-lived signed URLs. This read rule is identical in
--   20261107010000_shared_profile_pictures.sql, so re-running either file in any
--   order never hides pictures from other members.
-- * Restricted accounts can't upload or change their picture.
begin;

alter table public.profiles add column if not exists avatar_path text;

-- The path must point inside the user's own folder, in the expected shape.
create or replace function public.guard_maak_avatar_path() returns trigger
language plpgsql set search_path=public,pg_temp as $$
begin
 if new.avatar_path is not null and new.avatar_path !~ (
  '^'||new.id::text||'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$')
 then raise exception 'invalid_avatar_path'; end if;
 return new;
end; $$;
drop trigger if exists maak_avatar_path_guard on public.profiles;
create trigger maak_avatar_path_guard before insert or update of avatar_path on public.profiles
 for each row execute function public.guard_maak_avatar_path();
revoke all on function public.guard_maak_avatar_path() from public,anon,authenticated;

-- Private bucket: 5 MB, PNG / JPEG / WebP only.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('avatars','avatars',false,5242880,array['image/png','image/jpeg','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,
 allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists maak_avatar_read on storage.objects;
create policy maak_avatar_read on storage.objects for select to authenticated
 using(bucket_id='avatars' and (
  (storage.foldername(name))[1]=auth.uid()::text
  or public.is_maak_admin()
  or (select public.is_maak_active())));
drop policy if exists maak_avatar_upload on storage.objects;
create policy maak_avatar_upload on storage.objects for insert to authenticated
 with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text and public.is_maak_active());
drop policy if exists maak_avatar_delete on storage.objects;
create policy maak_avatar_delete on storage.objects for delete to authenticated
 using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

notify pgrst,'reload schema';
commit;
