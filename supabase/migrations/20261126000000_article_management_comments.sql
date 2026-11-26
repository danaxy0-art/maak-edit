-- Health Library: admin article management, member comments and replies,
-- and reply notifications. Apply after 20261021_account_blocking.sql and
-- 20261106000000_push_notifications.sql. Repeatable (safe to run twice).
--
-- 1. Article tables. The app already reads public.articles, illness_types,
--    article_likes and saved_articles. They are created here only when missing,
--    so this file also works on a fresh project. Existing rows are kept.
--    Articles are tagged with a health condition from public.chronic_conditions
--    (the list Admin manages under Conditions) through articles.condition_id.
--    Existing illness_type_id tags are carried over by matching names.
-- 2. Admin article management: admin_list_articles, admin_save_article,
--    admin_delete_article. All writes go through these security-definer RPCs, so
--    they do not depend on the policies already on public.articles.
-- 3. Comments: public.article_comments. Help seekers and approved volunteers
--    who are not restricted can comment on published articles and reply to
--    comments. Replies are one level deep: a reply to a reply joins the same
--    thread (parent_id = the top-level comment; reply_to_id = the comment
--    actually answered). Members delete their own comments; admins delete any.
--    A deleted comment that has replies stays as "This comment was deleted"
--    (deleted_at set, text and author removed) so the replies are kept; one
--    without replies is removed.
--    Clients use RPCs only; the table has no client grants.
--
-- Re-running this file upgrades a database where an earlier version of it
-- (articles tagged with illness_types) was applied.
-- 4. Notifications: a reply notifies the author of the comment it answers
--    (kind 'article_reply', reference_id = the article). Title: who replied and
--    on which article; body: the reply itself. The existing
--    maak_notification_push trigger also sends it as a push.
begin;

-- 1. Article tables --------------------------------------------------------------
create table if not exists public.illness_types (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now());

create table if not exists public.articles (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  summary text not null default '',
  content text not null default '',
  illness_type_id uuid references public.illness_types(id) on delete set null,
  source_name text,
  source_url text,
  image_url text,
  status text not null default 'draft',
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
-- Older copies of the table may lack some columns the app reads.
alter table public.articles add column if not exists summary text not null default '';
alter table public.articles add column if not exists content text not null default '';
alter table public.articles add column if not exists illness_type_id uuid;
alter table public.articles add column if not exists source_name text;
alter table public.articles add column if not exists source_url text;
alter table public.articles add column if not exists image_url text;
alter table public.articles add column if not exists status text not null default 'draft';
alter table public.articles add column if not exists published_at timestamptz;
alter table public.articles add column if not exists created_at timestamptz not null default now();
alter table public.articles add column if not exists updated_at timestamptz not null default now();
-- Optional fields are saved as NULL when left empty (published_at stays NULL
-- for drafts), so they must not be NOT NULL. Some live copies of the table
-- were made with NOT NULL here, which failed saves with error 23502.
do $$
declare col text;
begin
 foreach col in array array['illness_type_id','source_name','source_url','image_url','published_at'] loop
  if exists(select 1 from information_schema.columns where table_schema='public'
            and table_name='articles' and column_name=col and is_nullable='NO') then
   execute format('alter table public.articles alter column %I drop not null', col);
   raise notice 'articles.%: NOT NULL removed (optional field).', col;
  end if;
 end loop;
 -- Required columns this app never fills (no default) would also fail every
 -- save. Make them optional and report them.
 for col in select c.column_name from information_schema.columns c
  where c.table_schema='public' and c.table_name='articles' and c.is_nullable='NO'
   and c.column_default is null and c.is_identity='NO' and c.is_generated='NEVER'
   and c.column_name not in ('id','title','summary','content','status','created_at','updated_at','condition_id')
 loop
  execute format('alter table public.articles alter column %I drop not null', col);
  raise notice 'articles.%: NOT NULL removed (the app does not fill this column).', col;
 end loop;
end $$;

create table if not exists public.article_likes (
  user_id uuid not null references auth.users(id) on delete cascade,
  article_id uuid not null references public.articles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, article_id));
create table if not exists public.saved_articles (
  user_id uuid not null references auth.users(id) on delete cascade,
  article_id uuid not null references public.articles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, article_id));

