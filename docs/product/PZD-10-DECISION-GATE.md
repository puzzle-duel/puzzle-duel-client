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
| PD-03 | All-time leaderboard metric | Separate version-compatible points/normalized rating specification required; **defer all-time ranking unless fairness formula explicitly chosen** | Raw sum rewards number of days/attempts; lifetime raw scores across different configs unfair | PZD-30; feature F04 |
| PD-04 | Guest → account linking conflicts | Keep local guest practice & best score; server account is source of truth for ranked attempts; never auto-merge identity by email | Retrospective ranked promotion risks double-counting and fraud; conflict ownership UX | PZD-26/27; ADR |
| PD-05 | Ad session reset and consent | Session/counter definitions, persistence across app restarts, offline completed games, consent/child audience and cooldown explicitly specified before shipping; ads feature-flagged off until approved | Too-frequent ads; platform store/review policy | PZD-32/33; ADR |
| PD-06 | Difficulty validity | Profiles as tunable, versioned candidate configs requiring deterministic generator constraints and real playtest evidence | Static obstacle count alone does not measure difficulty; impossible/free-play layouts | PZD-21/35 |
| PD-07 | Empty futurePieces during an otherwise legal move | Generate/commit enough future pieces for valid challenge horizon; **explicitly define terminal tray consumption representation** | Current PZD-11 fixture validator aborts instead of representing terminal empty stream; must not become product policy | PZD-17/21, CORE-001 contract extension |
| PD-08 | Matches present before first move | Require canonical generated initial boards to have no unresolved >=3 runs; decide whether imported/saved states with runs are invalid vs auto-resolved | Otherwise replay may disagree about when scoring begins | PZD-17/19/21 |
| PD-09 | Last empty cell filled then cleared by cascade | Determine game-over only **after full placement cascade resolution** based on final board and remaining turns | Early end could incorrectly terminate a valid cascading move | PZD-20 |
| PD-10 | Error precedence after game end | Recommend `game_ended` takes precedence over blocked/occupied tap if status already ended; preserve invalid-coordinate precedence separately | Client/backend error mismatch/behavior leak | PZD-17/18 |
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

- **2026-11-15 — PD-02 APPROVED:** The daily challenge switches at **00:00 UTC**, globally at the same instant. This approval applies to PD-02 only. A global challenge-day ID should derive from the UTC date; clients may display the reset in local time. Implementation and affected ADR/feature specs remain subject to later review. PD-01 is also approved separately; PD-03...PD-13 remain pending.

- **2026-11-15 — PD-01 APPROVED:** The one official daily challenge attempt is **reserved when the player starts** that official challenge, not when they submit a score. If they leave or the session is interrupted, they may resume **the same attempt**; another official attempt for the same challenge is forbidden. This approval does **not** define authentication, timeout/expiry, cross-device recovery, guest eligibility, claim/finalize endpoints or idempotency mechanics. Those must be specified and reviewed before implementation. No new ADR is marked Accepted.
