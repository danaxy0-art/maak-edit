# Session notifications, device-time session times, member profiles

## Database setup

Run these in the Supabase SQL editor, in this order. Both can be run more than once. If you already ran an earlier copy of the first file, run it again to upgrade.

1. `supabase/migrations/20261127000000_session_notifications.sql`
2. `supabase/migrations/20261127010000_member_profiles.sql`

Rollbacks are in `supabase/rollbacks/` under the same names.

## 1. Session notifications are shown and pushed

- **The problem:** session scheduling stored its notifications with kind `session`. That kind belonged to the old booking feature, which was removed. The app hides it (`notificationStream`) and the push trigger skips it, so nobody saw these notifications.
- **New kind:** session request, confirmation, decline, cancellation and reschedule notifications now use kind `support_session`. They show in the notification list and the pop-up banner, and the existing push trigger sends them with no trigger change. Tapping one opens **Sessions**.
- **Earlier notifications:** older scheduling notifications (those whose `reference_id` is a session booking) are moved to `support_session`. They appear in the app but aren't pushed again.
- **Old rows:** genuine old booking rows keep kind `session` and stay hidden.

## 2. Session times use each user's device time

- `maak_session_label` used to write `2026-11-30 15:00 UTC`.
- Session notifications, both the push and the in-app text, now show the time in the **recipient's** device time, for example `Mon 30 Nov 2026, 4:00 PM` for someone whose phone is on UTC+1.
- **How the app reports it:** `TimeZoneSync` sends the device's UTC offset (`DateTime.now().timeZoneOffset`) through `set_maak_utc_offset`. It does this when the member's app opens and each time the app comes back to the foreground, and only when the offset has changed. Offsets are stored in `member_time_zones`, which clients can't read.
- **How the database applies it:** `maak_session_label` now returns a placeholder. `maak_session_notify`, which knows the recipient, replaces it with the time at that person's offset. Razan's session functions are unchanged.
- **Unknown offset:** someone who hasn't opened the updated app yet gets Riyadh time, marked `(Riyadh time)`.
- **Older notifications:**
  - **Stored UTC times:** older notifications that still contain a UTC time are rewritten in the same way.
  - **When the text is fixed:** the text is written when the notification is sent. If someone later changes time zone, older notifications stay in the time zone they had then.
- **Daylight saving:** the offset is today's offset. For users in a country with daylight saving, a session booked across a clock change could show an hour off. Saudi Arabia doesn't change its clocks. Making this exact would need a time zone plugin such as `flutter_timezone`.
- Both session helpers now include `pg_temp` in their `search_path`.

## 3. Health Library tables

These were already in the repo: `20261126000000_article_management_comments.sql` creates `articles`, `illness_types`, `article_likes`, `saved_articles` and `article_comments`. `tests/database/article_comments_test.mjs` builds them on an empty database and on a production-like one.

## 4. Profiles from chats and comments

You can open someone's profile by tapping:
- their photo or name in the chat header (the header now shows their photo), or
- the photo or name of a Health Library comment's author.

Who sees what is decided by `get_maak_member_profile` (security definer):

| Viewer | Volunteer (approved) | Help seeker |
|---|---|---|
| Any active member | Name, photo, role, rating/badge, lived experience, conditions, language | Name, photo, role only |
| Someone they've had a support request with | Same | Also conditions and language |
| The member themselves, admins | Everything | Everything |

- **Unavailable profiles:** admin accounts, restricted accounts, and volunteers who aren't approved show "This profile is not available". An unapproved volunteer is still visible to themselves, to admins, and to people they've had a support request with.
- **Requesting support:** a help seeker viewing an approved volunteer gets **Request support or a session**, which opens the existing volunteer page.

## Tests

```
cd tests/database && npm install
node session_notifications_test.mjs   # 11 checks
node member_profiles_test.mjs         # 8 checks
```

## Changed files

- **New:**
  - `lib/frontend/redesign/member_profile.dart`
  - `lib/backend/services/time_zone_sync.dart`
  - the two migrations, their rollbacks, and their tests
- **Updated:**
  - `notifications.dart`, `shell.dart`: open Sessions for `support_session`; the shell also reports the time zone
  - `support.dart`: chat header photo and profile link
  - `article_comments.dart`: comment author links
  - `feedback.dart`: "profile not available" message
  - `supabase_service.dart`, `push_notification_service.dart`: comments only
