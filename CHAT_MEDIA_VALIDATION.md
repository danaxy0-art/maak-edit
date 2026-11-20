# Verification for chat media / registration agreement update

Executed in this workspace:
- 15 pure Dart image signature, size, WAV header, sample format and duration-boundary checks passed.
- 25 isolated PostgreSQL/PGlite checks passed: migration applied twice; agreement version/ownership/idempotency; upload owner/participant rules; no anonymous/nonparticipant media reads; metadata/path checks; valid image/voice; rejected malformed attachment; sent attachment deletion denied; ended/blocked chat upload denied.
- 48 existing and updated Node tests passed: matching, edge authentication, consent fail-closed behavior, no description sent without seeker consent, provider fallback, condition name review, registration email endpoint.
- Standalone Dart analysis of the dependency-free media policy: no issues.
- Dart formatter parsed the changed Dart files. Asset/font bytes compared with original ZIP.

Not executed:
- Full Flutter dependency resolution, Flutter analyzer, Android/iOS/web build, microphone capture, browser audio playback, device UI, live Supabase migration/deployment and Gemini API delivery. These require verification on the target project/device. Do not interpret the above unit/database results as a device test.

Manual acceptance checks (both Help Seeker and Volunteer):
1. New registration cannot finish unchecked; checked agreement saves one owner/version/timestamp record. No new consent box on matching page.
2. Two separate browser profiles/devices in an accepted chat can send/view PNG, JPEG, WebP in both directions; preview can be canceled; >10MB/invalid format rejected clearly.
3. Grant mic permission; record 5 seconds; stop, preview, send; recipient can play/pause. Denied permission explains the issue.
4. Recording below 0.5 seconds rejected; 60 seconds stops for review. Cancel/background does not send. Refresh/return to chat restores sent history.
5. Retry after lost upload/insert response yields one message. A network failure preserves pending attachment.
6. Nonparticipant cannot sign/read/upload another chat object. Ended, restricted and blocked conversations reject sends on server; existing End/Reopen and reactions still work.
7. Existing account without agreement still gets condition matches with no provider call; explicit Profile agreement enables AI. Provider outage still shows condition recommendations.
