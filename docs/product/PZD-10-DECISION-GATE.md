# PZD-10 — Blueprint v1.0 Product Decision Gate

Status: **PROPOSED — OWNER DECISIONS REQUIRED**  
Task: https://puzzle-duel-app.atlassian.net/browse/PZD-10  
Repositories: `puzzle-duel-client` and `puzzle-duel-backend`  
Inputs: byte-identical `BLUEPRINT.md` on both main branches (Git blob `9e027cc00f4441a34bfa067b257fa2383336f55e`), `AGENTS.md`, approved CORE-001 fixture delivery PZD-11.  
This document **does not accept** the draft Blueprint, change an ADR, authorize implementation, or merge anything.

## 1. Already expressed in draft Blueprint — retain unless owner explicitly changes

- Placement-first directional shapes (circle/diamond/triangle), match >=3 row/column, simultaneous one-cell post-clear shift, unique union, integer cascade score 100 × wave index; no hints, boosts, 3x or PvP in MVP.
- Easy 5×5/15 turns/1 obstacle, medium 6×6/12/2, hard 7×7/10/4 are *unvalidated prototype candidates*, not guaranteed balanced.
- Monster 8×8/9/6 and tournaments remain post-MVP.
- Free guest start, offline free play; account required for ranked submission.
- Daily challenge uses identical versioned board/ordered pieces, one official attempt per player, retries practice.
- Ad hypothesis: first nine completed games ad-free; first eligible interstitial after 10th; then intervals 8 and 6; no midgame ad. Consent/privacy required before enabling.
- Score verification is server-authoritative; no client-provided score trusted.

## 2. Open decisions: owner must select policy before ACCEPTED

| ID | Decision | Proposed default for owner consideration (not approved) | Alternatives/risks | Required downstream |
| --- | --- | --- | --- | --- |
| PD-01 | Ranked official attempt lifecycle | **APPROVED by owner: official daily attempt is reserved on start.** If interrupted, player may resume the **same** attempt; cannot create another official attempt for the same daily challenge. | Token/expiry, claim idempotency, interruption recovery, guest/auth eligibility and finalization security are still **implementation decisions requiring separate specification**; no automatic forfeiture on interruption is authorized. | PZD-28/29/31; relevant ADR to be reconciled |
| PD-02 | Daily challenge date cutoff | **APPROVED by owner: UTC 00:00 global cutoff.** One shared challenge date/ID worldwide; clients show the reset moment in the player's local timezone. Türkiye display: 03:00 (UTC+03:00). | Region-local midnight and per-user midnight NOT selected. | PZD-28/31; relevant ADR to be reconciled |
| PD-03 | All-time leaderboard metric | **APPROVED: MVP includes DAILY leaderboard ONLY; all-time/lifetime leaderboard is deferred to a later release.** | No all-time aggregate metric, endpoint, or UI in MVP. Daily leaderboard remains server-verified and challenge-specific. | Reconcile PZD-30 and feature F04 with approved MVP scope |
| PD-04 | Guest → account linking conflicts | **APPROVED by owner: preserve local guest progress, personal best and practice history when Apple/Google account is linked; only server-verified official attempts contribute to ranked scores.** Do not retroactively promote guest practice results to official ranking. | Cross-device data reconciliation, guest/account conflict UI and durable storage rules require detailed specifications. Identity must not auto-merge merely by matching email. | PZD-26/27/24/29; relevant ADR/spec reconciliation |
| PD-05 | Ad session reset and consent | **PARTIALLY APPROVED by owner (option A): completed-game ad counter persists across app termination/relaunch; reopening the app MUST NOT reset it.** Eligibility remains based on completed games. | Ad frequency thresholds, consent/age restrictions, offline completion accounting, cooldown, eligible-game semantics, and feature-flag rollout remain pending; no permission to serve ads is implied. | PZD-32/33; ADR |
| PD-06 | Difficulty validity | **APPROVED by owner (option A): Easy 5×5 / 15 moves / 1 obstacle; Medium 6×6 / 12 moves / 2 obstacles; Hard 7×7 / 10 moves / 4 obstacles are all in MVP as versioned, tunable initial settings.** Balance through deterministic validity checks and player testing before release. | Initial values are NOT frozen difficulty guarantees; changes to ranked challenges must preserve challenge/config versioning and cross-player fairness. Monster remains post-MVP. | PZD-21/35; feature F03 |
| PD-07 | Empty futurePieces during an otherwise legal move | **APPROVED by owner (A): the full ordered piece supply sufficient for the configured move budget must be determined before a game starts. On the final permitted move, no replacement piece needs to be generated or consumed.** For an official challenge, all players receive the identical versioned piece sequence. | Terminal offer-tray representation, whether an early full-board end leaves unused pieces, and compatibility with PZD-11 fixture assumption that every legal move replenishes an offer need an explicit versioned contract/test update before product engine implementation. No on-demand generation fallback. | PZD-17/21/20/29, CORE-001 contract amendment |
| PD-08 | Matches present before first move | **APPROVED by owner (option A): game initial board must contain no pre-existing horizontal/vertical run of 3+ matching shapes; matches and cascades trigger only after a legal player placement.** Do not automatically clear matches or award points before the first move. | Generator must reject/regenerate invalid starting boards. Imported/resumed malformed states with ready matches need explicit validation/error handling; no auto-resolve rule approved. | PZD-17/19/21/29; CORE-001 follow-up contract checks |
| PD-09 | Last empty cell filled then cleared by cascade | **APPROVED by owner (option A): determine game end only after the entire legal placement has resolved all matching, clears, simultaneous shifts and cascade waves.** Evaluate final board availability and remaining move budget **after resolution**. | If the final placement initially fills the board but a cascade reopens a legal cell, the game continues when turns remain. If the move limit has been reached, the game ends even with space. No early termination before scoring and cascade resolution. | PZD-20/17/29; CORE-001 end-condition regression fixtures |
| PD-10 | Error precedence after game end | **APPROVED by owner (option A): when game status is already ended, `game_ended` takes priority over `blocked_tap` and `occupied_tap` regardless of the tapped cell's occupancy/obstacle state.** No additional turn, score, offer consumption or board mutation. | Out-of-range or malformed coordinate precedence is NOT resolved by this approval; validation boundaries must be specified separately. Existing PZD-11 fixture only pins `game_ended` for an otherwise empty legal cell; new regression vectors needed. | PZD-17/18/20/29; versioned CORE-001 replay contract extension |
| PD-11 | Movement event representation | `moved` includes only pieces that actually changed cells, ordered by source row-major | Including stationary pieces may cause UI/replay divergence; PZD-11 current fixtures use moved-only | PZD-19 |
| PD-12 | Cascade safety | No arbitrary user-facing wave cap; prove finite progress by board occupancy/clears or define explicit deterministic fault behavior for malformed replay states | Checker-only 20-wave guard is NOT gameplay policy | PZD-20/29 |
| PD-13 | Ruleset version vocabulary | Confirm exact `rulesVersion`, status strings and typed error codes before a production API; current `core-001.v1` belongs to fixture vocabulary | Prematurely freezing network API from test-only convention | PZD-15/17/28 |

