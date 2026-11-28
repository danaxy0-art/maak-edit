# Ma’ak

Ma’ak is a peer support app for people living with chronic conditions. Help
seekers are matched with approved volunteers who live with a similar condition,
then talk to them by chat or voice call, book support sessions and read the
Health Library. Administrators review volunteer applications, reports and
appeals.

Built with Flutter (Android first, web for development) and Supabase.

## Features

**Help seekers**
- Registration with health conditions, preferred language and an optional AI
  matching consent.
- Volunteer matching (rule-based, with optional AI ranking) and support
  requests.
- Chat with photos, voice notes and video, message reporting and deletion.
- Voice calls, including ringing when the app is closed (Android).
- Support sessions: request, reschedule and cancel; add a session to the phone
  calendar; reminders 1 hour and 10 minutes before each confirmed session.
- Rate a volunteer after a completed conversation.
- Health Library articles with likes, saves and comments.
- Personal Health Planner: appointment and medication reminders.

**Volunteers**
- Application and approval flow.
- Accept support requests, chat, calls and sessions (same tools as above).
- Participation badges (beginner, intermediate, expert) and a public rating
  summary.

**Administrators**
- Overview, volunteer applications, condition name reviews.
- Account restriction, reactivation and appeals.
- Message and voice call reports, Health Library article management.
- Analytics dashboard.

## Project structure

```
lib/
  main.dart                 App start-up (Firebase, Supabase, notifications)
  backend/
    calls/                  Voice call signalling and ringing
    chat/                   Chat media rules
    services/               Supabase access, notifications, reminders, calendar
    validation/             Form rules
  frontend/
    redesign/               Current screens (shells, chat, sessions, admin …)
    auth/                   Sign-in, sign-up, password reset, account states
    design/ theme/ widgets/ Shared components and styling
supabase/
  migrations/               Database changes, applied in file name order
  functions/                Edge Functions (push, email, matching, calls …)
  checks/                   Read-only verification queries
  rollbacks/                Undo scripts for migrations
  production/               Notes and scripts for the deployed project
  templates/                Auth email templates
docs/                       Feature setup guides
test/                       Flutter unit, widget and screenshot (golden) tests
tests/                      Database (PGlite) and standalone Dart checks
supabase_schema.sql         Base schema (also loaded by the database tests)
```

## Getting started

Requirements: Flutter 3.47 or later (Dart 3.13+, as pinned by `pubspec.lock`),
Android SDK for Android builds.

```bash
flutter pub get
flutter run                 # a connected Android phone or emulator
flutter run -d chrome       # web, for development
```

The app connects to the team's Supabase project by default. To use another
project:

```bash
flutter run --dart-define=SUPABASE_URL=https://<project>.supabase.co \
            --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

## Backend setup

1. **Database (new project).** In the Supabase SQL Editor, run
   `supabase_schema.sql`, then the files in `supabase/migrations/` in file name
   order. Read each file's header first: it describes what the file changes
   and what it depends on. `supabase/checks/` holds read-only queries that
   verify a migration. On the existing team project, do not re-run the base
   schema or migrations that are already applied; see
   `supabase/production/README.md`.
2. **Auth emails.** In Authentication → Email Templates, use
   `supabase/templates/signup.html` for *Confirm signup* and
   `supabase/templates/recovery.html` for *Reset password*. Both must contain
   `{{ .Token }}`, so the email carries the code the app asks for. Check that
   the project's SMTP settings deliver mail.
3. **Admin account.** Register a normal account and verify its email, then in
   the SQL Editor (the app never lets an account change its own role):

   ```sql
   update public.profiles set role = 'admin'
   where id = (select id from auth.users where email = '<admin email>');
   ```
4. **Edge Functions.** Deploy each function, for example
   `npx supabase functions deploy match-volunteers`, and set the secrets:

   | Secret | Used by |
   |---|---|
   | `FCM_SERVICE_ACCOUNT`, `PUSH_WEBHOOK_SECRET` | `send-push` |
   | `GEMINI_API_KEY` (optional model overrides) | `match-volunteers`, `review-condition-name` |
   | `VOICE_TURN_SECRET`, `VOICE_TURN_URLS` | `voice-ice-config` |
   | `maak-supabase-email` (Brevo API key) | `send-volunteer-email` |

   `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are
   provided by Supabase. Server keys never go into the Flutter app.
5. **Feature guides** in `docs/`: push notifications, password recovery OTP,
   voice calls and ringing, session notifications and member profiles, Health
   Library articles, and the design guide.

## Testing

```bash
flutter analyze
flutter test                       # unit, widget and golden tests
cd tests/database && npm install && npm test   # core database tests (PGlite)
node <file>_test.mjs               # any other database test, from tests/database
```

Screenshot tests compare against `test/goldens/`. After an intended design
change, regenerate them with `flutter test --update-goldens` and review the
new images.

## Team

Sara, Dana, Raghad, Razan, Shayma and Jawaher. Each feature's authors are
recorded in the Git history and in the commit messages.
