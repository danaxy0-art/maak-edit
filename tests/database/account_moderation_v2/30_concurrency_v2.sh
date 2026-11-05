#!/usr/bin/env bash
# Concurrency tests for 20261023 appeals: real parallel sessions on a fresh database.
# Usage: 30_concurrency_v2.sh <repo root> <this directory>   (see README.md)
# Env: PSQL, PGPORT (default 54329), PGLOG (server log, optional, counts deadlocks).
export PGCLIENTENCODING=UTF8
R="$1"; HERE="$2"; T="$R/tests/database/account_blocking"; P="${PSQL:-psql}"; PORT="${PGPORT:-54329}"; DB=maak_v2_conc
pg(){ "$P" -h 127.0.0.1 -p "$PORT" -U postgres -X "$@"; }
pg -q -c "drop database if exists $DB;" -c "create database $DB;" >/dev/null 2>&1
for f in "$T/00_supabase_stub.sql" "$R/supabase_schema.sql" "$R/supabase/migrations/20261018_matching.sql" \
  "$R/supabase/migrations/20261018_condition_reviews.sql" "$R/supabase/migrations/20261020_profile_repair.sql" \
  "$T/05_live_only_approximation.sql" "$T/10_seed.sql" "$R/supabase/migrations/20261021_account_blocking.sql" \
  "$R/supabase/migrations/20261022_account_moderation_visibility.sql" "$R/supabase/migrations/20261023_account_appeals.sql"; do
  pg -d $DB -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>"$HERE/.step.err" || { echo "BUILD FAILED: $f"; cat "$HERE/.step.err"; exit 1; }
done
pg -d $DB -q -c "create function test.act(p_sub uuid) returns void language plpgsql as \$\$ begin perform set_config('role','none',false); perform set_config('request.jwt.claims',json_build_object('sub',p_sub,'role','authenticated')::text,false); perform set_config('role','authenticated',false); end \$\$; create function test.last_appeal(p text) returns uuid language sql security definer as \$\$ select id from public.account_block_appeals where user_id=test.u(p) order by submitted_at desc limit 1 \$\$; grant usage on schema test to authenticated; grant execute on all functions in schema test to authenticated;"

now(){ date +%s%N; }
run(){ local s=$(now); local out; out=$(pg -d $DB -At -v ON_ERROR_STOP=1 -c "$1" 2>&1 >/dev/null); local rc=$?; local e=$(now)
  local msg="OK"; [ $rc -ne 0 ] && msg=$(echo "$out" | grep -m1 ERROR | sed 's/.*ERROR: *//')
  awk -v s=$s -v e=$e -v m="$msg" 'BEGIN{printf "%s (%.1fs)\n", m, (e-s)/1e9}'; }
q(){ pg -d $DB -At -c "$1" 2>&1; }
as(){ echo "select test.act(test.u('$1'));"; }
before=0; [ -n "$PGLOG" ] && before=$(grep -ci "deadlock detected" "$PGLOG")
q "$(as a1) select admin_block_account(test.u('c2'),'Concurrency block');" >/dev/null

echo "V1 double submit: first submit holds its transaction 3s, second arrives 1s later -> waits, then appeal_pending"
run "begin; $(as c2) select submit_my_appeal('first'); select pg_sleep(3); commit;" > "$HERE/c.a" &
sleep 1; echo "  second: $(run "$(as c2) select submit_my_appeal('second');")"; wait
echo "  first:  $(cat "$HERE/c.a")"; echo "  appeals stored: $(q "select count(*) from account_block_appeals where user_id=test.u('c2')")"

echo "V2 two admins decide the same appeal -> one wins, the other appeal_already_decided"
run "begin; $(as a1) select admin_decide_appeal(test.last_appeal('c2'),false,'Rejected by a1'); select pg_sleep(3); commit;" > "$HERE/c.a" &
sleep 1; echo "  a2 approve: $(run "$(as a2) select admin_decide_appeal(test.last_appeal('c2'),true);")"; wait
echo "  a1 reject:  $(cat "$HERE/c.a")"
echo "  status=$(q "select status from account_block_appeals where id=test.last_appeal('c2')") still_blocked=$(q "select count(*) from account_blocks where user_id=test.u('c2')")"

echo "V3 decision racing manual reactivation (reactivation first) -> appeal closed, decision refused"
q "$(as c2) select submit_my_appeal('attempt two');" >/dev/null
run "begin; $(as a1) select admin_reactivate_account(test.u('c2')); select pg_sleep(3); commit;" > "$HERE/c.a" &
sleep 1; echo "  a2 approve: $(run "$(as a2) select admin_decide_appeal(test.last_appeal('c2'),true);")"; wait
echo "  reactivate: $(cat "$HERE/c.a")"
echo "  appeal=$(q "select status||'/'||coalesce(closed_reason,'-') from account_block_appeals where id=test.last_appeal('c2')")"

echo "V4 submit racing reactivation (reactivation first) -> submit waits, then account_active"
q "$(as a1) select admin_block_account(test.u('c2'),'Second block');" >/dev/null
run "begin; $(as a1) select admin_reactivate_account(test.u('c2')); select pg_sleep(3); commit;" > "$HERE/c.a" &
sleep 1; echo "  submit: $(run "$(as c2) select submit_my_appeal('too late');")"; wait
echo "  reactivate: $(cat "$HERE/c.a")"

echo "V5 submit racing reactivation (submit first) -> reactivation waits, then closes the new appeal"
q "$(as a1) select admin_block_account(test.u('c2'),'Third block');" >/dev/null
run "begin; $(as c2) select submit_my_appeal('just in time'); select pg_sleep(3); commit;" > "$HERE/c.a" &
sleep 1; echo "  reactivate: $(run "$(as a1) select admin_reactivate_account(test.u('c2'));")"; wait
echo "  submit: $(cat "$HERE/c.a")"
echo "  appeal=$(q "select status||'/'||coalesce(closed_reason,'-') from account_block_appeals where id=test.last_appeal('c2')")"

echo "V6 third-attempt race: two submits at once after two rejections -> one attempt 3, one appeal_pending"
q "$(as a1) select admin_block_account(test.u('c2'),'Fourth block');" >/dev/null
for i in 1 2; do q "$(as c2) select submit_my_appeal('round $i');" >/dev/null; q "$(as a1) select admin_decide_appeal(test.last_appeal('c2'),false,'No');" >/dev/null; done
run "begin; $(as c2) select submit_my_appeal('final A'); select pg_sleep(2); commit;" > "$HERE/c.a" &
sleep 0.5; echo "  B: $(run "$(as c2) select submit_my_appeal('final B');")"; wait
echo "  A: $(cat "$HERE/c.a")"
echo "  this block: attempts=$(q "select string_agg(attempt::text,',' order by attempt) from account_block_appeals a join account_blocks b on b.block_event_id=a.block_event_id where b.user_id=test.u('c2')")"
echo "  fourth after rejection: $(q "$(as a1) select admin_decide_appeal(test.last_appeal('c2'),false,'No');" >/dev/null; run "$(as c2) select submit_my_appeal('fourth');")"

if [ -n "$PGLOG" ]; then echo "deadlocks detected during run: $(( $(grep -ci "deadlock detected" "$PGLOG") - before ))"; else echo "set PGLOG to count deadlocks"; fi
rm -f "$HERE/c.a" "$HERE/.step.err"
