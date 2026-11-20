# Validation of the merged profile and Other update

Executed locally against this delivered source:

- 33 Node checks: matching, matching Edge handler and optional condition-name review Edge handler. External auth and AI calls mocked.
- 30 PGlite/PostgreSQL-compatible integration checks: existing registration, approval, permissions, notifications and matching behavior.
- 15 PGlite checks: Other validation, acceptance/link/rejection, privacy and general recommendations.
- 9 PGlite checks: combined APPLY_UPDATES.sql applied twice, missing profile repair, preservation of existing roles, denial of metadata-based admin elevation, condition write permissions.
- 17 standalone Dart checks: name validation and canonical suggestions.

Total: 104 executed local checks passed. These are not 104 Flutter UI tests.
Dart formatting parsed all changed Dart source successfully.

Not executed: Flutter analyze, test/profile_conditions_test.dart, existing Flutter widget/golden tests, Chrome/Android builds, live Supabase calls, deployed Edge Functions or live Gemini calls.
Flutter verification was blocked by automatic approval review because the Flutter tool attempted to access the cloud instance metadata address. No workaround was used. The standalone Dart, Node and PGlite checks do not contact that address.

New test/profile_conditions_test.dart supplies targeted mocked service and phone layout checks for local execution with flutter test test/profile_conditions_test.dart. It remains unverified here.

The existing logo, botanical background, notification screen and delete-account/send-volunteer-email Edge Function source were compared byte-for-byte to the supplied archive and are unchanged.

Deployment prerequisites are in START_HERE_AR.md. APPLY_UPDATES.sql requires the existing base schema. Existing volunteer decisions are preserved; newly missing role-detail rows are not fabricated as approved applications.
