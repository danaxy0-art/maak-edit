# Verification — scoped message deletion, tombstones and MP4

User scope correction: whole-conversation deletion was excluded. No clear-chat RPC, table or UI action was added. Existing End Chat/reopen migration files are byte-identical to the previous delivered version.

Executed checks:
- 26 integration checks on an isolated PGlite instance using the repository schema and actual matching, condition review, chat reads, account-blocking, End Chat, reopen, media and deletion migrations. Supabase auth/storage are test stubs; the live-only restricted_at column is represented in the fixture. The deletion migration was applied twice.
- Cases: personal sanitized placeholder; other participant keeps original; sender-only deletion for everyone; idempotency; image, voice and video access revocation; nonparticipant and anonymous denial; direct UPDATE/DELETE denied; no duplicate notification; per-reader preview; unread count and notices; reactions work then are removed/denied after deletion; new sends after individual deletion; End Chat retains history and blocks sends; individual deletion in an ended chat; accepted request preserved.
- 48 matching/edge/registration tests passed, including agreement checks from the previous version.
- 15 existing media/WAV checks and 5 new MP4 signature/size checks passed. Standalone Dart analysis of the dependency-free media policy passed.
- Dart formatter parsed the changed Dart sources. Original logos, fonts and image assets remain byte-identical.

Not verified in this environment:
- Flutter package resolution/full analysis, widget rendering, Android/iOS/web compilation, microphone/video capture or live browser/device playback. The exact plugin/device combination and live Supabase migration should be tested using START_MESSAGE_DELETE_AR.md. Database and pure-code tests do not establish device behavior.

Tests:
- `dart tests/chat_media_policy_check.dart`
- `dart tests/video_media_policy_check.dart`
- `node --test tests/matching/*.test.mjs`
- In tests/database after npm install: `node message_deletion_video_test.mjs`

Storage deletion semantics:
- Personal deletion preserves the other participant's content; own original content is excluded by RLS and scrubbed in the chat RPC.
- Everyone deletion replaces message body/metadata, removes reactions and prevents new signed media links. Objects are retained inaccessible through the client policies; existing signed URLs/copies may remain usable until expiry (URLs: five minutes). No claims of physical deletion from backups/devices.
