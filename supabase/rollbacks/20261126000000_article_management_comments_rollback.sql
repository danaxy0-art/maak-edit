-- Rollback for 20261126000000_article_management_comments.sql.
-- Removes article comments (all comment data is deleted), the comment and admin
-- article RPCs, reply notifications and articles.condition_id (illness_type_id
-- is kept, so earlier tags are still there). Articles, illness types, likes, saves,
-- their policies and health_article_like_counts are left in place, because the
-- Health Library reader used them before this migration.
begin;
drop function if exists public.add_article_comment(uuid,text,uuid);
drop function if exists public.delete_article_comment(uuid);
drop function if exists public.get_article_comments(uuid);
drop function if exists public.health_article_comment_counts();
drop function if exists public.can_comment_on_articles();
drop function if exists public.admin_list_articles();
drop function if exists public.admin_save_article(uuid,text,text,text,uuid,text,text,text,text);
drop function if exists public.admin_delete_article(uuid);
drop function if exists public.admin_set_article_status(uuid,text);
drop table if exists public.article_comments;
drop index if exists public.articles_condition;
alter table public.articles drop column if exists condition_id;
delete from public.notifications where kind='article_reply';
notify pgrst, 'reload schema';
commit;
