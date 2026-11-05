# Account moderation v2 database tests

Tests for `supabase/migrations/20261022_account_moderation_visibility.sql`
(Migration A: admin visibility, verified admin labels) and
`supabase/migrations/20261023_account_appeals.sql` (Migration B: appeals), their
rollbacks (`supabase/rollbacks/`) and verification checks (`supabase/checks/`).

Run only against a **throwaway local PostgreSQL** server, never Supabase. The
scripts create and drop databases named `maak_v2*`. They reuse the platform stub,
live-feature approximation and seed from `../account_blocking/`.

| File | Purpose |
|---|---|
| `11_seed_v2.sql` | Admins with: no name and no username (the confirmed `maak-testing` case), a chosen username only, an auto-generated username only, and one deleted during tests. Blocks made with the original RPC **before** the migrations, so the block-event backfill is exercised (including a block, reactivation and re-block) |
| `15_harness.sql` | Runs checks as a given API role and JWT subject |
| `21_tests_v2.sql` | 114 checks: hidden admins, own-row `profiles_read`, labels, backfill and link integrity, appeal lifecycle and limits, ownership, immutability, deletion cascade and both trigger orders, redaction, grants, existing admin features |
| `30_concurrency_v2.sh` | Parallel sessions: double submit, two admins deciding, decision vs reactivation, submit vs reactivation (both orders), third-attempt race |
| `run_tests.sh` | Everything above, plus backfill-refusal cases, exact rollback comparisons, roll-forward, and the original 138-check suite as a regression |

```bash
PSQL=psql PGPORT=54329 PGLOG=/tmp/maak_pg.log bash tests/database/account_moderation_v2/run_tests.sh
```

Expected: `114 | 0`; all verification columns `t`; three backfill cases refused
with nothing applied; rollbacks identical; `deadlocks detected during run: 0`.
The original suite reports `135 | 3`. Those three differences are intended:
admins are no longer listed in Manage Accounts (2 checks), and TRUNCATE of the
moderation history is now refused earlier, by the foreign keys that reference it.
