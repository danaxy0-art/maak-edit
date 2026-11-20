#!/usr/bin/env bash
# Builds a fresh test database the way production was built, applies
# 20261021_account_blocking.sql twice, then runs the functional, rollback and
# concurrency tests. Usage (from the repo root, against a THROWAWAY server):
#   PSQL=psql PGPORT=54329 PGLOG=/path/to/server.log bash tests/database/account_blocking/run_tests.sh
export PGCLIENTENCODING=UTF8
# pwd -W gives C:/... paths on Git Bash, which Windows psql.exe needs.
HERE="$(cd "$(dirname "$0")" && (pwd -W 2>/dev/null || pwd))"; ROOT="$(cd "$HERE/../../.." && (pwd -W 2>/dev/null || pwd))"
P="${PSQL:-psql}"; PORT="${PGPORT:-54329}"
pg(){ "$P" -h 127.0.0.1 -p "$PORT" -U postgres -X "$@"; }
MIGRATION="$ROOT/supabase/migrations/20261021_account_blocking.sql"
BASE=("$HERE/00_supabase_stub.sql" "$ROOT/supabase_schema.sql"
  "$ROOT/supabase/migrations/20261018_matching.sql" "$ROOT/supabase/migrations/20261018_condition_reviews.sql"
  "$ROOT/supabase/migrations/20261020_profile_repair.sql" "$HERE/05_live_only_approximation.sql" "$HERE/10_seed.sql")
build(){ pg -q -c "drop database if exists $1;" -c "create database $1;" >/dev/null 2>&1
  for f in "${BASE[@]}"; do pg -d "$1" -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>"$HERE/.step.err" || { echo "BUILD FAILED: $f"; cat "$HERE/.step.err"; exit 1; }; done; }
apply(){ pg -d "$1" -q -v ON_ERROR_STOP=1 -f "$2" >/dev/null 2>"$HERE/.step.err" || { echo "APPLY FAILED: $2"; grep ERROR "$HERE/.step.err"; exit 1; }; }
# Every policy, function and trigger, fingerprinted, for exact before/after comparison.
snapshot(){ pg -d "$1" -At -v ON_ERROR_STOP=1 -c "select 'policy|'||schemaname||'.'||tablename||'.'||policyname||'|'||md5(cmd||permissive||roles::text||coalesce(qual,'')||'|'||coalesce(with_check,'')) from pg_policies
 union all select 'function|'||p.oid::regprocedure::text||'|'||md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g'))||coalesce(p.proconfig::text,'')||coalesce(p.proacl::text,'')||p.prosecdef::text||p.provolatile::text||pg_get_function_result(p.oid)) from pg_proc p where p.pronamespace in ('public'::regnamespace,'auth'::regnamespace,'storage'::regnamespace)
 union all select 'trigger|'||tgrelid::regclass||'.'||tgname||'|'||md5(pg_get_triggerdef(oid)) from pg_trigger where not tgisinternal order by 1"; }

echo "1. Functional tests (migration applied twice to a populated database)"
build maak_test; apply maak_test "$MIGRATION"; apply maak_test "$MIGRATION"
pg -d maak_test -q -v ON_ERROR_STOP=1 -P pager=off -f "$HERE/20_tests.sql" > "$HERE/.results.txt" 2>&1 || { echo "TEST SCRIPT FAILED"; tail "$HERE/.results.txt"; exit 1; }
grep "| FAIL" "$HERE/.results.txt"; tail -3 "$HERE/.results.txt" | head -1
pg -d maak_test -q -v ON_ERROR_STOP=1 -P pager=off -f "$ROOT/supabase/checks/20261021_account_blocking_verify.sql"

echo "2. Rollback restores the pre-migration state exactly"
build maak_rb; snapshot maak_rb > "$HERE/.before.txt"; apply maak_rb "$MIGRATION"
apply maak_rb "$ROOT/supabase/rollbacks/20261021_account_blocking_rollback.sql"; snapshot maak_rb > "$HERE/.after.txt"
# The rollback keeps the moderation tables, so only their two guard functions and three triggers may remain.
extra=$(diff "$HERE/.before.txt" "$HERE/.after.txt" | grep '^>' | grep -vE 'guard_account_block_target|guard_moderation_history|account_blocks\.maak_account_block_target|account_moderation_events\.maak_moderation_history')
missing=$(diff "$HERE/.before.txt" "$HERE/.after.txt" | grep '^<')
if [ -z "$extra$missing" ]; then echo "   PASS: $(wc -l < "$HERE/.before.txt") objects restored"; else echo "   FAIL:"; echo "$extra$missing"; fi
apply maak_rb "$MIGRATION" && echo "   PASS: migration re-applies after rollback"

echo "3. Concurrency"
bash "$HERE/30_concurrency.sh" "$ROOT" "$HERE"
rm -f "$HERE/.step.err" "$HERE/step.err" "$HERE/c.a" "$HERE/c.b" "$HERE/c.c" "$HERE/.before.txt" "$HERE/.after.txt"
