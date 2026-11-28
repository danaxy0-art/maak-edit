# Cancellation with a blocked participant (20261024)

Tests for `supabase/migrations/20261024_cancel_with_blocked_participant.sql`,
its rollback (`supabase/rollbacks/`) and verification (`supabase/checks/`).
Run only against a **throwaway local PostgreSQL** server, never Supabase.

The database is built like production on 2026-10-21: the team's 20261021
migrations, the exported production function definitions and production-shaped
data, then 20261021 → production compat patch → 20261022 → 20261023.

| File | Purpose |
|---|---|
| `05_before_fix.sql` | Reproduces the bug (rolled back) |
| `10_tests.sql` | 43 checks, against the exact production `cancel_support_request()` (from `../production_compat/05_production_definitions.sql`): the fix; repeating a cancellation (production returns without error and without a second notification); unauthorized cancellation (blocked volunteer, other seeker, the volunteer, a blocked seeker, anon); the guard exception stays narrow (volunteer, reopening, accepting, accepted conversations, immutable participants); existing blocking protections; the team's cancellation rules; production conversation restrictions; reactivation |
| `run_tests.sh` | Before/after, idempotency, verification, refusal of an unknown guard definition, rollback, re-application, full rollback chain, and the existing suites with the fix applied |

```bash
PSQL=psql PGPORT=54329 bash tests/database/cancel_blocked_participant/run_tests.sh
```

Section 5 runs the existing suites; their differences are the documented ones.
The production compat suite is also run on the database with the team
migrations, where 3 booking checks fail because `20261021090000_chat_reads_remove_booking.sql`
revoked `book_support_session()`.