**The proposed defaults are recommendations, not decisions.** Owner may accept, reject, amend, or defer individually. Deferrals that affect MVP gameplay or ranking block corresponding implementation. If the user wants a leaner launch, explicitly scope out the blocked feature rather than inventing its behavior.

## 3. Cross-repo blueprint acceptance criteria

- Owner signs off on exact rules, MVP inclusion/exclusion and status of all decisions affecting MVP.
- One approved blueprint version/hash is byte-identical in client/backend. Preserve a changelog, revision number and agreed owner/date.
- Architecture ADRs are approved separately; blueprint acceptance does NOT silently accept Flutter/Flame, NestJS, data layout, session or privacy ADRs.
- Canonical CORE-001 fixture vector from PZD-11 stays immutable unless rules are deliberately versioned and the associated tests change in a reviewed PR.
- Client/backend product-engine parity is verified once engines exist; passing PZD-11 fixture checkers does not imply both engines exist or have passed.
- No merge/deploy/Done/new task kickoff without owner authorization.

## 4. Required delivery sequence (PZD-10, same task)

1. Present owner the decision matrix and record approvals/deferred items (verbatim rationale and scope).
2. Produce updated `BLUEPRINT.md` in two review branches with the same bytes, only for approved changes. Keep existing files marked Draft until sign-off.
3. Record `README` / specs / ADR references impacted; do not promote Proposed ADRs.
4. Check byte-for-byte parity; create PR(s) to both repos and attach evidence.
5. Review CI / documentation and rules-change regression if relevant.
6. Request owner merge/close approval; then mark PZD-10 Done. Obtain fresh owner approval before starting PZD-13 or any other task.

## 5. Cursor instructions at this stage

**DO NOT WRITE GAME CODE.** The only authorized deliverable now is a proposed decision matrix and comparison report. Do not modify `BLUEPRINT.md` or accept any proposed decision until owner has selected the final policy. Fixes within PZD-10 may be iterated and reviewed without approving a new task.

## 6. Audit checklist

- [x] Initial `BLUEPRINT.md` bytes identical in both repositories (same Git blob)
- [x] PZD-11 fixture suite merged to both main branches (prior task)
- [ ] Owner decision sign-off on PD-01...PD-13 or explicit scoped deferrals
- [ ] Blueprint changes signed off and versioned in both PRs
- [ ] Exact cross-repo blueprint parity verified after approved changes
- [ ] Owner approval for merge and Done

## Owner decision log

- **2026-11-15 — PD-02 APPROVED:** The daily challenge switches at **00:00 UTC**, globally at the same instant. This approval applies to PD-02 only. A global challenge-day ID should derive from the UTC date; clients may display the reset in local time. Implementation and affected ADR/feature specs remain subject to later review. PD-01 is also approved separately; PD-03 was separately approved; PD-05 remaining ad policy and PD-06...PD-13 remain pending.

