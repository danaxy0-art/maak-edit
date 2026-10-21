# Account blocking database tests

Tests for `supabase/migrations/20261021_account_blocking.sql`, its rollback
(`supabase/rollbacks/`) and its post-deploy checks (`supabase/checks/`).

Run them only against a **throwaway local PostgreSQL** server, never against
Supabase. They create and drop the databases `maak_test`, `maak_rb` and `maak_conc`.

## Files

| File | Purpose |
|---|---|
| `00_supabase_stub.sql` | Minimal Supabase platform: `anon`/`authenticated`/`service_role`, default grants, `auth.uid()`, `storage` |
| `05_live_only_approximation.sql` | The live-only conversation restriction feature (`restricted_at`), reconstructed from the reviewed live definitions. Not in Git otherwise. Update it if the live functions change. |
| `10_seed.sql` | Admins, seekers, volunteers, requests, messages and sessions |
| `20_tests.sql` | 138 functional checks: permissions, validation, bypass attempts, restrictions, maintenance, history, grants |
| `30_concurrency.sh` | Parallel sessions: block vs. write, booking vs. block vs. restriction, double block, block vs. reactivate |
| `run_tests.sh` | Runs everything, including the exact rollback comparison |

## Running

PostgreSQL 15 or newer. Start a disposable cluster, for example:

```bash
initdb -D /tmp/maak_pg -U postgres -A trust -E UTF8 --locale=C
pg_ctl -D /tmp/maak_pg -o "-p 54329 -c listen_addresses=127.0.0.1" -l /tmp/maak_pg.log -w start
PSQL=psql PGPORT=54329 PGLOG=/tmp/maak_pg.log bash tests/database/account_blocking/run_tests.sh
pg_ctl -D /tmp/maak_pg -m fast stop
```

Expected: `138 | 0` (passed | failed), all verification columns `t`, the
rollback reported as restoring every object, and `deadlocks detected during run: 0`.

On Windows, run from Git Bash with `PSQL="/c/Program Files/PostgreSQL/17/bin/psql.exe"`.
`run_tests.sh` sets `PGCLIENTENCODING=UTF8`; without it psql may read the Arabic
condition aliases in `20261018_condition_reviews.sql` as WIN1252 and fail.
