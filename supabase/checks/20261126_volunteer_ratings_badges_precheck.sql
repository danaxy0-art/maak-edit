-- READ-ONLY precheck for 20261126100000_volunteer_ratings.sql and
-- 20261126110000_volunteer_badges.sql. Run in the Supabase SQL Editor BEFORE
-- applying them. It only reads the catalog and counts rows; it changes nothing.
-- Every row should show ok = true. Rows marked 'info' explain, never block.
with
fn as (
  select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) args,
         regexp_replace(lower(pg_get_functiondef(p.oid)), '\s+', '', 'g') body
  from pg_proc p where p.pronamespace = 'public'::regnamespace
),
col as (
  select table_name, column_name from information_schema.columns where table_schema = 'public'
),
checks(check_name, ok, detail) as (
  -- 1. Columns the migrations read
  select 'column '||t||'.'||c, exists(select 1 from col where table_name = t and column_name = c), 'required'
  from (values ('support_requests','status'), ('support_requests','seeker_id'), ('support_requests','volunteer_id'),
               ('support_requests','ended_at'), ('support_requests','restricted_at'),
               ('messages','request_id'), ('messages','sender_id'),
               ('volunteer_profiles','user_id'), ('volunteer_profiles','status'),
               ('account_blocks','user_id')) v(t, c)
  -- 2. Functions the migrations call
  union all
  select 'function '||f||'('||a||')', exists(select 1 from fn where proname = f and args = a), 'required'
  from (values ('is_maak_active',''), ('is_maak_account_blocked','p_user_id uuid'),
               ('guard_maak_blocked_actor',''), ('end_maak_chat','p_request_id uuid')) v(f, a)
  -- 3. Production moderation: restriction is recorded in restricted_at, and
  --    lifting clears it (the badge excludes credit while it is set).
  union all
  select 'admin_restrict_conversation sets restricted_at',
         exists(select 1 from fn where proname = 'admin_restrict_conversation' and body like '%restricted_at=now()%'),
         'production-only function; badge credit is excluded while restricted_at is set'
  union all
  select 'admin_restrict_conversation does not clear ended_at',
         not exists(select 1 from fn where proname = 'admin_restrict_conversation' and body like '%ended_at=null%'),
         'clearing ended_at would not remove recorded credit, but should be known'
  union all
  select 'admin_lift_conversation_restriction clears restricted_at',
         exists(select 1 from fn where proname = 'admin_lift_conversation_restriction' and body like '%restricted_at=null%'),
         'from 20261107110000; lifting restores badge credit'
  union all
  -- Bodies are lower-cased with whitespace removed: "update public.support_requests
  -- set ... restricted_at = ..." becomes "...support_requestsset...restricted_at=...".
  select 'functions that write support_requests.restricted_at (review list)',
         true, coalesce((select string_agg(proname, ', ' order by proname) from fn
                         where body like '%support_requestsset%restricted_at=%'), 'none')
  -- 4. Functions that end or reopen chats (expected: end_maak_chat, decide_maak_chat_reopen)
  union all
  select 'functions that write support_requests.ended_at (review list)', true,
         coalesce((select string_agg(proname, ', ' order by proname) from fn
                   where body like '%support_requestsset%ended_at=%'), 'none')
  union all
  select 'triggers on support_requests (review list)', true,
         coalesce((select string_agg(tgname, ', ' order by tgname) from pg_trigger
                   where tgrelid = 'public.support_requests'::regclass and not tgisinternal), 'none')
  -- 5. Name collisions (an existing object from an earlier run of THESE files is fine)
  union all
  select 'table '||t||' free or from these migrations', true,
         case when to_regclass('public.'||t) is null then 'free'
              else 'info: already exists, from an earlier run of these migrations (re-running is safe)' end
  from unnest(array['volunteer_ratings','volunteer_support_completions','volunteer_badge_levels']) t
  union all
  select 'function name '||f||' free or same signature', not exists(select 1 from fn where proname = f and args <> a),
         coalesce((select string_agg(proname||'('||args||')', '; ') from fn where proname = f), 'free')
  from (values ('rate_maak_volunteer','p_request_id uuid, p_stars integer'),
               ('correct_maak_rating','p_request_id uuid, p_stars integer'),
               ('my_maak_rating','p_request_id uuid'),
               ('maak_volunteer_stats','p_volunteer_ids uuid[]'),
               ('my_maak_badge_progress','')) v(f, a)
  -- 6. What the badge backfill would record (read-only count)
  union all
  select 'backfill preview: ended conversations with a volunteer reply', true,
         (select count(*)::text from support_requests r
          where r.status = 'accepted' and r.ended_at is not null
            and exists(select 1 from messages m where m.request_id = r.id and m.sender_id = r.volunteer_id))
         || ' conversation(s) would be recorded; '
         || (select count(*)::text from support_requests r
             where r.status = 'accepted' and r.ended_at is null
               and exists(select 1 from messages m where m.request_id = r.id and m.sender_id = r.volunteer_id))
         || ' open conversation(s) earn credit when they end'
)
select check_name, ok, detail from checks order by ok, check_name;
