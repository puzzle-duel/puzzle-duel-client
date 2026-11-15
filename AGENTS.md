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

## Workflow / quality gates
Before code: cite feature ID, impacted blueprint rules, ADRs and test plan. Make minimum scoped diff. Provide unit tests for each ruleset change, widget/e2e tests for relevant UX, and contract/golden fixture parity with backend. Run formatting/lint/tests and report exact results; do not claim unrun tests passed.
Do NOT push to main, merge PR, modify organization settings, deploy or publish without explicit approval. Ask before adding dependencies, analytics SDKs, IAP or changing auth/privacy.
