#!/usr/bin/env bash
# Production compatibility tests on a THROWAWAY local server, never Supabase.
# Builds a database carrying the exported production definitions, then tests the
# production sequence 20261021 -> production compat patch -> 20261022 -> 20261023,
# its verification, rollback and re-application. Usage from the repo root:
#   PSQL=psql PGPORT=54329 bash tests/database/production_compat/run_tests.sh
export PGCLIENTENCODING=UTF8
HERE="$(cd "$(dirname "$0")" && (pwd -W 2>/dev/null || pwd))"; ROOT="$(cd "$HERE/../../.." && (pwd -W 2>/dev/null || pwd))"
T="$ROOT/tests/database/account_blocking"; V="$ROOT/tests/database/account_moderation_v2"; P="${PSQL:-psql}"; PORT="${PGPORT:-54329}"
pg(){ "$P" -h 127.0.0.1 -p "$PORT" -U postgres -X "$@"; }
M="$ROOT/supabase/migrations"; PR="$ROOT/supabase/production"
M21="$M/20261021_account_blocking.sql"; PATCH="$PR/20261021_production_compat.sql"
M22="$M/20261022_account_moderation_visibility.sql"; M23="$M/20261023_account_appeals.sql"
RB23="$ROOT/supabase/rollbacks/20261023_account_appeals_rollback.sql"
RB22="$ROOT/supabase/rollbacks/20261022_account_moderation_visibility_rollback.sql"
RB21P="$PR/20261021_account_blocking_production_rollback.sql"
apply(){ pg -d "$1" -q -v ON_ERROR_STOP=1 -f "$2" >/dev/null 2>"$HERE/.step.err"; }
must(){ apply "$1" "$2" || { echo "APPLY FAILED: $2"; grep ERROR "$HERE/.step.err"; exit 1; }; }
# Production-like database before deployment: platform stub, schema and team
# updates, the exported production definitions, shared seed shaped like production.
prod(){ pg -q -c "drop database if exists $1;" -c "create database $1;" >/dev/null 2>&1
  for f in "$T/00_supabase_stub.sql" "$ROOT/supabase_schema.sql" "$M/20261018_matching.sql" "$M/20261018_condition_reviews.sql" \
    "$M/20261020_profile_repair.sql" "$HERE/05_production_definitions.sql" "$T/10_seed.sql" "$HERE/12_seed_production.sql" "$HERE/13_baseline.sql"; do
    must "$1" "$f"; done; }
