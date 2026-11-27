# PZD-54 — Account State Isolation & Single Top Banner

Status: Binding for Puzzle Duel client development (GOLDEN RULES).

## GOLDEN RULE 1 — Single Notification Presenter

All transient user-facing notifications must use the centralized, gesture-dismissible
Top Banner (`AppTopBannerHost`) with semantic `info`, `warning`, and `success`
presentation via `TournamentController.presentAppFeedback`.

- No parallel `SnackBar`, Toast, or screen-specific transient notification channel.
- Maximum one visible banner at a time; one logical operation must not duplicate feedback.
- Successful logout presents exactly one informational banner; guest Home must not also
  raise an automatic `RANKED_AUTH_REQUIRED` warning (the tournament CTA already explains auth).
- Users may dismiss any banner immediately by swiping upward; auto-dismiss timers remain.
- Timers and exit animations are generation-fenced so stale callbacks cannot dismiss a newer banner.
- Legitimate modal dialogs, confirmation sheets, inline validation, and persistent contextual UI remain allowed.

## GOLDEN RULE 2 — Strict Account State Isolation

Account-scoped state must be owned by the current authenticated identity and valid
scope / tournament generation.

- On logout and account transition, call `invalidateAccountScopedPresentation` (or
  `applyGuestSessionAfterLogout`) so `day`, `results`, `board`, `leaderboard`, claim,
  resume navigation, and related personal fields cannot leak into guest or Account B.
- Fence in-flight work with `_tournamentEpoch`, personal-records `fenceSync`, credential
  generation, and session-renewal generation. Stale success / failure / `finally` /
  timer completions must not mutate the active scope.
- Guest Home must never show previous verified score, progress pips, on-time badges,
  rankings, or rewards — even transiently. Prefer clearing ownership over conditional
  paint-only hacks (Home still applies defense-in-depth suppression).
- Do not indiscriminately wipe Practice history, device settings, ads counters, or
  backend tournament records. Logout is an auth lifecycle transition, not account deletion.
- Every new account-scoped feature must include logout and account-switching regression coverage.

## GOLDEN RULE 3 — Observability

Authentication transitions, state invalidation, rejected stale completions, and
notification lifecycle events must remain diagnosable through the existing privacy-safe
`DiagnosticRuntime` / `LogEvent` pipeline (`docs/staging/STAGING-OBSERVABILITY-RELEASE-GATE.md`).

Relevant operations (non-exhaustive):

- `auth_account_scope_cleared`, `guest_home_state_initialized`
- `account_scoped_state_invalidated`
- `app_feedback_presented`, `app_feedback_dismissed_auto`, `app_feedback_dismissed_gesture`
- Existing auth / session / HTTP correlation events

Never log tokens, credentials, emails, or sensitive account payloads.

## GOLDEN RULE 4 — UX Copy Consistency

User-facing messages must be concise, accurate, actionable, and reflect actual
product behavior.

- Never imply restrictions, charges, or entitlements that do not exist.
- Authentication requirements must not be presented as monetization requirements.
- Puzzle Duel currently has no paid gameplay features; do not describe Practice
  or tournament gates as “free vs paid”.
- Prefer short actionable copy (e.g. “Sign in to enter the tournament.”) over
  redundant explanations when the surrounding UI already states the requirement.
- Keep EN/TR (and other supported locales) in sync via `TournamentCopy` / localization
  infrastructure — no hardcoded one-off strings for product messaging.

## Notification lifecycle identity

- Explicit `AppFeedbackNotice` instances are owned by `generation` + `accountEpoch`.
- Identical message text from separate legitimate operations must present again.
- Auto-dismiss timers, gestures, and exit animations pass the expected generation;
  stale callbacks must not dismiss a newer banner.
- `_dismissedNoticeContentKey` applies only to tournament-notice episodes and is
  cleared on each refresh episode — never permanently suppress app feedback.
