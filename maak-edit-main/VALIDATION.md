# Validation — registration and database fixes

- Flutter: 43 tests passed, including no username input for either role and blocking registration when conditions fail to load.
- PostgreSQL/PGlite: 18 integration checks passed, including a volunteer registered without username metadata being visible to admin, document validation, review permissions, rejection and reapplication.
- Updated SQL is tested twice to verify repeatability. Auth accounts missing profiles are repaired; existing profile roles and data are preserved. Admin application query uses a left join so profile join failures cannot hide submitted applications.
- Dart analysis: no issues found.
- Android build and live Supabase were not tested. Apply the supplied SQL to the application's Supabase project before testing live data.
