# ADR-P43 — Player profile practice persistence and badge reads

Status: **Proposed** (PZD-43 implementation candidate; owner freeze required before production enablement)

## Context

PZD-43 needs personal practice records, version-aware personal bests, and an authoritative On-Time badge collection. Jira open decisions include local vs cloud practice storage, reinstall behavior, and badge repeat semantics.

Existing facts on `main`:

- Client already persists local practice history in JSON (`PracticeStore`).
- Practice uses `core-001.v2` / `gen-001.v1`; ranked tournament boards use `core-001.v3`.
- On-Time grants are written only by F2-B into `tournament_on_time_badge`.
- No player-level badge collection API existed; only per-series `/results` and leaderboard flags.
- ADR-002 (local game state) remains Proposed.

## Decision

### Practice records (device-local)

1. Persist completed practice results on-device only for PZD-43.
2. Scope files by sanitized player label so switching UAT/signed-in players does not leak records.
3. Keep a bounded history (`maxRecords = 40`) and a separate immortalized personal-best map so pruning cannot erase a best.
4. Personal bests are keyed by `difficulty|rulesVersion|generatorVersion`. Incompatible versions are never compared.
5. Source classification is `local_practice` with `verifiedRank: false`. Never send these scores to ranked publication endpoints.
6. Do not auto-merge guest records into a signed-in scope after login.
7. Do not promise cloud restore, reinstall recovery, or cross-device sync in this ADR.
8. Legacy unscoped `practice-records.json` migrates only into the `guest` scope.

### Badges

1. On-Time remains server-authoritative and F2-B-granted only.
2. Candidate read API: `GET /v1/tournament/me/badges` behind the existing ranked HTTP feature gate.
3. Counts derive from immutable awarded rows joined to the authenticated player's completions.
4. On-Time is repeatable across days (one decision row per series). Client must not invent counts.
5. Summary reads trust write-time HMAC + immutability triggers and do not re-HMAC every historical series (unlike `/results`).

## Consequences

- Profile UI can ship practice bests offline without cloud APIs.
- Badge counts require an authenticated session and enabled ranked HTTP (UAT/candidate).
- Owner still decides production enablement, durable app-support directories vs temp storage, and any future cloud sync.

## Non-goals

- New badge grant rules
- Practice score verification or ranked promotion
- XP / level / streak systems
- Lifetime all-time ranking math
