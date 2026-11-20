# Production deployment: account blocking, visibility and appeals

> [!WARNING]
> **DEPLOYED TO PRODUCTION ON 2026-10-21 — DO NOT RE-RUN.**
> The main Ma'ak Supabase project already has, in this order:
> 1. `supabase/migrations/20261021_account_blocking.sql`
> 2. `supabase/production/20261021_production_compat.sql`
> 3. `supabase/migrations/20261022_account_moderation_visibility.sql`
> 4. `supabase/migrations/20261023_account_appeals.sql`
> 5. `supabase/migrations/20261024_cancel_with_blocked_participant.sql`
>
> All verification checks and the final production compatibility checks passed,
> including all seven columns of
> `supabase/checks/20261024_cancel_with_blocked_participant_verify.sql`.
> Do not run any of these files, the rollbacks, or the optional grant on production
> again without a team decision.

### 20261024: cancel with a blocked participant (deployed 2026-10-21)

`supabase/migrations/20261024_cancel_with_blocked_participant.sql` fixes a
confirmed production bug: a help seeker could not cancel their own pending
support request when the volunteer was blocked (`participant_unavailable`). It
only replaces `guard_maak_blocked_participants()`, adding one exception
(pending → canceled, by the request's own seeker); no data, other functions,
policies or grants changed. It was applied once in the SQL Editor on
2026-10-21, and the post-deployment run of
`supabase/checks/20261024_cancel_with_blocked_participant_verify.sql` returned
`t` for every column.

- **Verify (read-only, safe at any time):** run the 20261024 verify script;
  every column must be `t`. `guard_fixed = f` means the guard is no longer the
  20261024 version (for example after a re-run of 20261021 or a rollback).
- **Rollback:** `supabase/rollbacks/20261024_cancel_with_blocked_participant_rollback.sql`
  restores the 20261021 guard exactly; canceled requests stay canceled. Roll it
  back first if 20261023, 20261022 or 20261021 is ever rolled back. Afterwards
  the verify script shows `guard_fixed = f` and `guard_was_20261021 = t`.
- Tested in `tests/database/cancel_blocked_participant/`.

## Warnings for the production database

- **Re-running 20261021 breaks production silently.** It replaces
  `maak_matching_context()` without production's open-request rule, grants
  `my_support_sessions()` to `authenticated`, and overwrites functions that
  20261022 (`admin_list_accounts`, `admin_blocked_accounts`,
  `admin_account_moderation_history`) and 20261023 (`admin_block_account`,
  `admin_account_moderation_history`) redefined, and it restores the old
  `guard_maak_blocked_participants()` that 20261024 fixed. Re-running 20261022
  likewise overwrites 20261023's `admin_account_moderation_history`. If either
  happens, re-apply every later step of the sequence above in order, then run
  `verify_production_compat.sql` and the 20261022/20261023/20261024 verify
  scripts.
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
| `20261021_account_blocking_production_rollback.sql` | Emergency rollback of 20261021 + patch, only after rolling back 20261024, 20261023 and 20261022 |
| `optional_grant_my_support_sessions.sql` | Not part of the deployment; a separate team decision |

Read-only checks that remain safe on production: `verify_production_compat.sql`,
`../checks/20261022_account_moderation_visibility_verify.sql`,
`../checks/20261023_account_appeals_verify.sql` and
`../checks/20261024_cancel_with_blocked_participant_verify.sql`. The smoke tests in
`../checks/` call the admin RPCs and then roll back, so they write nothing;
they need an admin's profile ID in place of their placeholder.

## Fresh database (not production)

**Do not apply `supabase/migrations/` in filename order.** Two files share the
version `20261021` (`20261021_account_blocking.sql` and
`20261021_matching_connections.sql`), and filename order runs the team's
`20261021090000_…` and `20261021100000_…` files *before* account blocking but
`20261021_matching_connections.sql` *after* it. That replaces
`maak_matching_context()` without the blocking checks (blocked seekers can match,
blocked volunteers are offered), and account blocking re-grants
`my_support_sessions()`, which `20261021090000_chat_reads_remove_booking.sql`
revoked when the booking feature was removed.

20261021 also requires the conversation restriction columns
(`support_requests.restricted_at`, `restricted_by`, `restriction_reason`), which
exist in production but are created by no file in the repository. A database
built only from the repository needs them first.

For a new database built from the repository schema, apply in this order:

1. The existing migrations up to `20261020_profile_repair.sql`, then the team's
   `20261021090000_chat_reads_remove_booking.sql`,
   `20261021100000_registration_email.sql` and
   `20261021_matching_connections.sql`
2. `supabase/migrations/20261021_account_blocking.sql`, then immediately
   `supabase/production/20261021_production_compat.sql` (despite its name, it
   is needed on any database that has the team migrations from step 1: it
   restores the open-request matching rule with the blocking checks and the
   revoked `my_support_sessions()`), then `verify_production_compat.sql`
3. `supabase/migrations/20261022_account_moderation_visibility.sql`, then its verify
4. `supabase/migrations/20261023_account_appeals.sql`, then its verify
5. `supabase/migrations/20261024_cancel_with_blocked_participant.sql`, then its verify

On such a database `verify_production_compat.sql` reports
`production_rpcs_untouched = f` unless the conversation restriction functions
are the production versions. Rollbacks: `supabase/rollbacks/` (24, 23, then 22), then
this folder's production rollback for 20261021 + patch. A database copied from
production needs the production sequence at the top of this file, starting with
`precheck_production.sql`.

`optional_grant_my_support_sessions.sql`: the missing grant is intentional.
`20261021090000_chat_reads_remove_booking.sql` revoked it when the booking
feature was removed, so do not run that script unless booking is brought back.

Tested in `tests/database/` (`production_compat/` for the production sequence).
