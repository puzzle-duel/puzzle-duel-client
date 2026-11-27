# Phase 1 UAT checklist — Auth lifecycle, badges, diagnostics

Owner device cycle after backend + client deploy. Do not mark Done without this.

## Scenario A — Returning verified account

1. Launch staging app.
2. Authenticate with existing Google account.
3. Verify **no** guest-selection popup (“Mevcut hesabına geçilsin mi?”).
4. Verify original account identity and profile.
5. Verify previously earned On-Time badge is visible (earned, not locked).
6. Logout with confirmation.
7. Verify Profile immediately shows guest state.
8. Verify old account badge data is not exposed.
9. Login with the same Google account again.
10. Verify original badge and account data return.
11. Repeat logout/relogin multiple times.
12. Kill and relaunch the app; verify session and badge persistence.

## Scenario B — Independent profile access

1. Establish a verified account.
2. Ensure no active tournament gameplay session (safe: skip claim / no session secret).
3. Open Profile.
4. Verify badges still load via account-scoped path.
5. Verify no official ranked attempt is consumed.

## Scenario C — Diagnostics

1. Open Settings → **Log Gönder (UAT)**.
2. Verify a real server **Report ID** is returned (Copy available).
3. Run Unified Request Log Inspector with that Report ID.
4. Verify profile/auth HTTP correlation (`profile_badges`, `provider_auth`, `diagnostic_report`).
5. Repeat while tournament session is unavailable; upload must still succeed with account bearer.
6. Confirm Crashlytics vs server delivery are distinct in the snackbar.

## Scenario D — Firebase

1. Settings Crash Test subtitle must match truthful readiness (`FirebaseDiagnostics.readinessMessage`).
2. Noop / not-configured builds must **not** claim “Crashlytics kaydı alındı”.
3. When configured: submit staging non-fatal; confirm Firebase project ingestion (owner console).
4. Explicit Crash Test with confirmation; relaunch; confirm crash + breadcrumbs.
5. Symbolication/dSYM evidence remains owner Firebase console acceptance.

## Apple

Real-device Apple UAT remains pending if Developer enrollment/provider config unavailable. Do not claim pass from mocks.

## Rollout order

1. Merge **backend** PR first (no new migration required).
2. Wait for automatic staging CD on `version/**`.
3. Merge **client** PR; ship new iPhone staging build.
4. Execute this checklist; file Report IDs in Jira.
