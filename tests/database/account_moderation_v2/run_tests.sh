#!/usr/bin/env bash
# Tests for 20261022 (visibility, labels) and 20261023 (appeals) on a THROWAWAY
# local server, never Supabase. Usage from the repo root:
#   PSQL=psql PGPORT=54329 PGLOG=/path/to/server.log bash tests/database/account_moderation_v2/run_tests.sh
export PGCLIENTENCODING=UTF8
# pwd -W gives C:/... paths on Git Bash, which Windows psql.exe needs.
HERE="$(cd "$(dirname "$0")" && (pwd -W 2>/dev/null || pwd))"; ROOT="$(cd "$HERE/../../.." && (pwd -W 2>/dev/null || pwd))"
T="$ROOT/tests/database/account_blocking"; P="${PSQL:-psql}"; PORT="${PGPORT:-54329}"
pg(){ "$P" -h 127.0.0.1 -p "$PORT" -U postgres -X "$@"; }
M="$ROOT/supabase/migrations"; A="$M/20261022_account_moderation_visibility.sql"; B="$M/20261023_account_appeals.sql"
RA="$ROOT/supabase/rollbacks/20261022_account_moderation_visibility_rollback.sql"
RB="$ROOT/supabase/rollbacks/20261023_account_appeals_rollback.sql"
BASE=("$T/00_supabase_stub.sql" "$ROOT/supabase_schema.sql" "$M/20261018_matching.sql" "$M/20261018_condition_reviews.sql"
  "$M/20261020_profile_repair.sql" "$T/05_live_only_approximation.sql" "$T/10_seed.sql" "$M/20261021_account_blocking.sql")
apply(){ pg -d "$1" -q -v ON_ERROR_STOP=1 -f "$2" >/dev/null 2>"$HERE/.step.err"; }
must(){ apply "$1" "$2" || { echo "APPLY FAILED: $2"; grep -E "ERROR" "$HERE/.step.err"; exit 1; }; }
# $1 db, $2 = "seed" to add the v2 seed (blocks made before the new migrations)
base(){ pg -q -c "drop database if exists $1;" -c "create database $1;" >/dev/null 2>&1
  for f in "${BASE[@]}"; do must "$1" "$f"; done; [ "$2" = seed ] && must "$1" "$HERE/11_seed_v2.sql"; return 0; }
