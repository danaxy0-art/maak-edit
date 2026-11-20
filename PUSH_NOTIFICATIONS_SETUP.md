# Push notifications (FCM) — setup

## What sends a push

| Event | Who gets it | Source |
|---|---|---|
| Chat message | the other person in the chat (volunteer or help seeker) | `notify_maak_message` → `notifications` row |
| Volunteer application approved / not approved | the volunteer | `review_volunteer_application` → `notifications` row |
| New volunteer application (and re-application) | every admin | `save_maak_profile` → `notifications` row |
| New support request (and cancellation) | the volunteer | `request_peer_support` / `cancel_support_request` → `notifications` row |
| Support request accepted / declined | the help seeker | `decide_support_request` → `notifications` row |
| Account restricted | the restricted user | trigger on `account_blocks` insert |
| Account reactivated | the user | `admin_reactivate_account` / appeal approval → `notifications` row |
| New account appeal | every admin | trigger on `account_block_appeals` insert (push only) |
| New matching volunteer | each help seeker who now sees that volunteer in Find a volunteer | `notify_maak_new_matches` → `notifications` row (kind `match`) |

**Appeals** are push-only, with no bell entry. The person appealing is restricted, and restricted
callers can't write notification rows. Admins already see pending appeals on the overview.

**New matches** use the same rules as Find a volunteer:
- The volunteer is approved, not restricted, has AI matching on, and shares an active condition
  with the seeker. "Other" doesn't count.
- The seeker has AI matching on, isn't restricted, and has no open request with that volunteer.

Matches are checked when a volunteer is approved, turns AI matching on, adds a condition, or is
reactivated. Each seeker is told about a given volunteer only once (`match_notifications_sent`).
Seekers with no approved condition, who only get general suggestions, aren't notified.

Every new `notifications` row becomes a push, so any future event that inserts one is
pushed automatically. A restricted account receives only account-status pushes.

**Chat notifications** show the sender's name as the title and the message text as the body
(cut to 200 characters). Media shows an icon plus its caption, or "📷 Photo", "🎤 Voice message"
or "🎥 Video" when there's no caption. If a message is deleted for everyone, or hidden by the
recipient, the stored notification text changes to "This message was deleted." A push that already
reached a phone can't be recalled.

**Request notifications** name the other person: "New support request from Dana", "Sara accepted
your support request", "Sara declined your support request", "Dana canceled their support request".

The restriction push never includes the reason.

Tapping a push opens: the conversation (chat), Requests or Journey (requests), Find a volunteer
(new match), or the admin Appeals page (appeal). For an application
decision, restriction or reactivation, the app reloads from the start so the user sees the right screen.

## One-time setup

1. **Database**: run these in the SQL editor, in order:
   - `supabase/migrations/20261106000000_push_notifications.sql`
   - `supabase/migrations/20261106010000_appeal_and_match_notifications.sql`
   - `supabase/migrations/20261106020000_detailed_chat_request_notifications.sql` (adds sender names,
     message text and request names)

2. **Vault secrets** — in the SQL editor (pick any long random string for the secret):
   ```sql
   select vault.create_secret('https://<project-ref>.supabase.co', 'maak_project_url');
   select vault.create_secret('<long-random-string>', 'maak_push_secret');
   ```

3. **Firebase service account** — Firebase console → Project settings → Service accounts →
   *Generate new private key*. Keep the JSON file private and don't commit it.

4. **Edge Function secrets and deploy**:
   ```bash
   supabase secrets set PUSH_WEBHOOK_SECRET='<same long-random-string>'
   supabase secrets set FCM_SERVICE_ACCOUNT="$(cat path/to/service-account.json)"
   supabase functions deploy send-push --no-verify-jwt
   ```

5. **App** — `flutter pub get`, then run on a real device or an emulator with Google Play.
   Sign in and allow notifications.

## Checking it works

- `select * from public.device_tokens;` should show a row after you sign in on a device.
- `select * from net._http_response order by created desc limit 5;` shows recent calls to send-push.
- Edge Function logs show `fcm_send_failed` with Google's error if FCM rejects a send.
- Database tests: `cd tests/database && npm install && node push_notifications_test.mjs && node appeal_match_notifications_test.mjs && node detailed_notifications_test.mjs`.

## Notes

- While the app is open, Android doesn't show the system notification. Volunteers still get the
  existing in-app banner, and everyone gets the bell badge.
- iOS isn't set up in Firebase for this project yet (`firebase.json` only lists Android and web).
  To add it, run `flutterfire configure` for iOS, upload an APNs key in Firebase, and enable the
  Push Notifications and Background Modes → Remote notifications capabilities in Xcode.
