# PZD-11 — Canonical deterministic puzzle ruleset and fixture contract
Status: **Proposed / implementation specification**; blueprint CORE-001 is current product baseline, not an Accepted ADR.
Owners: client and backend. This exact document must match in both repos before implementation.
Jira: https://puzzle-duel-app.atlassian.net/browse/PZD-11

## Goal
Make engine behavior independently verifiable in Dart and TypeScript without involving rendering, login, ads, Firebase, the network or SportsDash. This task is **documentation + fixture schema + fixture cases only**, NOT application scaffolding.

## Coordinate/data contract (proposal for owner review)
- Zero-based [row,column] where 0<=row,column<N; row-major index = row*N+column.
- Shapes `circle`, `diamond`, `triangle`; direction `up`, `right`, `down`, `left`. Shapes are gameplay identity, not palette/color.
- State: `rulesVersion`, `boardSize`, `moveLimit`, `blocked`, `cells` (null or `{shape,direction}`), `offers` (ordered length 3), `futurePieces` (ordered), `turnsUsed`, `score`, `status`.
- Move: `{offerIndex:0|1|2,tap:[row,col]}`. Invalid move is rejected without consuming offer/turn or mutating state. Immediately replace only used slot with next streamed piece if one remains. Behavior when stream exhausts must be explicit in generator spec; fixtures should keep sufficient pieces.
- Placement: require tapped cell empty and not blocked. Look one orthogonal cell forward in selected piece direction. If inside and empty/unblocked, land on neighbor; otherwise tapped cell. No slide beyond one cell. Legal move costs exactly one turn.
- Match: detect all runs >=3 equal SHAPE horizontal/vertical. Union intersection cells; delete each unique coordinate once. No diagonal matches. Arrows/visual theme do not affect matching.
- After **each successful clear**, attempt one-step simultaneous movement of each remaining piece using board occupancy immediately after clearing, before movement. A target with a piece at phase start is unavailable even if that piece wants to leave. Every target proposed by >1 source fails for all, and sources remain in place. Blocked and out-of-bounds destinations fail. No gravity.
- Rematch after movement until no match. Each clear is wave 1,2,... for that one player move. Score delta at wave k = unique cleared count * 100 * k; score from different player moves does not share wave multiplier.
- No clear => no global shift. All shifts are driven by a prior clear. End on move limit or no legal empty board cell; attempted moves after end fail without mutation.
- Engine output per legal move must expose `landing`, `turnsUsed`, `scoreDelta`, `waves` each with `cleared`, `scoreDelta`, `moved` entries, and `finalState`, so UI animation does not recalculate rules.

## Required golden fixtures
All coordinates zero-based and rows increase downward. Fixtures may describe direct phase functions (not just full moves):
1. `place_right_free`: N=5 blank; circle-right offer, tap [2,2] => landing [2,3], 1 turn, 0 points, no waves.
2. `place_blocked_neighbor`: N=5, blocked [[2,3]], circle-right, tap [2,2] => landing [2,2], 1 turn, 0 points.
3. `place_edge`: N=5, circle-up, tap [0,2] => landing [0,2].
4. `illegal_tap`: blocked tap or occupied tap; no changes in state, offer, turn or score; explicit typed error.
5. `horizontal_match`: state row 2 has circles at [2,0] and [2,1], blocked [2,3]; circle-right tap [2,2] => piece lands [2,2] (blocked forward), clear three [2,0],[2,1],[2,2], score=300, waves=1. When other surviving pieces exist check one movement phase.
6. `cross_union`: direct match phase N=5 circles [2,1],[2,2],[2,3],[1,2],[3,2] => unique 5 cleared, 500 at wave 1, not 600.
7. `contested_shift`: direct shift phase N=5; [2,1] right and [2,3] left both claim empty [2,2], neither moves.
8. `preoccupied_shift`: direct shift phase N=5; [2,1] right cannot enter [2,2] occupied at phase start, even when [2,2] right plans to [2,3].
9. `blocked_shift`: piece aimed at static blocked cell or boundary stays put.
10. `two_wave_cascade`: hand-constructed board and one move producing >=2 clear waves; pin cleared coordinate arrays and cumulative integer score from independent reference walkthrough. Do NOT invent an expected score without checking the board manually or in an independent reference test.
11. `end_conditions`: move budget exhaustion; grid filled (non-blocked cells all occupied); illegal post-end move.
12. `replay_determinism`: identical versioned configuration and transcript => exact same outcomes on repeated execution and both runtimes.

## Fixture schema and engineering guidelines
- Store language-independent JSON under `docs/contracts/gameplay/v1/`; a schema plus numbered fixtures. Each fixture must include given/when/expected, rule IDs, and a human-readable derivation.
- Separate `phase` fixtures (`match`, `shift`) from `fullMove` fixtures; do not fake a game move to test an internal state transition.
- Preserve stable ordering: cleared cells row-major; movement records source-index ascending. Standardize serializer field order only if consumers depend on it (normally should not).
- Reject duplicates/out-of-range blocked positions, malformed shapes/directions, illegal turn counts, overwrites and unknown rulesVersion.
- Version fixtures immutably after approval. Both teams must consume identical JSON bytes or a CI hash verification; do not fork the contract.
- Do not include user IDs, tokens, infrastructure endpoints, branding assets or restricted commercial materials.

## Definition of Done (PZD-11)
- Detailed fixture JSON schema and all enumerated cases written, reviewed and mutually consistent.
- Explicit expected pre-/post-states, score, landing and wave order for fullMove cases.
- At least one independent verification technique recorded; ambiguous cases documented as questions, not arbitrary choices.
- Cross-repo parity established (file identical or documented source-of-truth sync); no application code or unexplained dependency added.
- PR titled `[PZD-11]`, branch named with PZD-11, no direct main merge; report tests NOT_RUN if no harness exists.

## Blockers to disclose, not guess
Exact official daily attempt lifecycle, RNG algorithm and seed versioning, and all-time rank formula are **outside** this task and remain Proposed elsewhere.