# Every policy, function, trigger, column, index and constraint, fingerprinted.
snapshot(){ pg -d "$1" -At -v ON_ERROR_STOP=1 -c "select 'policy|'||schemaname||'.'||tablename||'.'||policyname||'|'||md5(cmd||permissive||roles::text||coalesce(qual,'')||'|'||coalesce(with_check,'')) from pg_policies
 union all select 'function|'||p.oid::regprocedure::text||'|'||md5(btrim(regexp_replace(p.prosrc,'[[:space:]]+',' ','g'))||coalesce(p.proconfig::text,'')||coalesce(p.proacl::text,'')||p.prosecdef::text||p.provolatile::text||pg_get_function_result(p.oid)) from pg_proc p where p.pronamespace in ('public'::regnamespace,'auth'::regnamespace,'storage'::regnamespace)
 union all select 'trigger|'||tgrelid::regclass||'.'||tgname||'|'||md5(pg_get_triggerdef(oid)) from pg_trigger where not tgisinternal
 union all select 'column|'||c.relname||'.'||a.attname||'|'||format_type(a.atttypid,a.atttypmod)||'|'||a.attnotnull from pg_attribute a join pg_class c on c.oid=a.attrelid where c.relnamespace='public'::regnamespace and c.relkind='r' and a.attnum>0 and not a.attisdropped
 union all select 'index|'||indexrelid::regclass||'|'||md5(pg_get_indexdef(indexrelid)) from pg_index i join pg_class c on c.oid=i.indrelid where c.relnamespace='public'::regnamespace
 union all select 'constraint|'||conrelid::regclass||'.'||conname||'|'||md5(pg_get_constraintdef(oid)) from pg_constraint where connamespace='public'::regnamespace
 union all select 'table|'||c.relname||'|'||c.relrowsecurity||'|'||coalesce(c.relacl::text,'') from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r'
 order by 1"; }
same(){ if diff "$1" "$2" >/dev/null; then echo "   PASS: $3 ($(wc -l < "$1") objects identical)"; else echo "   FAIL: $3"; diff "$1" "$2" | head -20; fi; }

echo "1. Functional and security tests (A and B each applied twice)"
base maak_v2 seed; must maak_v2 "$A"; must maak_v2 "$B"; must maak_v2 "$A"; must maak_v2 "$B"; must maak_v2 "$HERE/15_harness.sql"
pg -d maak_v2 -q -v ON_ERROR_STOP=1 -P pager=off -f "$HERE/21_tests_v2.sql" > "$HERE/.results.txt" 2>&1 || { echo "TEST SCRIPT FAILED"; tail "$HERE/.results.txt"; exit 1; }
grep "| FAIL" "$HERE/.results.txt"; tail -3 "$HERE/.results.txt" | head -1

echo "2. Post-deploy verification queries"
base maak_v2_verify seed; must maak_v2_verify "$A"
pg -d maak_v2_verify -At -F' ' -c "$(cat "$ROOT/supabase/checks/20261022_account_moderation_visibility_verify.sql")" | sed 's/^/   A only: /'
must maak_v2_verify "$B"
pg -d maak_v2_verify -At -F' ' -c "$(cat "$ROOT/supabase/checks/20261022_account_moderation_visibility_verify.sql")" | sed 's/^/   A after B: /'
pg -d maak_v2_verify -At -F' ' -c "$(cat "$ROOT/supabase/checks/20261023_account_appeals_verify.sql")" | sed 's/^/   B: /'

echo "3. Backfill refuses to guess (each must abort and leave nothing applied)"
for case in "changed reason|update account_blocks set reason='Edited' where user_id=test.u('c4')" \
            "duplicate event|insert into account_moderation_events(user_id,action,reason,actor_id,created_at) select user_id,'blocked',reason,blocked_by,blocked_at from account_blocks where user_id=test.u('c4')" \
            "later event|insert into account_moderation_events(user_id,action,reason,actor_id,created_at) select user_id,'reactivated','x',blocked_by,blocked_at+interval '1 minute' from account_blocks where user_id=test.u('c4')" \
            "other event, identical timestamp|insert into account_moderation_events(user_id,action,reason,actor_id,created_at) select user_id,'reactivated','x',blocked_by,blocked_at from account_blocks where user_id=test.u('c4')" \
            "null blocker whose admin still exists|update account_blocks set blocked_by=null where user_id=test.u('c4')"; do
  name="${case%%|*}"; sql="${case#*|}"
  base maak_v2_bf seed; must maak_v2_bf "$A"; pg -d maak_v2_bf -q -c "$sql" >/dev/null
  if apply maak_v2_bf "$B"; then echo "   FAIL: $name applied"; else
    err=$(grep -o "block_event_backfill_failed[^(]*" "$HERE/.step.err" | head -1)
    left=$(pg -d maak_v2_bf -At -c "select to_regclass('public.account_block_appeals') is null and not exists(select 1 from pg_attribute where attrelid='public.account_blocks'::regclass and attname='block_event_id')")
    [ -n "$err" ] && [ "$left" = t ] && echo "   PASS: $name -> $err; nothing applied" || echo "   FAIL: $name ($err, clean=$left)"
  fi
done

base maak_v2_bf seed; must maak_v2_bf "$A"
pg -d maak_v2_bf -q -c "delete from auth.users where id=test.u('a6');" >/dev/null   # c7's blocking admin
if apply maak_v2_bf "$B"; then
  ok=$(pg -d maak_v2_bf -At -c "select b.blocked_by is null and e.reason='Abusive language' and e.actor_id=test.u('a6') and e.user_id=b.user_id from account_blocks b join account_moderation_events e on e.id=b.block_event_id where b.user_id=test.u('c7')")
  [ "$ok" = t ] && echo "   PASS: deleted blocking admin -> linked to the one correct event" || echo "   FAIL: deleted admin link ($ok)"
else echo "   FAIL: deleted blocking admin case refused: $(grep -m1 ERROR "$HERE/.step.err")"; fi

echo "4. Rollback and roll-forward"
base maak_v2_rb seed; snapshot maak_v2_rb > "$HERE/.s0"; must maak_v2_rb "$A"; snapshot maak_v2_rb > "$HERE/.sa"; must maak_v2_rb "$B"
pg -d maak_v2_rb -q -c "select set_config('request.jwt.claims',json_build_object('sub',test.u('c4'))::text,false); select submit_my_appeal('Rollback data');" >/dev/null
must maak_v2_rb "$RB"; snapshot maak_v2_rb > "$HERE/.sb_rb"
kept=$(diff "$HERE/.sa" "$HERE/.sb_rb" | grep -c '^>'); lost=$(diff "$HERE/.sa" "$HERE/.sb_rb" | grep -c '^<')
echo "   B rollback: $lost 20261022 objects changed (want 0), $kept retained appeal objects (by design)"
echo "   B rollback keeps data: $(pg -d maak_v2_rb -At -c "select count(*)||' appeal row(s)' from account_block_appeals")"
pg -d maak_v2_rb -q -c "select set_config('request.jwt.claims',json_build_object('sub',test.u('a1'))::text,false); select admin_block_account(test.u('c1'),'Blocked while rolled back');" >/dev/null && echo "   PASS: original admin_block_account works after B rollback"
must maak_v2_rb "$B"; echo "   PASS: B re-applies; block made during rollback linked: $(pg -d maak_v2_rb -At -c "select block_event_id is not null from account_blocks where user_id=test.u('c1')")"
must maak_v2_rb "$RB"
sed -n '/^-- OPTIONAL/,$p' "$RB" | grep -E '^-- (begin|drop|alter|commit)' | sed 's/^-- //' > "$HERE/.cleanup.sql"
pg -d maak_v2_rb -q -c "delete from account_blocks where block_event_id is null;" >/dev/null   # block made in this test only
must maak_v2_rb "$HERE/.cleanup.sql"; snapshot maak_v2_rb > "$HERE/.sb_clean"; same "$HERE/.sa" "$HERE/.sb_clean" "B rollback + optional cleanup restores 20261022 exactly"
must maak_v2_rb "$RA"; snapshot maak_v2_rb > "$HERE/.sa_rb"; same "$HERE/.s0" "$HERE/.sa_rb" "A rollback restores 20261021 exactly"
base maak_v2_rb2 seed; must maak_v2_rb2 "$A"; must maak_v2_rb2 "$B"
if apply maak_v2_rb2 "$RA"; then echo "   FAIL: A rollback ran while B installed"; else echo "   PASS: A rollback refuses while B is installed"; fi
must maak_v2_rb "$A"; must maak_v2_rb "$B"; echo "   PASS: A and B roll forward again after full rollback"

echo "5. Regression: original account-blocking suite on a database with A and B"
base maak_v2_reg; must maak_v2_reg "$A"; must maak_v2_reg "$B"
pg -d maak_v2_reg -q -v ON_ERROR_STOP=1 -P pager=off -f "$T/20_tests.sql" > "$HERE/.regression.txt" 2>&1
grep "| FAIL" "$HERE/.regression.txt"; tail -3 "$HERE/.regression.txt" | head -1

echo "6. Concurrency"
bash "$HERE/30_concurrency_v2.sh" "$ROOT" "$HERE"
rm -f "$HERE/.step.err" "$HERE/.s0" "$HERE/.sa" "$HERE/.sb_rb" "$HERE/.sb_clean" "$HERE/.sa_rb" "$HERE/.cleanup.sql"
