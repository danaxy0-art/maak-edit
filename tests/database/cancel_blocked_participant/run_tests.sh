#!/usr/bin/env bash
# Tests for 20261024_cancel_with_blocked_participant.sql on a THROWAWAY local server,
# never Supabase. Builds a production-like database (team migrations, exported
# production definitions, 20261021 -> compat patch -> 20261022 -> 20261023), then
# tests the fix, its verification, rollback, re-application and the existing suites.
# Usage from the repo root:
#   PSQL=psql PGPORT=54329 bash tests/database/cancel_blocked_participant/run_tests.sh
export PGCLIENTENCODING=UTF8
HERE="$(cd "$(dirname "$0")" && (pwd -W 2>/dev/null || pwd))"; ROOT="$(cd "$HERE/../../.." && (pwd -W 2>/dev/null || pwd))"
T="$ROOT/tests/database/account_blocking"; V="$ROOT/tests/database/account_moderation_v2"; PC="$ROOT/tests/database/production_compat"
P="${PSQL:-psql}"; PORT="${PGPORT:-54329}"; M="$ROOT/supabase/migrations"; PR="$ROOT/supabase/production"
FIX="$M/20261024_cancel_with_blocked_participant.sql"; RBFIX="$ROOT/supabase/rollbacks/20261024_cancel_with_blocked_participant_rollback.sql"
VERIFY="$ROOT/supabase/checks/20261024_cancel_with_blocked_participant_verify.sql"
pg(){ "$P" -h 127.0.0.1 -p "$PORT" -U postgres -X "$@"; }
apply(){ pg -d "$1" -q -v ON_ERROR_STOP=1 -f "$2" >/dev/null 2>"$HERE/.step.err"; }
must(){ apply "$1" "$2" || { echo "APPLY FAILED: $2"; grep ERROR "$HERE/.step.err"; exit 1; }; }
q(){ pg -d "$1" -At -F' ' -c "$2"; }
fp(){ q "$1" "select md5(btrim(regexp_replace(prosrc,'[[:space:]]+',' ','g'))) from pg_proc where proname='guard_maak_blocked_participants'"; }
# Production-like database as of 2026-10-21, with the team migrations and the deployed sequence.
prod(){ pg -q -c "drop database if exists $1;" -c "create database $1;" >/dev/null 2>&1
  for f in "$T/00_supabase_stub.sql" "$ROOT/supabase_schema.sql" "$M/20261018_matching.sql" "$M/20261018_condition_reviews.sql" \
    "$M/20261020_profile_repair.sql" "$M/20261021090000_chat_reads_remove_booking.sql" "$M/20261021100000_registration_email.sql" \
    "$M/20261021_matching_connections.sql" "$PC/05_production_definitions.sql" "$T/10_seed.sql" "$PC/12_seed_production.sql" "$PC/13_baseline.sql" \
    "$M/20261021_account_blocking.sql" "$PR/20261021_production_compat.sql" "$M/20261022_account_moderation_visibility.sql" \
    "$M/20261023_account_appeals.sql" "$V/15_harness.sql"; do must "$1" "$f"; done; }
results(){ grep "| FAIL" "$1" | sed 's/^/   /'; echo "   $(tail -3 "$1" | head -1)"; }

echo "1. Before the fix (production as deployed)"
prod cb_pre; echo "   verify before: $(pg -d cb_pre -At -F' ' -f "$VERIFY")  (guard_fixed f expected; guard_was_20261021 t)"
pg -d cb_pre -q -v ON_ERROR_STOP=1 -P pager=off -f "$HERE/05_before_fix.sql" | grep -E "PASS|FAIL" | sed 's/^/   /'

echo "2. Apply the fix twice (idempotent), verify, functional tests"
prod cb; must cb "$FIX"; must cb "$FIX"
echo "   verify after: $(pg -d cb -At -F' ' -f "$VERIFY")"
echo "   production compat verify still: $(pg -d cb -At -F' ' -f "$PR/verify_production_compat.sql")"
echo "   20261023 verify still: $(pg -d cb -At -F' ' -f "$ROOT/supabase/checks/20261023_account_appeals_verify.sql")"
pg -d cb -q -v ON_ERROR_STOP=1 -P pager=off -f "$HERE/10_tests.sql" > "$HERE/.results.txt" 2>&1 || { echo "TEST SCRIPT FAILED"; tail "$HERE/.results.txt"; exit 1; }
results "$HERE/.results.txt"