- **2026-11-15 — PD-01 APPROVED:** The one official daily challenge attempt is **reserved when the player starts** that official challenge, not when they submit a score. If they leave or the session is interrupted, they may resume **the same attempt**; another official attempt for the same challenge is forbidden. This approval does **not** define authentication, timeout/expiry, cross-device recovery, guest eligibility, claim/finalize endpoints or idempotency mechanics. Those must be specified and reviewed before implementation. No new ADR is marked Accepted.

- **2026-11-15 — PD-03 APPROVED:** MVP ships **daily leaderboard only**; all-time/lifetime rankings are postponed to a later release. Do not implement all-time aggregations, endpoints or UI as MVP. This decision requires a subsequent scope update to Jira PZD-30 and F04; it does not authorize deleting their future scope. PD-05 remaining ad policy and PD-06...PD-13 remain pending.

- **2026-11-15 — PD-04 APPROVED:** Preserve locally stored guest progress, personal best and practice/history after linking an Apple/Google account. Ranked/official results remain server-authoritative and require independently verified official attempts; prior guest free-play/practice results are **not** promoted into the leaderboard. The owner has NOT yet approved conflict UX, cross-device sync/merge, data retention limits, identity proof mechanics or guest eligibility for official attempt claims. These details must be specified under PZD-24/26/27/29 before implementation. PD-05 remaining ad policy and PD-06...PD-13 remain pending.

- **2026-11-15 — PD-05 PARTIAL APPROVAL (option A):** The ad eligibility/completed-games counter MUST persist across app restarts; force quit, termination or normal relaunch does not reset completed-game progress. This decision does **not** approve ad delivery without consent/age safeguards, does not finalize game thresholds or cooldown, and does not decide offline counter sync, account switching or reset on uninstall. Keep advertisement serving feature-flagged off until PZD-32/33 policy review. PD-06...PD-13 remain pending.

- **2026-11-15 — PD-06 APPROVED (option A):** MVP includes Easy (5×5, 15 moves, 1 static obstacle), Medium (6×6, 12 moves, 2 static obstacles), and Hard (7×7, 10 moves, 4 static obstacles). These are initial configurable, versioned parameters, not fixed balance claims. Validate generated layouts deterministically, test actual difficulty with players, and adjust in reviewed versioned configurations. Same ranked challenge keeps an identical immutable config for all competitors. Monster stays post-MVP. No production tuning or generator mechanics are implicitly approved by this decision; PD-07...PD-13 remain pending.

- **2026-11-15 — PD-07 APPROVED (option A):** Before starting the game, determine a finite ordered supply of pieces sufficient to play through the configured move limit (unless the board ends the game earlier). At the final legal move allowed by the move budget, no replacement piece is needed. Daily official challenge uses exactly the same version-pinned ordered sequence for every participant. **Follow-up spec gap, not yet approved:** the final offers/stream representation and how a last-move transition interacts with the PZD-11 golden fixture checker, which currently assumes an offer replacement on each legal move. Update the replay contract and add specific last-move + early-board-end tests before implementing this behavior in product engines; do not quietly change existing PZD-11 fixtures or invent a filler piece. PD-08...PD-13 remain pending.

- **2026-11-15 — PD-08 APPROVED (option A):** Generated initial boards for game start must have no ready horizontal or vertical same-shape run of 3 or more. Matches and cascades are triggered only after a legal player placement, not as a pregame cleanup; no score is awarded before the first player move. Deterministic initial-board validation and generator retry/fail policy must be designed within PZD-21. Resume/import of corrupt board states with pre-existing matches remains an error-handling/specification issue, not an authorization to auto-resolve. PD-09...PD-13 remain pending.

- **2026-11-15 — PD-09 APPROVED (option A):** After a valid player placement, fully resolve all matches, union clears, simultaneous one-cell movement, subsequent cascades and scoring before checking terminal state. Evaluate the move-limit and availability of non-blocked empty cells on the **final board**. Filling the final available cell does not terminate play prematurely if that same move clears pieces and restores an available cell while moves remain. Reaching the move limit ends the game regardless of newly freed space. Add explicit regression coverage for final-cell fill + cascade-reopen, final-cell fill + no-clear, and move-limit + cascade. PD-10...PD-13 remain pending.

- **2026-11-15 — PD-10 APPROVED (option A):** If the current game state is `ended`, any tap against an in-bounds blocked or occupied cell returns `game_ended` (rather than `blocked_tap` or `occupied_tap`), with no changes to board, turns, offers or score. The owner explicitly chose game-ended precedence over cell-state errors. This approval does NOT decide behavior for out-of-bounds/malformed input, which must be specified separately. The PZD-11 golden suite currently tests ended-state tap only on an otherwise legal empty cell; add blocked+ended and occupied+ended negative tests when extending the versioned replay contract. PD-11...PD-13 remain pending.
