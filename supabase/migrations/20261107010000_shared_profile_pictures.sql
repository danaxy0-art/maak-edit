-- Apply after 20261107000000_profile_pictures.sql. Repeatable.
--
-- Profile pictures become visible to every signed-in member, not only the owner:
-- in matches, requests, conversations, the journey and the admin pages.
--
-- * Storage: any active (not restricted) member, and admins, can read avatar files.
--   Uploading and deleting stay limited to the owner's own folder.
-- * maak_avatar_paths(ids): profiles RLS only lets a member read their own row,
--   so the app asks this function for other people's picture paths. Restricted
--   members' pictures are hidden from everyone except themselves and admins.
begin;

drop policy if exists maak_avatar_read on storage.objects;
create policy maak_avatar_read on storage.objects for select to authenticated
 using(bucket_id='avatars' and (
  (storage.foldername(name))[1]=auth.uid()::text
  or public.is_maak_admin()
  or (select public.is_maak_active())));

create or replace function public.maak_avatar_paths(p_user_ids uuid[])
returns table(user_id uuid, avatar_path text)
language sql stable security definer set search_path=public,pg_temp as $$
 select p.id, p.avatar_path from profiles p
 where auth.uid() is not null
  and (public.is_maak_active() or public.is_maak_admin())
  and p.id = any((coalesce(p_user_ids,'{}'::uuid[]))[1:200])
  and p.avatar_path is not null
  and (p.id=auth.uid() or public.is_maak_admin()
       or not exists(select 1 from account_blocks b where b.user_id=p.id));
$$;
revoke all on function public.maak_avatar_paths(uuid[]) from public,anon;
grant execute on function public.maak_avatar_paths(uuid[]) to authenticated;

notify pgrst,'reload schema';
commit;
