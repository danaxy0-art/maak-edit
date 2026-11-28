-- Rollback for 20261128020000_article_comment_authors.sql
-- Restores "on delete cascade" on article_comments.user_id and the previous
-- get_article_comments (without author_status).
-- Warning: comments whose author's account was deleted (user_id is null) are
-- removed first, with their replies, because the old rules require an author.

delete from public.article_comments where user_id is null;

alter table public.article_comments drop constraint if exists article_comments_user_id_fkey;
alter table public.article_comments
  add constraint article_comments_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;
alter table public.article_comments alter column user_id set not null;

drop function if exists public.get_article_comments(uuid);
-- Deleted comments come back with is_deleted, no text and no author.
create function public.get_article_comments(p_article_id uuid)
returns table(id uuid, article_id uuid, user_id uuid, parent_id uuid, reply_to_id uuid,
  reply_to_name text, body text, created_at timestamptz, author_name text,
  author_role text, is_mine boolean, is_deleted boolean)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not (is_maak_admin() or can_comment_on_articles()) then raise exception 'comment_not_allowed'; end if;
 if not exists(select 1 from articles a where a.id=p_article_id
               and (a.status='published' or is_maak_admin())) then
  raise exception 'article_unavailable';
 end if;
 return query
  select c.id, c.article_id,
   case when c.deleted_at is null then c.user_id end,
   c.parent_id, c.reply_to_id,
   case when c.reply_to_id is null or r.deleted_at is not null then null
        else coalesce(nullif(btrim(rp.full_name),''),'A member') end,
   case when c.deleted_at is null then c.body else '' end,
   c.created_at,
   case when c.deleted_at is null then coalesce(nullif(btrim(p.full_name),''),'A member') end,
   case when c.deleted_at is null then p.role end,
   c.deleted_at is null and c.user_id=auth.uid(),
   c.deleted_at is not null
  from article_comments c
  left join profiles p on p.id=c.user_id
  left join article_comments r on r.id=c.reply_to_id
  left join profiles rp on rp.id=r.user_id
  where c.article_id=p_article_id
  order by c.created_at, c.id;
end; $$;


revoke all on function public.get_article_comments(uuid) from public, anon;
grant execute on function public.get_article_comments(uuid) to authenticated;
notify pgrst, 'reload schema';
