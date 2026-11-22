# Session scheduling (Razan) — files added and changed

Every line added to an existing file is wrapped in `ADDED BY RAZAN` comments.

## New files (only mine)
| File | What it is |
|---|---|
| `supabase/migrations/20261121100000_session_scheduling.sql` | Tables `volunteer_time_slots`, `session_bookings` and the functions for all 5 stories |
| `supabase/rollbacks/20261121100000_session_scheduling_rollback.sql` | Removes only the objects above |
| `lib/frontend/redesign/sessions.dart` | Screens: `AvailabilityPage`, `VolunteerSlotsPage`, `SessionsPage` |
| `tests/database/session_scheduling_test.mjs` | 41 database checks |
| `test/session_scenario_screens_test.dart` | 15 checks that draw the full volunteer / help seeker story step by step |
| `test/session_scheduling_test.dart` | 11 Flutter widget checks (set `MAAK_SCREENSHOTS=1` and `--update-goldens` to also write screenshots) |

## Existing files with a small marked addition
| File | Added |
|---|---|
| `lib/backend/services/supabase_service.dart` | 9 methods at the end of the class (block `ADDED BY RAZAN: session scheduling`) |
| `lib/frontend/redesign/feedback.dart` | Friendly messages for the new error codes |
| `lib/frontend/redesign/home.dart` | Import + one "Sessions" row in Quick actions |
| `lib/frontend/redesign/support.dart` | Import + one "Available times" row on the volunteer profile page |

## Apply order
1. Run the migration once in the Supabase SQL Editor (needs `20261021_account_blocking.sql`, already in the project).
2. Run `dart format`, `flutter analyze`, `flutter test`.
3. Home and volunteer-profile golden images change (one extra row): refresh with `flutter test --update-goldens` for `home_screens_test.dart` and `seeker_screens_test.dart` only, after checking the diff.

## Rules (agreed)
- A request is `pending` until the volunteer accepts; only then it is confirmed.
- Volunteer on a pending request: Accept / Decline only. Reschedule / Cancel appear once it is confirmed.
- Decline turns down only that help seeker: the time opens again for others, and that help seeker cannot request the same time again.
- Volunteer cancel / volunteer-side reschedule withdraws the old time (they are not free then).
- Day of the session: `Today`/`Tomorrow` + `Starts in …` (under 24 h), `Happening now` (no buttons), `Completed`, `Expired` for an unanswered request whose time passed.
- Not built: reminder notification before the session (needs a scheduled server job) and a call/chat button on the session card.
