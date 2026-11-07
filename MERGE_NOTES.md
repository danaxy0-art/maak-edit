# Merge notes: your version + the other version

The project is on the other version's latest commit (`a028b09`, branch
`redesign/home-foundation`), with your version's changes on top, uncommitted. Review them with
`git status` / `git diff`, then commit.

## What came from where

**Other version (already committed):**
- Message reports
- Admin report management: a **Message reports** card on the admin Overview, plus the report
  details page
- Restricted conversations: an admin can end a reported conversation, and members see why
- The in-app notification banner for both help seekers and volunteers
- Send validation in the chat

**Your version (uncommitted):**
- Push notifications for all events, with names and message text
- Appeal and new-match notifications
- Profile pictures, shared with other members
- The application and account filters
- The Appeals tab in the admin bar
- The instant redirect to the restricted screen
- The one-push-per-restriction fix
- The chat changes: one Send button with media captions, no bottom bar inside a chat, a
  reopened chat updating live, and a fixed Messages icon
- The trimmed matching page

## How the overlapping parts were combined

| Where | Result |
|---|---|
| Chat screen (`support.dart`) | Their admin restriction (`_restricted`, `_closed`, reason banner) and your media draft/caption send, live reopen, full-screen chat. Restricting a chat also clears a waiting attachment. |
| Opening a notification (`shell.dart`, `notifications.dart`) | `message`, `chat_reopen` and their new `restricted` kind all open the conversation full-screen; `restricted` has its own icon in the list. |
| Admin (`admin.dart`) | Your Appeals tab and their Message reports card on Overview both kept. |
| Line endings | Your copy had Windows (CRLF) line endings in 219 files, which caused false whole-file conflicts. They are now Unix (LF) like the rest of the repo. No content changed. |

Pushes: when an admin ends a reported conversation, both members get a **push** too (kind
`restricted`), through the existing notification trigger. No extra setup needed.

## Database migrations, in order

Run any you haven't run yet, in this order (SQL editor: paste the whole file and run):

1. `20261105_message_reports.sql` (other version)
2. `20261106000000_push_notifications.sql`
3. `20261106010000_appeal_and_match_notifications.sql`
4. `20261106020000_detailed_chat_request_notifications.sql`
5. `20261106100000_admin_report_management.sql` (other version)
6. `20261107000000_profile_pictures.sql`
7. `20261107010000_shared_profile_pictures.sql`
8. `20261107020000_single_restriction_push.sql`
9. `20261107030000_appeal_and_block_fixes.sql`

All are repeatable. Check what's installed with
`supabase/production/check_notification_and_profile_changes.sql`. The reports feature has its own
check, `supabase/checks/20261106100000_admin_report_management_verify.sql`.

## Tests

- **Database:** all 17 suites from both versions pass, plus `tests/database/combined_features_test.mjs`,
  which installs both feature sets together and checks where they meet.
- **Flutter:** not run in this merge, because Flutter isn't available here. Run `flutter analyze`
  and `flutter test`. Expect to update:
  - goldens: `admin_overview` (both versions changed it) and `admin_applications`
  - `test/account_appeals_test.dart`: Appeals moved to its own tab
  - `test/seeker_screens_test.dart`: the matching test was already out of date
