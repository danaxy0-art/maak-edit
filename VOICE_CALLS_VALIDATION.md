# Voice call implementation validation

Implemented stories: start, accept/reject, call states, end, report technical issues, admin review.

## Automated checks

18 isolated PostgreSQL/PGlite integration checks passed. These load the original application schema and actual account/chat migrations before the new voice migration. No live database was accessed.

```
PASS connected participant starts a call
PASS outsider cannot read call or mutate signalling
PASS simultaneous opposite call is busy
PASS caller cannot accept its own call or write rows directly
PASS callee accepts; Connected only after both transports connect
PASS ICE is available to peers only
PASS either participant ends and signalling is cleared
PASS participants report technical problems once per call
PASS admin sees issues but not SDP; reviewer and note saved
PASS callee rejects and call stays ended
PASS unanswered call becomes Missed on server timeout
PASS ended conversation cannot start a call
PASS volunteer can initiate and seeker can end
PASS connected call expires after lost heartbeat
PASS restricted chat terminates ongoing call on sync
PASS invalid and anonymous operations are rejected
PASS blocked peer cannot be called
PASS ended call cannot be resurrected by a late answer
18 voice-call database checks passed
```

Dart syntax was parsed/formatted successfully with dart format. flutter analyze, application builds, and two-device media testing were NOT completed. The Flutter command was rejected by automatic review because its environment detector attempted access to a cloud metadata endpoint. This route was not rerun.

## Changed integration points

- lib/main.dart: app-wide incoming/ongoing call host
- lib/frontend/redesign/support.dart: start-call and call-history buttons
- lib/frontend/redesign/admin.dart and admin_reports.dart: voice issue management entry point
- lib/backend/calls/voice_call_service.dart: WebRTC transport, signalling, state polling, cleanup
- lib/frontend/calls/voice_calls.dart: incoming/active/ended UI, history, member reports, admin review
- supabase/migrations/20261121000000_voice_calls.sql: protected calls, ICE, reports, role-checked RPCs
- supabase/functions/voice-ice-config/index.ts: optional coturn REST ephemeral credentials
- supabase/config.toml: new Edge Function registration
- android/app/src/main/AndroidManifest.xml: audio routing permission
- pubspec.yaml: flutter_webrtc dependency; run flutter pub get to regenerate the lockfile
- tests/database/voice_calls_test.mjs: new integration suite

## Pending device acceptance

Follow VOICE_CALLS_SETUP_AR.md: apply the new SQL, install Flutter dependency, configure/deploy TURN for restrictive networks, and test real two-way audio on two clients. Incoming calls require the app to be open. No background push/CallKit integration was added.

UI update: Reports now has visible Message reports and Voice call reports tabs. Call report cards show a phone icon. Admin overview entry renamed Reports. This UI-only update needs no additional SQL. Dart syntax formatting passed; Flutter runtime verification remains pending as documented above.