-- On a fresh project, install the reader policies the app relies on. On an
-- existing project these tables already have their own policies; leave them.
do $$
begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='articles') then
  alter table public.articles enable row level security;
  create policy articles_read_published on public.articles for select to authenticated
   using (status='published' or is_maak_admin());
  grant select on public.articles to authenticated;
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='illness_types') then
  alter table public.illness_types enable row level security;
  create policy illness_types_read on public.illness_types for select to authenticated using (true);
  create policy illness_types_admin on public.illness_types for all to authenticated
   using (is_maak_admin()) with check (is_maak_admin());
  grant select, insert, update, delete on public.illness_types to authenticated;
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='article_likes') then
  alter table public.article_likes enable row level security;
  create policy article_likes_own on public.article_likes for all to authenticated
   using (user_id=auth.uid()) with check (user_id=auth.uid());
  grant select, insert, delete on public.article_likes to authenticated;
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='saved_articles') then
  alter table public.saved_articles enable row level security;
  create policy saved_articles_own on public.saved_articles for all to authenticated
   using (user_id=auth.uid()) with check (user_id=auth.uid());
  grant select, insert, delete on public.saved_articles to authenticated;
 end if;
 -- The reader calls this for like counts. Keep an existing definition.
 if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
               where n.nspname='public' and p.proname='health_article_like_counts') then
  execute $f$
   create function public.health_article_like_counts()
   returns table(article_id uuid, like_count bigint)
   language sql stable security definer set search_path=public,pg_temp as $b$
    select l.article_id, count(*) from article_likes l
    join articles a on a.id=l.article_id and a.status='published'
    group by l.article_id;
   $b$;
  $f$;
  revoke all on function public.health_article_like_counts() from public, anon;
  grant execute on function public.health_article_like_counts() to authenticated;
 end if;
end $$;

-- Health condition of an article: one of the conditions Admin manages.
alter table public.articles add column if not exists condition_id uuid;
do $$
begin
 if not exists(select 1 from pg_constraint where conname='articles_condition_id_fkey') then
  alter table public.articles add constraint articles_condition_id_fkey
   foreign key (condition_id) references public.chronic_conditions(id) on delete set null;
 end if;
