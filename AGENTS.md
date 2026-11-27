# AGENTS.md — Puzzle Duel Client (binding for coding agents)
## Authority and scope
Read `BLUEPRINT.md`, relevant `docs/features/` and `docs/adr/` before modifying code. This repo is ONLY the iOS/Android client; the backend belongs to `puzzle-duel-backend`.
Priority: explicit owner instructions > accepted product blueprint/ADRs > feature spec > code conventions. If contradictory, STOP and ask; **never silently choose**.
Only ADRs with Status: Accepted are binding architecture choices. Proposed ADRs require approval; no assumption that a framework/library decision was accepted.

## Immutable gameplay until approved
Implement placement-first arrow move, runs >=3, unique union clear, simultaneous one-cell post-clear movement, cascading ×wave score as specified by CORE-001. 3x tiles, movement hints, new boosts, traffic skin, changing shapes/rules are out of scope. Difficulty configurable; Monster is prototype/post-MVP only. Ranked games share exact seeds/configs and canonical rule version.

## Engineering restrictions
- Prefer deterministic pure Dart gameplay logic, no animation/Flutter state in scoring engine.
- UI animation cannot affect engine state, placements, outcomes or scoring. Guard rapid taps and navigation during resolution.
- Accessibility: shapes not just colors, focus/readable labels, contrast, reduced motion, screen sizes.
- Never hardcode live secrets, credentials, backend prod URLs or tokens. Never commit .env or signing keys.
- Guest start and free play remain available offline. Do not gate first play behind authentication or an ad.
- No ads in gameplay; show only at approved boundaries with consent/age gating. Never invent 2-game frequency.
- Backend is source of truth for ranked score; never use local score as confirmed rank.
- No third-party assets with unclear commercial license; no club logos/names or implied endorsement.

## Mandatory observability reading gate — EVERY development task
Before planning or editing any screen, route, API call, error handling, CI, Firebase or staging code, **MUST READ** `docs/staging/STAGING-OBSERVABILITY-RELEASE-GATE.md` and `docs/staging/SERVER-CONFIG.md`. The observability guide is binding for all client features (not just release): screen/important action breadcrumbs, HTTP start/completed/failed with the same 32-hex `x-request-id`, Firebase Crashlytics custom logs, Report ID/Request ID Inspector, redaction and honest NOT_RUN gates. All changes must document instrumentation impact and tests. If the feature needs a new diagnostic event code or report field, update client/backend contract and inspector together; never bypass allowlists or log secrets. No changes to game mechanics/animations under a logging task. Gökhan/Serap named-player enrollment was reverted; do not recreate it to satisfy logging.

## Workflow / quality gates
Before code: cite feature ID, impacted blueprint rules, ADRs and test plan. Make minimum scoped diff. Provide unit tests for each ruleset change, widget/e2e tests for relevant UX, and contract/golden fixture parity with backend. Run formatting/lint/tests and report exact results; do not claim unrun tests passed.
Do NOT push to main, merge PR, modify organization settings, deploy or publish without explicit approval. Ask before adding dependencies, analytics SDKs, IAP or changing auth/privacy.

## Mandatory post-development summary (GOLDEN RULE)
After every meaningful milestone, implementation, bug fix, refactor, or review remediation, deliver a development summary to the owner **in Turkish** (keep file names and technical identifiers in English) and record the same summary on the corresponding Jira issue. The summary must cover: what changed, why, how it works, files, impact, decisions, executed tests with actual results, GitHub branch/SHA/PR/CI, Jira status/comments, remaining work, next step, and whether owner action is required. Do not treat a milestone as complete until this summary is delivered. Providing a summary does not by itself require stopping for approval unless a real approval gate was reached. All future agents must read and follow this rule before starting development.

## GOLDEN RULES — Account isolation & notifications (PZD-54)
Binding detail: `docs/architecture/PZD-54-ACCOUNT-ISOLATION-AND-NOTIFICATIONS.md`.

1. **Single Notification Presenter** — All transient user feedback uses `AppTopBannerHost` / `presentAppFeedback` (info/warning/success). No SnackBar/Toast parallel channels.
2. **Strict Account State Isolation** — Account-scoped tournament presentation and async completions must not cross logout or account-switch boundaries; fence with scope/generation.
3. **Observability** — Auth transitions, invalidation, stale rejection, and banner lifecycle remain privacy-safe `LogEvent` diagnostics.