echo "3. Refuses an unexpected guard definition (nothing applied)"
prod cb_odd; pg -d cb_odd -q -c "create or replace function public.guard_maak_blocked_participants() returns trigger language plpgsql security definer set search_path=public,pg_temp as \$\$ begin return new; end; \$\$;" >/dev/null
before=$(fp cb_odd); apply cb_odd "$FIX" && echo "   FAIL: applied over an unknown definition" || echo "   PASS: refused ($(grep -o 'unexpected definition[^;]*' "$HERE/.step.err")); guard unchanged: $([ "$(fp cb_odd)" = "$before" ] && echo yes || echo NO)"

echo "4. Rollback and re-application"
prod cb_rb; base=$(fp cb_rb); must cb_rb "$FIX"; must cb_rb "$RBFIX"
echo "   rollback restores the 20261021 guard exactly: $([ "$(fp cb_rb)" = "$base" ] && echo yes || echo NO)"
echo "   verify after rollback: $(pg -d cb_rb -At -F' ' -f "$VERIFY")  (guard_fixed f expected)"
pg -d cb_rb -q -v ON_ERROR_STOP=1 -P pager=off -f "$HERE/05_before_fix.sql" | grep -E "PASS|FAIL" | sed 's/^/   after rollback: /'
must cb_rb "$FIX"; echo "   re-applied: $(pg -d cb_rb -At -F' ' -f "$VERIFY")"
must cb_rb "$RBFIX"; must cb_rb "$ROOT/supabase/rollbacks/20261023_account_appeals_rollback.sql"
must cb_rb "$ROOT/supabase/rollbacks/20261022_account_moderation_visibility_rollback.sql"; must cb_rb "$PR/20261021_account_blocking_production_rollback.sql"
echo "   full chain 24 -> 23 -> 22 -> production 21 rollback: OK (guard removed: $(q cb_rb "select to_regprocedure('public.guard_maak_blocked_participants()') is null"))"

echo "5. Existing suites with the fix applied, each on the database its own runner builds"
# As production_compat/run_tests.sh prod() + deploy: no team migrations, so booking stays granted there.
base(){ pg -q -c "drop database if exists $1;" -c "create database $1;" >/dev/null 2>&1
  for f in "$T/00_supabase_stub.sql" "$ROOT/supabase_schema.sql" "$M/20261018_matching.sql" "$M/20261018_condition_reviews.sql" \
    "$M/20261020_profile_repair.sql" "$PC/05_production_definitions.sql" "$T/10_seed.sql"; do must "$1" "$f"; done; }
base cb_pc; for f in "$PC/12_seed_production.sql" "$PC/13_baseline.sql" "$M/20261021_account_blocking.sql" "$PR/20261021_production_compat.sql" \
  "$M/20261022_account_moderation_visibility.sql" "$M/20261023_account_appeals.sql" "$V/15_harness.sql" "$FIX"; do must cb_pc "$f"; done
pg -d cb_pc -q -v ON_ERROR_STOP=1 -P pager=off -f "$PC/25_tests_production.sql" > "$HERE/.pc.txt" 2>&1; echo "   production compat suite:"; results "$HERE/.pc.txt"
base cb_v2; for f in "$M/20261021_account_blocking.sql" "$PR/20261021_production_compat.sql" "$V/11_seed_v2.sql" \
  "$M/20261022_account_moderation_visibility.sql" "$M/20261023_account_appeals.sql" "$V/15_harness.sql" "$FIX"; do must cb_v2 "$f"; done
pg -d cb_v2 -q -v ON_ERROR_STOP=1 -P pager=off -f "$V/21_tests_v2.sql" > "$HERE/.v2.txt" 2>&1; echo "   account_moderation_v2 suite (expected: #53, my_support_sessions not granted in production):"; results "$HERE/.v2.txt"
base cb_old; for f in "$M/20261021_account_blocking.sql" "$PR/20261021_production_compat.sql" "$M/20261022_account_moderation_visibility.sql" "$M/20261023_account_appeals.sql" "$FIX"; do must cb_old "$f"; done
pg -d cb_old -q -v ON_ERROR_STOP=1 -P pager=off -f "$T/20_tests.sql" > "$HERE/.old.txt" 2>&1; echo "   original account_blocking suite (expected: 5 production differences + 3 documented 20261022/20261023 differences):"; results "$HERE/.old.txt"
# Booking on the production-like database (team migration 20261021090000 revoked it).
prod cb_team; must cb_team "$FIX"
pg -d cb_team -q -v ON_ERROR_STOP=1 -P pager=off -f "$PC/25_tests_production.sql" > "$HERE/.pc_team.txt" 2>&1
echo "   production compat suite on the database with the team migrations (booking revoked):"; results "$HERE/.pc_team.txt"
rm -f "$HERE/.step.err"