end $$;
create index if not exists articles_condition on public.articles(condition_id);
-- Carry over earlier illness_types tags whose name matches a condition
-- (case-insensitive, or one of the condition's aliases).
update public.articles a set condition_id=c.id
from public.illness_types i, public.chronic_conditions c
where a.condition_id is null and i.id=a.illness_type_id and not c.is_other
 and (lower(btrim(c.name))=lower(btrim(i.name))
      or lower(btrim(i.name))=any(select lower(x) from unnest(c.aliases) x));
do $$
declare v_unmatched int;
begin
 select count(*) into v_unmatched from public.articles
 where condition_id is null and illness_type_id is not null;
 if v_unmatched>0 then
  raise notice '% article(s) had an illness type with no matching condition and are now General. Set their condition in Admin > Health Library articles.', v_unmatched;
 end if;
end $$;

-- 2. Admin article management ---------------------------------------------------
-- Dropped first so a re-run can change their parameters and result columns.
drop function if exists public.admin_list_articles();
drop function if exists public.admin_save_article(uuid,text,text,text,uuid,text,text,text,text);
create function public.admin_list_articles()
returns table(id uuid, title text, summary text, content text, condition_id uuid,
  condition_name text, source_name text, source_url text, image_url text, status text,
  published_at timestamptz, created_at timestamptz, updated_at timestamptz,
  like_count bigint, comment_count bigint)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 return query
  select a.id, a.title, a.summary, a.content, a.condition_id, c.name,
   a.source_name, a.source_url, a.image_url, a.status, a.published_at,
   a.created_at, a.updated_at,
   (select count(*) from article_likes l where l.article_id=a.id),
   (select count(*) from article_comments c where c.article_id=a.id)
  from articles a left join chronic_conditions c on c.id=a.condition_id
  order by coalesce(a.updated_at, a.created_at) desc;
end; $$;

-- Creates (p_id null) or updates an article and returns its id.
-- published_at is set the first time an article is published and kept after.
create function public.admin_save_article(
  p_id uuid, p_title text, p_summary text, p_content text, p_condition_id uuid,
  p_source_name text, p_source_url text, p_image_url text, p_status text)
returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_title text := btrim(coalesce(p_title,''));
 v_summary text := btrim(coalesce(p_summary,''));
 v_content text := btrim(coalesce(p_content,''));
 v_source_name text := nullif(btrim(coalesce(p_source_name,'')),'');
 v_source_url text := nullif(btrim(coalesce(p_source_url,'')),'');
 v_image_url text := nullif(btrim(coalesce(p_image_url,'')),'');
 v_id uuid;
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if char_length(v_title) not between 3 and 200 then raise exception 'invalid_article_title'; end if;
 if char_length(v_summary) not between 10 and 500 then raise exception 'invalid_article_summary'; end if;
 if char_length(v_content) not between 20 and 20000 then raise exception 'invalid_article_content'; end if;
 if v_source_name is not null and char_length(v_source_name) > 120 then raise exception 'invalid_article_source'; end if;
 if v_source_url is not null and (char_length(v_source_url) > 2000 or v_source_url !~* '^https?://[^\s/]+\.[^\s]+$') then
  raise exception 'invalid_article_url';
 end if;
 if v_image_url is not null and (char_length(v_image_url) > 2000 or v_image_url !~* '^https://[^\s/]+\.[^\s]+$') then
  raise exception 'invalid_article_image';
 end if;
 if coalesce(p_status,'') not in ('draft','published') then raise exception 'invalid_article_status'; end if;
 if p_status='published' and (v_source_name is null or v_source_url is null) then
  raise exception 'article_source_required';
 end if;
 -- An active condition other than "Other". An article keeps a condition that
 -- was deactivated after it was tagged.
 if p_condition_id is not null and not exists(
   select 1 from chronic_conditions c where c.id=p_condition_id and not c.is_other
   and (c.is_active or exists(select 1 from articles a where a.id=p_id and a.condition_id=c.id))) then
  raise exception 'invalid_article_condition';
 end if;

 if p_id is null then
  insert into articles(title,summary,content,condition_id,source_name,source_url,image_url,
   status,published_at,created_at,updated_at)
  values(v_title,v_summary,v_content,p_condition_id,v_source_name,v_source_url,v_image_url,
   p_status,case when p_status='published' then now() end,now(),now())
  returning articles.id into v_id;
 else
  update articles a set title=v_title, summary=v_summary, content=v_content,
   condition_id=p_condition_id, source_name=v_source_name, source_url=v_source_url,
   image_url=v_image_url, status=p_status,
   published_at=case when p_status='published' then coalesce(a.published_at, now()) else a.published_at end,
   updated_at=now()
  where a.id=p_id returning a.id into v_id;
  if v_id is null then raise exception 'article_unavailable'; end if;
 end if;
 return v_id;
end; $$;

-- Deletes an article with its likes, saves and comments, whatever ON DELETE
-- rules the existing foreign keys use.
create or replace function public.admin_delete_article(p_id uuid)
returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if not exists(select 1 from articles where id=p_id) then raise exception 'article_unavailable'; end if;
 delete from article_comments where article_id=p_id;
 delete from article_likes where article_id=p_id;
 delete from saved_articles where article_id=p_id;
 delete from articles where id=p_id;
end; $$;

-- Publishes an article or moves it back to drafts without editing it.
-- Publishing needs a source, as in admin_save_article.
create or replace function public.admin_set_article_status(p_id uuid, p_status text)
returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_article articles%rowtype;
begin
 if not is_maak_admin() then raise exception 'not_allowed'; end if;
 if coalesce(p_status,'') not in ('draft','published') then raise exception 'invalid_article_status'; end if;
 select * into v_article from articles where id=p_id for update;
 if v_article.id is null then raise exception 'article_unavailable'; end if;
 if p_status='published' and (nullif(btrim(coalesce(v_article.source_name,'')),'') is null
     or nullif(btrim(coalesce(v_article.source_url,'')),'') is null) then
  raise exception 'article_source_required';
 end if;
 update articles a set status=p_status, updated_at=now(),
  published_at=case when p_status='published' then coalesce(a.published_at, now()) else a.published_at end
 where a.id=p_id;
end; $$;

-- 3. Comments ---------------------------------------------------------------------
create table if not exists public.article_comments (
  id uuid primary key default gen_random_uuid(),
  article_id uuid not null references public.articles(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid references public.article_comments(id) on delete cascade,
  reply_to_id uuid references public.article_comments(id) on delete set null,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now());
create index if not exists article_comments_article_date on public.article_comments(article_id, created_at);
create index if not exists article_comments_parent on public.article_comments(parent_id);
create index if not exists article_comments_user_date on public.article_comments(user_id, created_at desc);
-- Soft delete: a deleted comment with replies keeps its row (empty text) so
-- the thread stays readable.
alter table public.article_comments add column if not exists deleted_at timestamptz;
alter table public.article_comments drop constraint if exists article_comments_body_check;
alter table public.article_comments add constraint article_comments_body_check
 check (deleted_at is not null or char_length(btrim(body)) between 1 and 1000);
alter table public.article_comments enable row level security;
revoke all on public.article_comments from anon, authenticated;

-- Help seekers and approved volunteers whose account is not restricted.
create or replace function public.can_comment_on_articles()
returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select auth.uid() is not null
  and not is_maak_account_blocked(auth.uid())
  and exists(select 1 from profiles p where p.id=auth.uid() and (
   p.role='help_seeker'
   or (p.role='volunteer' and exists(select 1 from volunteer_profiles v
        where v.user_id=p.id and v.status='approved'))));
$$;

-- Dropped first: a re-run adds the is_deleted column to its result.
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

-- Comment counts for published articles (shown on the reader's article cards).
create or replace function public.health_article_comment_counts()
returns table(article_id uuid, comment_count bigint)
language sql stable security definer set search_path=public,pg_temp as $$
 select c.article_id, count(*) from article_comments c
 join articles a on a.id=c.article_id and a.status='published'
 where auth.uid() is not null and c.deleted_at is null
 group by c.article_id;
$$;

-- Adds a comment, or a reply when p_reply_to is set. Returns the new id.
create or replace function public.add_article_comment(p_article_id uuid, p_body text,
  p_reply_to uuid default null)
returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_body text := btrim(coalesce(p_body,''));
 v_title text;
 v_target article_comments%rowtype;
 v_parent uuid;
 v_id uuid;
 v_name text;
begin
 if not can_comment_on_articles() then raise exception 'comment_not_allowed'; end if;
 if char_length(v_body) not between 1 and 1000 then raise exception 'invalid_comment'; end if;
 select a.title into v_title from articles a where a.id=p_article_id and a.status='published';
 if v_title is null then raise exception 'article_unavailable'; end if;
 -- Light flood protection: at most 5 comments per minute per member.
 if (select count(*) from article_comments c where c.user_id=auth.uid()
     and c.created_at > now() - interval '1 minute') >= 5 then
  raise exception 'comment_rate_limited';
 end if;

 if p_reply_to is not null then
  select * into v_target from article_comments c where c.id=p_reply_to and c.article_id=p_article_id;
  if v_target.id is null or v_target.deleted_at is not null then
   raise exception 'comment_unavailable';
  end if;
  v_parent := coalesce(v_target.parent_id, v_target.id);
 end if;

 insert into article_comments(article_id,user_id,parent_id,reply_to_id,body)
 values(p_article_id,auth.uid(),v_parent,v_target.id,v_body)
 returning article_comments.id into v_id;

 -- Notify the author of the answered comment (never for one's own comment).
 if v_target.id is not null and v_target.user_id<>auth.uid() then
  select nullif(btrim(full_name),'') into v_name from profiles where id=auth.uid();
  -- Title: who replied, on which article. Body: the reply.
  insert into notifications(user_id,title,body,kind,reference_id) values(
   v_target.user_id,
   coalesce(v_name,'Someone')||' replied on "'||
    case when char_length(v_title)>60 then left(v_title,59)||'…' else v_title end||'"',
   v_body,
   'article_reply', p_article_id);
 end if;
 return v_id;
end; $$;

-- Authors delete their own comments; admins delete any comment.
-- A comment that has replies (in its thread, or answering it) becomes
-- "This comment was deleted" and the replies stay. Otherwise it is removed,
-- along with any deleted placeholder left with no replies.
create or replace function public.delete_article_comment(p_comment_id uuid)
returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_comment article_comments%rowtype;
begin
 if auth.uid() is null then raise exception 'comment_not_allowed'; end if;
 select * into v_comment from article_comments c where c.id=p_comment_id for update;
 if v_comment.id is null or v_comment.deleted_at is not null then raise exception 'comment_unavailable'; end if;
 if v_comment.user_id<>auth.uid() and not is_maak_admin() then raise exception 'comment_not_allowed'; end if;
 if v_comment.user_id=auth.uid() and is_maak_account_blocked(auth.uid()) then raise exception 'account_blocked'; end if;
 if exists(select 1 from article_comments x where x.parent_id=v_comment.id or x.reply_to_id=v_comment.id) then
  update article_comments set deleted_at=now(), body='' where id=v_comment.id;
 else
  delete from article_comments where id=v_comment.id;
  loop
   delete from article_comments t where t.article_id=v_comment.article_id and t.deleted_at is not null
    and not exists(select 1 from article_comments x where x.parent_id=t.id or x.reply_to_id=t.id);
   exit when not found;
  end loop;
 end if;
end; $$;

-- 4. Grants --------------------------------------------------------------------------
revoke all on function public.admin_list_articles(),
 public.admin_save_article(uuid,text,text,text,uuid,text,text,text,text),
 public.admin_delete_article(uuid),
 public.admin_set_article_status(uuid,text),
 public.can_comment_on_articles(),
 public.get_article_comments(uuid),
 public.health_article_comment_counts(),
 public.add_article_comment(uuid,text,uuid),
 public.delete_article_comment(uuid) from public, anon;
grant execute on function public.admin_list_articles(),
 public.admin_save_article(uuid,text,text,text,uuid,text,text,text,text),
 public.admin_delete_article(uuid),
 public.admin_set_article_status(uuid,text),
 public.can_comment_on_articles(),
 public.get_article_comments(uuid),
 public.health_article_comment_counts(),
 public.add_article_comment(uuid,text,uuid),
 public.delete_article_comment(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
