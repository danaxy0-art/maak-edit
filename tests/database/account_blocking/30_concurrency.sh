#!/usr/bin/env bash
# Concurrency tests: two or three real sessions against a fresh isolated database.
# Usage: 30_concurrency.sh <repo root> <this directory>   (see README.md)
# Env: PSQL (psql binary), PGPORT (default 54329), PGLOG (server log, optional,
# used to count deadlocks). Never point this at a shared or production server.
export PGCLIENTENCODING=UTF8
R="$1"; SP="$2"; P="${PSQL:-psql}"; DB=maak_conc; PORT="${PGPORT:-54329}"
"$P" -h 127.0.0.1 -p "$PORT" -U postgres -X -q -c "drop database if exists $DB;" -c "create database $DB;" 2>/dev/null
for f in "$SP/00_supabase_stub.sql" "$R/supabase_schema.sql" "$R/supabase/migrations/20261018_matching.sql" \
  "$R/supabase/migrations/20261018_condition_reviews.sql" "$R/supabase/migrations/20261020_profile_repair.sql" \
  "$SP/05_live_only_approximation.sql" "$SP/10_seed.sql" "$R/supabase/migrations/20261021_account_blocking.sql"; do
  "$P" -h 127.0.0.1 -p "$PORT" -U postgres -d $DB -X -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>"$SP/step.err" || { echo "BUILD FAILED: $f"; exit 1; }
done
"$P" -h 127.0.0.1 -p "$PORT" -U postgres -d $DB -X -q -c "create function test.act(p_sub uuid) returns void language plpgsql as \$\$ begin perform set_config('role','none',false); perform set_config('request.jwt.claims',json_build_object('sub',p_sub,'role','authenticated')::text,false); perform set_config('role','authenticated',false); end \$\$; grant usage on schema test to authenticated; grant execute on all functions in schema test to authenticated;"

now(){ date +%s%N; }
# run SQL; print "OK" or the ERROR message, plus elapsed seconds
run(){ local s=$(now); local out; out=$("$P" -h 127.0.0.1 -p "$PORT" -U postgres -d $DB -X -At -v ON_ERROR_STOP=1 -c "$1" 2>&1 >/dev/null); local rc=$?; local e=$(now)
  local msg="OK"; [ $rc -ne 0 ] && msg=$(echo "$out" | grep -m1 ERROR | sed 's/.*ERROR: *//')
  awk -v s=$s -v e=$e -v m="$msg" 'BEGIN{printf "%s (%.1fs)\n", m, (e-s)/1e9}'; }
q(){ "$P" -h 127.0.0.1 -p "$PORT" -U postgres -d $DB -X -At -c "$1" 2>&1; }
before=0; [ -n "$PGLOG" ] && before=$(grep -ci "deadlock detected" "$PGLOG")

echo "C1 block in flight (holds 3s), counterpart c1 messages b2 1s later -> must WAIT then FAIL"
run "begin; select test.act(test.u('a1')); select admin_block_account(test.u('b2'),'C1'); select pg_sleep(3); commit;" > "$SP/c.a" &
sleep 1; echo "  message: $(run "select test.act(test.u('c1')); insert into messages(request_id,sender_id,body) values(test.u('e3'),test.u('c1'),'C1');")"; wait
echo "  block:   $(cat "$SP/c.a")"
q "select test.act(test.u('a1')); select admin_reactivate_account(test.u('b2'));" >/dev/null

echo "C2 message in flight (holds 3s), admin blocks the sender c1 1s later -> block WAITS, both commit in order"
run "begin; select test.act(test.u('c1')); insert into messages(request_id,sender_id,body) values(test.u('e3'),test.u('c1'),'C2'); select pg_sleep(3); commit;" > "$SP/c.a" &
sleep 1; echo "  block:   $(run "select test.act(test.u('a1')); select admin_block_account(test.u('c1'),'C2');")"; wait
echo "  message: $(cat "$SP/c.a")"
echo "  after: message rows=$(q "select count(*) from messages where body='C2'"), c1 blocked=$(q "select count(*) from account_blocks where user_id=test.u('c1')")"
echo "  c1 next message: $(run "select test.act(test.u('c1')); insert into messages(request_id,sender_id,body) values(test.u('e3'),test.u('c1'),'C2b');")"

echo "C3 booking e6 in flight (holds request lock 3s); block of seeker c3 and admin restriction of e6 arrive together"
run "begin; select test.act(test.u('b4')); select book_support_session(test.u('e6'),now()+interval '10 days'); select pg_sleep(3); commit;" > "$SP/c.a" &
sleep 1
run "select test.act(test.u('a1')); select admin_block_account(test.u('c3'),'C3');" > "$SP/c.b" &
run "select test.act(test.u('a1')); select admin_restrict_conversation(test.u('e6'),'C3');" > "$SP/c.c" &
wait
echo "  booking:  $(cat "$SP/c.a")"; echo "  block c3: $(cat "$SP/c.b")"; echo "  restrict: $(cat "$SP/c.c")"
echo "  after: sessions on e6=$(q "select count(*) from support_sessions where request_id=test.u('e6')"), c3 blocked=$(q "select count(*) from account_blocks where user_id=test.u('c3')"), e6 restricted=$(q "select restricted_at is not null from support_requests where id=test.u('e6')")"

echo "C4 volunteer b3 accepts blocked seeker c3's pending request e5 -> participant_unavailable"
echo "  accept: $(run "select test.act(test.u('b3')); select decide_support_request(test.u('e5'),true);")"
echo "C5 two admins block the same user at once -> one OK, one already_blocked"
run "begin; select test.act(test.u('a1')); select admin_block_account(test.u('b3'),'C5 a1'); select pg_sleep(2); commit;" > "$SP/c.a" &
sleep 0.5; echo "  a2: $(run "select test.act(test.u('a2')); select admin_block_account(test.u('b3'),'C5 a2');")"; wait
echo "  a1: $(cat "$SP/c.a")"; echo "  events for b3: $(q "select count(*) from account_moderation_events where user_id=test.u('b3')")"
echo "C6 reactivate and block the same user at once -> serialised, state matches last committed action"
run "begin; select test.act(test.u('a1')); select admin_reactivate_account(test.u('b3')); select pg_sleep(2); commit;" > "$SP/c.a" &
sleep 0.5; echo "  a2 block: $(run "select test.act(test.u('a2')); select admin_block_account(test.u('b3'),'C6 a2');")"; wait
echo "  a1 reactivate: $(cat "$SP/c.a")"
echo "  b3 blocked now=$(q "select count(*) from account_blocks where user_id=test.u('b3')"), events=$(q "select string_agg(action,',' order by created_at) from account_moderation_events where user_id=test.u('b3')")"
if [ -n "$PGLOG" ]; then echo "deadlocks detected during run: $(( $(grep -ci "deadlock detected" "$PGLOG") - before ))"; else echo "set PGLOG to count deadlocks"; fi
