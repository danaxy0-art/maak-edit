# Production compatibility tests

Tests the production deployment sequence on a **throwaway local PostgreSQL**
server whose functions are the definitions exported from the main Supabase
project (2026-10-21), with production's grants, triggers, Realtime tables and
data shape (4 active conversations, no pending requests, no restrictions, no
upcoming sessions). Never run against Supabase.

Sequence under test: `supabase/migrations/20261021_account_blocking.sql` →
`supabase/production/20261021_production_compat.sql` →
`supabase/migrations/20261022_account_moderation_visibility.sql` →
`supabase/migrations/20261023_account_appeals.sql`.

| File | Purpose |
|---|---|
| `05_production_definitions.sql` | The 9 exported production functions verbatim, restriction columns, and `my_support_sessions()` without EXECUTE for `anon`/`authenticated` (precheck Q4), and the 7 `support_requests` constraints exactly as reported by production |
| `12_seed_production.sql` | Shapes the shared seed like production (precheck Q7) |
| `13_baseline.sql` | Checksum of all user data before deployment; helpers |
| `25_tests_production.sql` | 48 checks: data unchanged, production constraints present and enforced, the 3 production triggers still work, Realtime unchanged, matching keeps the open-request rule, conversation restrictions (messaging and booking refused, `admin_restrict_conversation`, `admin_support_requests`), Flutter response fields, preserved `my_support_sessions` privileges, no access gained by blocked users |
| `run_tests.sh` | Prechecks, sequence, verifications, functional tests, rollback with exact comparison, re-application, and the existing suites on production definitions |

```bash
PSQL=psql PGPORT=54329 bash tests/database/production_compat/run_tests.sh
```

Section 5 runs the existing suites against production definitions. Their
expected differences are production behaviour: `my_support_sessions()` is not
executable by `authenticated`, matching excludes volunteers with open requests,
and restricting an already-restricted conversation is refused. Check 84 of the
original suite clears `restricted_at` but not `restriction_reason`, which the
production constraint rightly refuses; checks 91 and 101 then fail because the
conversation stays restricted. With that update also clearing the reason, all
three pass.
