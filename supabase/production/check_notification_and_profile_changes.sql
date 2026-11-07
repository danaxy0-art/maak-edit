-- Read-only check: which notification, profile-picture and blocking changes are
-- installed. Run in the SQL editor; every row should say true. Changes nothing.
select step, installed from (values
 (1,  '20261106000000 push: device_tokens table',
      to_regclass('public.device_tokens') is not null),
 (2,  '20261106000000 push: vault secret maak_project_url',
      exists(select 1 from vault.secrets where name='maak_project_url')),
 (3,  '20261106000000 push: vault secret maak_push_secret',
      exists(select 1 from vault.secrets where name='maak_push_secret')),
 (4,  '20261106000000 push: restriction push trigger',
      exists(select 1 from pg_trigger where tgname='maak_account_block_push')),
 (5,  '20261106010000 appeal push to admins + new-match notices',
      exists(select 1 from pg_trigger where tgname='maak_appeal_push')),
 (6,  '20261106020000 names and message text in notifications',
      exists(select 1 from pg_trigger where tgname='maak_notification_details')),
 (7,  '20261107000000 profile pictures: avatars bucket',
      exists(select 1 from storage.buckets where id='avatars')),
 (8,  '20261107010000 profile pictures visible to others',
      to_regprocedure('public.maak_avatar_paths(uuid[])') is not null),
 (8.5,'profile pictures: storage rule lets other members view them',
      exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
             and policyname='maak_avatar_read' and qual ilike '%is_maak_active%')),
 (9,  '20261107020000 notification push waits for the block to be saved',
      exists(select 1 from pg_trigger where tgname='maak_notification_push' and tgdeferrable)),
 (10, '20261107030000 appeals allowed (guard exempts notification inserts)',
      exists(select 1 from pg_proc where proname='guard_maak_blocked_actor'
             and prosrc ilike '%TG_TABLE_NAME=''notifications''%')),
 (11, '20261107030000 instant redirect: status signal streamed live',
      exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
             and tablename='account_status_signals'))
) as t(n, step, installed)
order by n;

-- Edge Functions can't be checked from SQL. After changing them, redeploy:
--   send-push       (restricted users get only the restriction push; pop-up channel)
--   delete-account  (also removes the profile picture)
-- Recent send-push results (status 200 and "sent" > 0 means delivered to Firebase):
--   select status_code, content, created from net._http_response order by created desc limit 10;
