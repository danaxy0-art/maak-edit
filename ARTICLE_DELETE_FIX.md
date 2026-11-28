# Article deletion feedback fix

The list and detail delete handlers previously caught both the database operation and UI feedback in one block. A feedback exception after a committed deletion could therefore display a deletion error.

Changes:
- Catch and log database deletion failures separately from success feedback.
- Return a deletion result from the detail page and show success on the list page.
- Request a void RPC result explicitly, matching admin_delete_article's SQL return type.
- Preserve existing authorization and SQL deletion logic.

No SQL migration is required for this patch. The underlying cause of the reported incident is not confirmed without its exception log.

Validation: the original ZIP was compared byte-for-byte with this copy; only the two article Dart source files changed. A regression test was added for successful JSON-null/204 responses and genuine RPC failure. Flutter and Dart are unavailable in the preparation environment, so compilation and tests have NOT been run.

Run locally from the project directory:

flutter pub get
flutter analyze
flutter test test/admin_article_delete_test.dart
flutter run -d chrome

Manual checks: delete a draft from the list and from its detail page; confirm it disappears and Article deleted appears. Cancel deletion and confirm it remains. If the error persists, copy the terminal exception after Admin article delete RPC failed or Admin article detail delete RPC failed. Do not retry deletion until checking whether the article was already removed.
