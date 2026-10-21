# Production deployment: account blocking, visibility and appeals

> [!WARNING]
> **DEPLOYED TO PRODUCTION ON 2026-10-21 — DO NOT RE-RUN.**
> The main Ma'ak Supabase project already has, in this order:
> 1. `supabase/migrations/20261021_account_blocking.sql`
> 2. `supabase/production/20261021_production_compat.sql`
> 3. `supabase/migrations/20261022_account_moderation_visibility.sql`
> 4. `supabase/migrations/20261023_account_appeals.sql`
>
> All verification checks and the final production compatibility checks passed.
> Do not run any of these files, the rollbacks, or the optional grant on production
> again without a team decision.

## Warnings for the production database

- **Re-running 20261021 breaks production silently.** It replaces
  `maak_matching_context()` without production's open-request rule, grants
  `my_support_sessions()` to `authenticated`, and overwrites functions that
  20261022 (`admin_list_accounts`, `admin_blocked_accounts`,
  `admin_account_moderation_history`) and 20261023 (`admin_block_account`,
  `admin_account_moderation_history`) redefined. Re-running 20261022 likewise
  overwrites 20261023's `admin_account_moderation_history`. If either happens,
  re-apply every later step of the sequence above in order, then run
  `verify_production_compat.sql` and the 20261022/20261023 verify scripts.
- **Migration history may not reflect these changes.** They were applied
  through the Supabase SQL Editor, so `supabase_migrations.schema_migrations`
  may not list them. Do not run `supabase db push` or
  `supabase migration repair` against production until the team has
  reconciled the history and verified the existing migration state. A push
  would re-run the migrations and would not apply the compat patch, which
  lives outside `supabase/migrations/`.
- **Older setup scripts are not safe on production.** `supabase_schema.sql`
  and `APPLY_UPDATES.sql` redefine functions that the blocking migration
  protects (for example `can_send_maak_message`, `browse_volunteers`,
  `maak_matching_context`). Never execute them on production without review.
- `precheck_production.sql` now reports `nothing_installed_yet = f` on
  production. That is expected; it was a pre-deployment check only.

## Files in this folder

Files here are for the **main Supabase project only**. They adapt the tested
migrations to production, which differs from the repository in
`maak_matching_context()` (open-request rule) and in `my_support_sessions()`
privileges (no EXECUTE for `authenticated`).

| File | Use |
|---|---|
| `precheck_production.sql` | Read-only check run before the 2026-10-21 deployment. Kept as a record |
| `20261021_production_compat.sql` | Applied on 2026-10-21 right after `20261021_account_blocking.sql` |
| `verify_production_compat.sql` | Read-only. Safe to run on production at any time; every column must be `t`. Replaces `checks/20261021_account_blocking_verify.sql` there |
| `20261021_account_blocking_production_rollback.sql` | Emergency rollback of 20261021 + patch, only after rolling back 20261023 and 20261022 |
| `optional_grant_my_support_sessions.sql` | Not part of the deployment; a separate team decision |

Read-only checks that remain safe on production: `verify_production_compat.sql`,
`../checks/20261022_account_moderation_visibility_verify.sql` and
`../checks/20261023_account_appeals_verify.sql`. The smoke tests in
`../checks/` call the admin RPCs and then roll back, so they write nothing;
they need an admin's profile ID in place of their placeholder.

## Fresh database (not production)

For a new local or test database built from the repository schema (for example
a new test project), the compat patch and this folder's other files do **not**
apply. Use the repository sequence, after the existing migrations:

1. `supabase/migrations/20261021_account_blocking.sql`, then
   `supabase/checks/20261021_account_blocking_verify.sql`
2. `supabase/migrations/20261022_account_moderation_visibility.sql`, then its verify
3. `supabase/migrations/20261023_account_appeals.sql`, then its verify

Rollbacks for that sequence are in `supabase/rollbacks/` (23, then 22, then 21).
A database copied from production instead needs the production sequence at the
top of this file, starting with `precheck_production.sql`.

Tested in `tests/database/` (`production_compat/` for the production sequence).
