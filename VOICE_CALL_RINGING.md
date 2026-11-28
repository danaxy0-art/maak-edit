# Voice calls: ringing on the phone, and using the app during a call

## What changed

### 1. Calls ring when Ma'ak is closed or in the background (Android)
Before this change, starting a call only wrote a `voice_calls` row. The other phone noticed it only by polling once a second while the app was open, so nothing rang when the app was closed.

- **The push:** a new call sends a push to the person being called. Its title is "Incoming voice call" and its body is "Sara is calling you. Open Ma'ak to answer."
- **The ringtone channel:** the push goes on a new **`maak_calls`** channel, created in `MainActivity.kt`. That channel plays the phone's **ringtone** at ringtone volume, vibrates like a call, and shows on the lock screen.
- **Answering:** tapping the notification opens Ma'ak, and the call appears within a second, ready to answer.
- **No late rings:** the push expires after 45 seconds. Calls stop ringing after 60 seconds anyway, so a delayed push can't ring for a call that's already over.
- **Missed calls:** if the caller hangs up, or nobody answers in time, the person gets **"Missed voice call"** instead. It replaces the ringing notification on the phone (same tag) and appears in the notification list. Tapping it opens the conversation, so they can call back. Declining is the person's own choice and sends nothing.
- **Clearing the shade:** answering, declining, or the call ending in the app removes the ringing notification from the phone.

### 2. Ringing while the app is open
- A push isn't shown while the app is in the foreground, so the app plays its own ring instead, `assets/sounds/ringtone.wav`, in a loop.
- On Android it uses ringtone volume and respects silent mode.
- It stops as soon as the call is answered, declined or over.

### 3. The app stays usable during an incoming or ongoing call
- **Before:** a full-screen panel covered the whole app until the call was answered or declined.
- **Incoming calls:** now shown as a banner at the top with the caller's name, **Accept** and **Decline**. Everything underneath keeps working. The ⌃ button shrinks the banner to a small pill that still has Accept and Decline.
- **Ongoing calls:** they open full screen as before. **Minimise** (⌄ at the top left, or "Use the app during the call") turns the call into a green bar at the top with the other person's name, the call time and an end button. Tap the bar to go back to the call.
- **Ended calls:**
  - **Unanswered incoming calls** just disappear, and the missed-call notification covers them.
  - **Calls you took part in** show how they ended, as before, so you can still report a problem.

## Setup

1. **Database:** run `supabase/migrations/20261127030000_voice_call_ringing.sql` in the Supabase SQL editor. It's safe to run twice, and the rollback is in `supabase/rollbacks/`.
2. **Edge Function:** redeploy it with `supabase functions deploy send-push`. Until you do, call pushes arrive on the normal Ma'ak channel with the usual short notification sound.
3. **App:** build and install the new version, then open it once. That creates the ringtone channel; until then, calls arrive on the normal channel.

## Limits

- **iOS:** the call push arrives as a time-sensitive notification with the normal sound, not a full ringing call screen. A real ringing call screen on iOS needs Apple's CallKit and VoIP pushes, which is a separate piece of work.
- **Ringing length:** Android plays the channel's ringtone once, for the length of the ringtone file (usually 15–30 seconds). It doesn't loop until answered. Looping, Answer/Decline buttons on the notification, and a full-screen call on the lock screen would need a background message handler and `USE_FULL_SCREEN_INTENT`. Android 14 also requires the user to allow that permission.
- **Phone makers:** some (for example Xiaomi and Huawei) stop pushes to apps the user has swiped away or put in battery saving. In that case the call shows the next time the app opens.

## Tests

```
cd tests/database && npm install
node voice_call_ringing_test.mjs   # 9 checks
node voice_calls_test.mjs          # 18 existing checks, unchanged
```

## Changed files

- **New:**
  - `lib/backend/calls/call_ringer.dart`
  - `assets/sounds/ringtone.wav`: generated, a 3-second double ring
  - the migration, its rollback and its test
- **Updated:**
  - `lib/frontend/calls/voice_calls.dart`: banner, minimised bar, peer name
  - `supabase/functions/send-push/index.ts`: calls channel, tag, expiry
  - `MainActivity.kt`: ringtone channel
  - `pubspec.yaml`: the asset
  - `notifications.dart` and `shell.dart`: open the chat from a missed call
  - `push_notification_service.dart`: ignore a tapped ringing push, because the call appears by itself
