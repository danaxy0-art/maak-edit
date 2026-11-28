-- Article comments from removed accounts
--
-- 1. A comment stays when its author's account is deleted. Before this,
--    article_comments.user_id was "on delete cascade", so deleting an account
--    (delete-account Edge Function -> auth.admin.deleteUser) removed every
--    comment the person wrote, and with parent_id cascading, every reply to
--    those comments too. Now user_id becomes null and the text is kept.
-- 2. get_article_comments returns author_status for each comment:
--      'active'      the author's account exists and is not blocked
--      'deleted'     the author deleted their account (user_id is null)
--      'deactivated' the author's account is blocked (account_blocks)
--    For deleted and deactivated authors, author_name is "[deleted account]"
--    or "[deactivated account]", and no user_id or role is returned, so the
--    app shows no profile link. reply_to_name ("Replying to ...") follows the
--    same rule.
--    A comment the author deleted (deleted_at set) is unchanged: no text, no
--    author, is_deleted = true.
--
-- Repeatable: safe to run more than once.

-- 1. Keep comments when the author's account is deleted -----------------------
alter table public.article_comments alter column user_id drop not null;

do $$
declare
  v_name text;
begin
  -- Drop the existing foreign key on user_id, whatever it is called.
  for v_name in
    select con.conname
    from pg_constraint con
    join pg_attribute att
      on att.attrelid = con.conrelid and att.attnum = any(con.conkey)
    where con.conrelid = 'public.article_comments'::regclass
      and con.contype = 'f'
      and att.attname = 'user_id'
  loop
    execute format('alter table public.article_comments drop constraint %I', v_name);
  end loop;
end $$;

alter table public.article_comments
  add constraint article_comments_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete set null;

-- 2. Author status in the comment list -----------------------------------------
-- Dropped first: the result gains the author_status column.
drop function if exists public.get_article_comments(uuid);
create function public.get_article_comments(p_article_id uuid)
returns table(id uuid, article_id uuid, user_id uuid, parent_id uuid, reply_to_id uuid,
  reply_to_name text, body text, created_at timestamptz, author_name text,
  author_role text, is_mine boolean, is_deleted boolean, author_status text)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not (is_maak_admin() or can_comment_on_articles()) then raise exception 'comment_not_allowed'; end if;
 if not exists(select 1 from articles a where a.id=p_article_id
               and (a.status='published' or is_maak_admin())) then
  raise exception 'article_unavailable';
 end if;
 return query
  with cm as (
   select c.*,
    p.full_name, p.role,
    case when c.user_id is null or p.id is null then 'deleted'
         when is_maak_account_blocked(c.user_id) then 'deactivated'
         else 'active' end as status,
    r.deleted_at as reply_deleted_at,
    rp.full_name as reply_full_name,
    case when r.id is null then null
         when r.user_id is null or rp.id is null then 'deleted'
         when is_maak_account_blocked(r.user_id) then 'deactivated'
         else 'active' end as reply_status
   from article_comments c
   left join profiles p on p.id=c.user_id
   left join article_comments r on r.id=c.reply_to_id
   left join profiles rp on rp.id=r.user_id
   where c.article_id=p_article_id)
  select x.id, x.article_id,
   case when x.deleted_at is null and x.status='active' then x.user_id end,
   x.parent_id, x.reply_to_id,
   case when x.reply_to_id is null or x.reply_deleted_at is not null then null
        when x.reply_status='deleted' then '[deleted account]'
        when x.reply_status='deactivated' then '[deactivated account]'
        else coalesce(nullif(btrim(x.reply_full_name),''),'A member') end,
   case when x.deleted_at is null then x.body else '' end,
   x.created_at,
   case when x.deleted_at is not null then null
        when x.status='deleted' then '[deleted account]'
        when x.status='deactivated' then '[deactivated account]'
        else coalesce(nullif(btrim(x.full_name),''),'A member') end,
   case when x.deleted_at is null and x.status='active' then x.role end,
   x.deleted_at is null and x.user_id is not null and x.user_id=auth.uid(),
   x.deleted_at is not null,
   x.status
  from cm x
  order by x.created_at, x.id;
end; $$;

revoke all on function public.get_article_comments(uuid) from public, anon;
grant execute on function public.get_article_comments(uuid) to authenticated;

notify pgrst, 'reload schema';