deploy(){ must "$1" "$M21"; must "$1" "$PATCH"; must "$1" "$M22"; must "$1" "$M23"; }
rollback(){ must "$1" "$RB23"; must "$1" "$RB22"; must "$1" "$RB21P"; }
q(){ pg -d "$1" -At -F' ' -c "$2"; }
snapshot(){ pg -d "$1" -At -v ON_ERROR_STOP=1 -c "select 'policy|'||schemaname||'.'||tablename||'.'||policyname||'|'||md5(cmd||permissive||roles::text||coalesce(qual,'')||'|'||coalesce(with_check,'')) from pg_policies
 union all select 'function|'||p.oid::regprocedure::text||'|'||md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g'))||coalesce(p.proconfig::text,'')||coalesce((select string_agg(a::text,',' order by a::text) from unnest(p.proacl) a),'')||p.prosecdef::text||p.provolatile::text||pg_get_function_result(p.oid)) from pg_proc p where p.pronamespace in ('public'::regnamespace,'auth'::regnamespace,'storage'::regnamespace)
 union all select 'trigger|'||tgrelid::regclass||'.'||tgname||'|'||md5(pg_get_triggerdef(oid)) from pg_trigger where not tgisinternal
 union all select 'column|'||c.relname||'.'||a.attname||'|'||format_type(a.atttypid,a.atttypmod)||'|'||a.attnotnull from pg_attribute a join pg_class c on c.oid=a.attrelid where c.relnamespace='public'::regnamespace and c.relkind='r' and a.attnum>0 and not a.attisdropped
 union all select 'index|'||indexrelid::regclass||'|'||md5(pg_get_indexdef(indexrelid)) from pg_index i join pg_class c on c.oid=i.indrelid where c.relnamespace='public'::regnamespace
 union all select 'constraint|'||conrelid::regclass||'.'||conname||'|'||md5(pg_get_constraintdef(oid)) from pg_constraint where connamespace='public'::regnamespace
 union all select 'table|'||c.relname||'|'||c.relrowsecurity||'|'||coalesce((select string_agg(a::text,',' order by a::text) from unnest(c.relacl) a),'') from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r'
 union all select 'publication|'||tablename from pg_publication_tables where pubname='supabase_realtime'
 order by 1"; }

echo "1. Read-only prechecks on the production-like database (all must be true)"
prod pc_pre; pg -d pc_pre -At -F' ' -v ON_ERROR_STOP=1 -f "$PR/precheck_production.sql" 2>&1 | sed 's/^/   /'

echo "2. Production sequence, verification and functional tests"
prod pc_deploy; deploy pc_deploy
echo "   production verify (after the whole sequence): $(pg -d pc_deploy -At -F' ' -f "$PR/verify_production_compat.sql")"
echo "   20261022 verify: $(pg -d pc_deploy -At -F' ' -f "$ROOT/supabase/checks/20261022_account_moderation_visibility_verify.sql")"
echo "   20261023 verify: $(pg -d pc_deploy -At -F' ' -f "$ROOT/supabase/checks/20261023_account_appeals_verify.sql")"
echo "   20261021 repository verify (redefined_bodies_ok expected f: matching is patched): $(pg -d pc_deploy -At -F' ' -f "$ROOT/supabase/checks/20261021_account_blocking_verify.sql")"
must pc_deploy "$V/15_harness.sql"
pg -d pc_deploy -q -v ON_ERROR_STOP=1 -P pager=off -f "$HERE/25_tests_production.sql" > "$HERE/.results.txt" 2>&1 || { echo "TEST SCRIPT FAILED"; tail "$HERE/.results.txt"; exit 1; }
grep "| FAIL" "$HERE/.results.txt"; echo "   functional: $(tail -3 "$HERE/.results.txt" | head -1)"

echo "3. Verify after the patch alone (before 20261022/20261023)"
prod pc_step; must pc_step "$M21"
echo "   after 20261021 only (open-request rule missing, sessions widened): $(pg -d pc_step -At -F' ' -f "$PR/verify_production_compat.sql")"
must pc_step "$PATCH"; echo "   after the patch: $(pg -d pc_step -At -F' ' -f "$PR/verify_production_compat.sql")"

echo "4. Rollback, data preservation and re-application"
prod pc_rb; snapshot pc_rb > "$HERE/.s0"; deploy pc_rb
pg -d pc_rb -q -c "select set_config('request.jwt.claims',json_build_object('sub',test.u('a1'))::text,false); select admin_restrict_conversation(test.u('e6'),'Restricted before rollback'); select admin_block_account(test.u('c2'),'Blocked before rollback');" >/dev/null
rollback pc_rb; snapshot pc_rb > "$HERE/.s_rb"
lost=$(diff "$HERE/.s0" "$HERE/.s_rb" | grep -c '^<'); kept=$(diff "$HERE/.s0" "$HERE/.s_rb" | grep '^>' | grep -cv 'account_\|moderation\|appeal\|block_event')
echo "   pre-deployment objects changed by the rollback: $lost (want 0); unexpected extra objects: $kept (want 0)"
echo "   production functions restored exactly: $(diff <(grep -E 'function\|(admin_restrict_conversation|admin_support_requests|book_support_session|browse_volunteers|can_send_maak_message|maak_matching_context|my_maak_conditions|my_support_requests|my_support_sessions|is_maak_admin)\(' "$HERE/.s0") <(grep -E 'function\|(admin_restrict_conversation|admin_support_requests|book_support_session|browse_volunteers|can_send_maak_message|maak_matching_context|my_maak_conditions|my_support_requests|my_support_sessions|is_maak_admin)\(' "$HERE/.s_rb") >/dev/null && echo yes || echo NO)"
echo "   restriction made during deployment kept after rollback: $(q pc_rb "select restricted_at is not null and restriction_reason='Restricted before rollback' from support_requests where id=test.u('e6')")"
echo "   restricted conversation still cannot message after rollback: $(q pc_rb "select not test.can_send_as('c3','e6')")"
echo "   other active conversations untouched: $(q pc_rb "select count(*)=3 from support_requests where status='accepted' and restricted_at is null")"
sed -n '/^-- OPTIONAL/,$p' "$RB23" | grep -E '^-- (begin|drop|alter|commit)' | sed 's/^-- //' > "$HERE/.cleanup23.sql"
sed -n '/^-- OPTIONAL/,$p' "$RB21P" | grep -E '^-- (begin|drop|alter|commit)' | sed 's/^-- //' | sed 's/  *--.*$//' > "$HERE/.cleanup21.sql"
must pc_rb "$HERE/.cleanup23.sql"; must pc_rb "$HERE/.cleanup21.sql"; snapshot pc_rb > "$HERE/.s_clean"
diff "$HERE/.s0" "$HERE/.s_clean" >/dev/null && echo "   PASS: rollback + optional cleanups restore the pre-deployment state exactly ($(wc -l < "$HERE/.s0") objects)" || { echo "   FAIL: differences:"; diff "$HERE/.s0" "$HERE/.s_clean" | head; }
deploy pc_rb; echo "   re-applied sequence verifies: $(pg -d pc_rb -At -F' ' -f "$PR/verify_production_compat.sql")"

echo "5. Existing suites on production definitions (differences must be production behaviour)"
pc_base(){ pg -q -c "drop database if exists $1;" -c "create database $1;" >/dev/null 2>&1
  for f in "$T/00_supabase_stub.sql" "$ROOT/supabase_schema.sql" "$M/20261018_matching.sql" "$M/20261018_condition_reviews.sql" \
    "$M/20261020_profile_repair.sql" "$HERE/05_production_definitions.sql" "$T/10_seed.sql"; do must "$1" "$f"; done; }
pc_base pc_v2; must pc_v2 "$M21"; must pc_v2 "$PATCH"; must pc_v2 "$V/11_seed_v2.sql"; must pc_v2 "$M22"; must pc_v2 "$M23"; must pc_v2 "$V/15_harness.sql"
pg -d pc_v2 -q -v ON_ERROR_STOP=1 -P pager=off -f "$V/21_tests_v2.sql" > "$HERE/.v2.txt" 2>&1
echo "   account_moderation_v2 suite: $(tail -3 "$HERE/.v2.txt" | head -1)"; grep "| FAIL" "$HERE/.v2.txt" | sed 's/^/   /'
pc_base pc_old; must pc_old "$M21"; must pc_old "$PATCH"
pg -d pc_old -q -v ON_ERROR_STOP=1 -P pager=off -f "$T/20_tests.sql" > "$HERE/.old.txt" 2>&1
echo "   original account_blocking suite: $(tail -3 "$HERE/.old.txt" | head -1)"; grep "| FAIL" "$HERE/.old.txt" | sed 's/^/   /'
rm -f "$HERE/.step.err" "$HERE/.s0" "$HERE/.s_rb" "$HERE/.s_clean" "$HERE/.cleanup23.sql" "$HERE/.cleanup21.sql"
