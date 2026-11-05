# Ma’ak — Complete Flutter redesign

Read **[README_AR.md](README_AR.md)** for the full Arabic setup guide.

- Flutter 3.35+ / Dart 3.9+, Android and web targets.
- Original logo preserved byte for byte.
- Two-step registration, live password checks, profile view/edit, unread notifications,
  admin-managed conditions and volunteer application review/reapplication.
- Persistent Supabase support requests, conversations and session scheduling.

## Setup

1. Run the entire `supabase_schema.sql` in your existing Supabase SQL Editor.
2. Configure signup/recovery email templates to include `{{ .Token }}` and working SMTP.
3. `flutter pub get`, `flutter analyze`, `flutter test`, then `flutter run`.
4. Android requires Android Studio SDK platform 36 and Java 17. Gradle files use the
   Flutter 3.35 template with the original application ID `com.example.ma_ak`.
5. For web preview: `flutter run -d chrome`. Supabase access still requires SQL setup.

The source project’s public Supabase connection is retained as a configurable default.
Override with `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...`.

See **VALIDATION.md** for executed checks and the remaining device/account checks.
