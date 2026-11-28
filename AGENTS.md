# AGENTS.md — Puzzle Duel Client (binding for coding agents)

## MANDATORY FIRST STEP — project action ledger (owner 2026-11-28)
Before ANY Puzzle Duel action (including read-only review, user-facing build commands, troubleshooting, Jira or GitHub operations), read `docs/DEVELOPMENT-HISTORY.md`, `docs/staging/SERVER-CONFIG.md` and relevant accepted decisions from the actual target ref. After each meaningful action append its outcome, evidence, decisions, tests and next step to the ledger. This is mandatory for all agents, including ChatGPT and Cursor. Verify existing approved UX and regressions before changing anything; do not resurrect removed behaviors. Staging transport is **https://84-13-66-211.sslip.io** (Oracle **84.13.66.211**); **https://staging.puzzle-duel.app is the JWT issuer, not the API transport**. Never give build instructions without the runbook's trusted TLS health preflight and complete OAuth/Firebase flags. No direct Oracle SSH, unapproved merge/deploy, destructive reset or data wipe.

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

1. **Single Notification Presenter** — All transient user feedback uses `AppTopBannerHost` / `presentAppFeedback` (info/warning/success). No SnackBar/Toast parallel channels. Banner lifecycle identity is generation/epoch, not message text.
2. **Strict Account State Isolation** — Account-scoped tournament presentation and async completions must not cross logout or account-switch boundaries; fence with scope/generation.
3. **Observability** — Auth transitions, invalidation, stale rejection, and banner lifecycle remain privacy-safe `LogEvent` diagnostics.
4. **UX Copy Consistency** — User-facing messages must be concise, accurate, actionable, and reflect actual product behavior. Never imply restrictions, charges or entitlements that do not exist. Authentication requirements must not be presented as monetization requirements.

## GOLDEN RULES — Badge Evolution & Prestige (PZD-56)
Binding visual contract: [`docs/design/BADGE_EVOLUTION_DESIGN_RULE.md`](docs/design/BADGE_EVOLUTION_DESIGN_RULE.md). Cursor rule: `.cursor/rules/badge-evolution-design.mdc`.

**Every developer and AI coding agent MUST read the canonical badge design document before modifying any badge-related implementation** (catalogue, painters, profile badge UI, Studio, award logic, thresholds, golden tests).

1. Owner-approved Badge Evolution Studio geometry is canonical — reproduce with shared vector medallion + center artwork; never redesign, simplify, replace, or substitute Material Icons / emoji / AI PNG medals.
2. Preserve existing badge identities and earned progress (especially `on_time`); never reset counts or grant competitive advantages; prestige is earned, never purchased.
3. Separate identity, eligibility, earned count, prestige resolution, palette, shared frame, and center artwork. Seven centers × six frames = 42 combinations; do not hand-maintain 42 bitmaps.
4. Account isolation and guest sync follow PZD-54 / established linking; competitive badges remain backend-authoritative; Studio never mutates real achievement state.
