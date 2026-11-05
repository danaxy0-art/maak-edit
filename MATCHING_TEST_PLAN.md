# Sprint 2 Matching — test evidence and backlog traceability

Implementation reference IDs below are proposed IDs for Dana's matching work. Align them with your team's actual Product/Sprint Backlog IDs once the instructor clarifies the convention. They are not claimed to be your official backlog numbering.

| Proposed ID | Requirement | Automated evidence |
|---|---|---|
| US-M01 | Save multiple selected chronic conditions without resetting approval | MATCH-DB01, DB02, DB03, DB12 |
| US-M02 | Only approved volunteers with at least one exact shared condition qualify | MATCH-01, 05, 06; DB04 |
| US-M03 | More shared conditions increase priority | MATCH-02 |
| US-M04 | Recommend complementary volunteers for different conditions | MATCH-03, 04, 10, 12 |
| US-M05 | AI compares descriptions only with both applicable opt-ins | EDGE-04 through 10 |
| US-M06 | Explain coverage and retain usable fallback on AI failure | MATCH-08; EDGE-05, 08, 09 |
| US-M07 | Protect own health selections, reject anonymous/unauthorized access | MATCH-DB05, 06, 09; EDGE-01 through 03 |
| US-M08 | Retain stable disease links on admin rename, respect disabled conditions | MATCH-DB07, 08, 11 |

## Executed locally

- 14 pure ranking tests: `node --test tests/matching/matching.test.mjs` — PASS.
- 10 Edge handler tests: `node --test tests/matching/edge.test.mjs` — PASS. Actual handler is loaded after stripping TypeScript, with Supabase and Gemini HTTP responses mocked. These tests do not establish live deployment or API success.
- 30 PostgreSQL/PGlite integration checks: `cd tests/database; npm install; node matching_test.mjs` — PASS. Includes 18 inherited regression checks and 12 new matching schema/authorization checks. Base schema and additive migration are executed twice.
- Dart files parsed and formatted successfully with Dart SDK 3.13.5. Formatting is not a substitute for Flutter analysis or runtime testing.

## Must execute on the configured application (Not Run)

| ID | Scenario | Expected |
|---|---|---|
| MAN-M01 | Register both roles without Username; select two conditions | No Username; both saved after verification |
| MAN-M02 | Open profile, change one of several conditions, save/reload | Exact selected list persists |
| MAN-M03 | Candidate for disease A plus another for B | Two complementary suggestions; no requirement that one covers all |
| MAN-M04 | Full overlap vs one shared disease | Full overlap ranks first; labels show correct coverage |
| MAN-M05 | Disable disease or reject volunteer then refresh | Disabled disease excluded from matching; rejected volunteer absent |
| MAN-M06 | AI off or volunteer opts out | No description sent to Gemini for that request/candidate |
| MAN-M07 | Configured Gemini key, valid user, both descriptions and consent | AI mode; tied disease counts can reorder |
| MAN-M08 | Provider down or invalid key | Clear condition fallback; no invented semantic score |
| MAN-M09 | Tap profile then Request support | Existing support request flow; no automatic selection or request |
| MAN-M10 | All required fields empty / invalid names, email and password | Recheck Sprint 1 validation and log actual results |
| MAN-M11 | Small device, large text and keyboard in selector | Controls remain reachable; no overflow |

Flutter SDK, Android runtime and live Supabase/Gemini were not available for this verification. Existing Flutter UI tests were adapted to the multiple-selection interaction but have not been executed for this delivery. Regenerate affected goldens only after reviewing rendered output. Do not report inherited historical VALIDATION claims as this delivery's test results.

Record actual tester and test designer names from all five group members when testing. Do not mark the manual rows Pass until run; keep defect/retest history for TC_17. TC_6 needs the actual test email, not a fabricated placeholder. Resolve TC_8/TC_9 against the 8-character requirement and ensure title, data, steps and expected result agree. Burndown/CFD comments require the team's actual charts/backlog and are outside this code-only update.
