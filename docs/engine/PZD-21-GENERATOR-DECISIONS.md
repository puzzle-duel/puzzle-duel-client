# PZD-21 — Challenge generator decision gate

Jira: [PZD-21](https://puzzle-duel-app.atlassian.net/browse/PZD-21).

Status: **Proposed — Owner Approval Required**

Branch: `feature/PZD-21-versioned-level-generator`  
Client `main` base at analysis: `b4f7500f3cd21d914f0846f7b2644ecfcb0d4696` (PZD-20 merged).

This document freezes **nothing**. It proposes generator contract choices so the owner can approve, reject, or amend them before any production algorithm lands in `packages/puzzle_duel_rules`.

Do **not** treat recommendations below as Accepted. Do **not** implement Phase C until the required GEN rows are owner-approved.

## Already owner-approved (not reopened here)

| ID | Decision | Source |
| --- | --- | --- |
| PD-06 | Easy 5×5 / 15 / 1; Medium 6×6 / 12 / 2; Hard 7×7 / 10 / 4 are MVP versioned starting profiles, not verified difficulty ratings. Monster excluded. | [PZD-10-DECISION-GATE.md](../product/PZD-10-DECISION-GATE.md), BLUEPRINT CORE-LEVEL-001 |
| PD-07 | Finite ordered piece supply before start; no on-demand replenishment. Final-budget empty stream uses `core-001.v2` single-null tray semantics. Historical `core-001.v1` abort semantics preserved. Early board-full + empty stream still unapproved. | Same |
| PD-08 | Initial full-move board must have no H/V run of 3+ identical shapes. Generator must reject/regenerate invalid starts. No pregame auto-clear or score. | Same |
| PD-13 | First official ruleset id is `core-001.v1`; rule changes need a new `rulesVersion`. | Same |
| ADR-001 | Pure Dart rules package; no Flutter/Flame inside the engine. | [ADR-001](../adr/ADR-001-client-stack.md) |

PZD-17…PZD-20 already enforce: blocked uniqueness/row-major/occupancy, `parseInitialGameState` vs `parseGameState`, offer tray length 3, and fail-closed unresolved pre-move matches in `applyMove`.

## Decision matrix

### GEN-01 — Seed and PRNG

**Question:** What seed encoding and deterministic PRNG produce identical integer sequences on Dart and TypeScript?

**Constraint:** Do not use unspecified `Random(seed)` / `Math.random` as a cross-runtime contract.

| Option | Pros | Cons |
| --- | --- | --- |
| **A. PCG32 (recommended)** | Well-specified 32-bit output; widely ported; good statistical quality for small draws | Needs an explicit portable reference implementation in both languages |
| B. xorshift32 | Tiny; easy to audit | Weaker statistical properties; still needs identical shift/mask semantics |
| C. Counter-based (e.g. SplitMix64 → truncate) | Easy to reason about “nth draw” | 64-bit intermediate portability must be locked carefully |

**Proposed recommendation (not Accepted):**

1. Seed type: unsigned 32-bit integer `seed` in range `0 … 2³²−1`, serialized as a JSON number that is an integer (no float). Daily/challenge IDs may hash into this range under a later transport contract; that hash is out of GEN-01 scope.
2. Algorithm: **PCG32** XSH-RR with 64-bit state. Exact constants and steps to pin on approval (standard PCG-XSH-RR-32):
   - state update: `state = state * 6364136223846793005 + |1` (odd increment fixed per stream; propose increment `1442695040664678687`)
   - output: standard XSH-RR extract to `uint32`
3. Initialization: `state = 0`; one `seed(seed)`; advance once before first consumer draw (standard PCG seed protocol). Exact init sequence must be copied into the approved algorithm doc byte-for-byte.
4. Bounded selection: for upper bound `n > 0`, use rejection sampling on `uint32` to avoid modulo bias: draw `u`; accept while `u < floor(2³² / n) * n`; return `u % n`. Overflow: all arithmetic mod `2⁶⁴` for state, mod `2³²` for output, using only unsigned wrap semantics defined in both languages.
5. Draw ordering: every consumer call advances the same single stream in a fixed call order defined by GEN-03/GEN-04. No parallel streams in MVP generator v1.

**Owner must approve:** algorithm choice, constants, seed range/serialization, init protocol, and unbiased `randBound(n)`.

---

### GEN-02 — Generator version

**Question:** How is the generation algorithm versioned independently of `rulesVersion`?

**Proposed recommendation (not Accepted):**

| Field | Meaning |
| --- | --- |
| `generatorVersion` | Opaque string id for the **generation algorithm + draw order + density policy**, e.g. `gen-001.v1` |
| `rulesVersion` | Gameplay rules id already used by the engine (`core-001.v1` or `core-001.v2`) |
| `profileId` / config | Easy / Medium / Hard parameter set (board, moves, obstacles) |

Rules:

1. Changing RNG, obstacle placement order, density, rejection sampling, piece catalogue order, or supply length formula **requires a new `generatorVersion`**.
2. Historical ranked challenges store `(generatorVersion, rulesVersion, profile/config, seed)` and must regenerate identically under that generator version forever.
3. Bumping `rulesVersion` alone must not silently change board/stream generation.
4. Fixture directory proposal: `docs/contracts/generator/gen-001.v1/` (separate from gameplay `v1`/`v2`).

**Owner must approve:** id vocabulary (`gen-001.v1` vs other spelling), fixture root path, and storage obligation on ranked challenges.

---

### GEN-03 — Initial board density

**Question:** How many non-blocked cells start occupied, and how are pieces placed?

Empty boards pass `parseInitialGameState` but are **not** assumed adequate production challenges (PD-06 / BLUEPRINT).

| Option | Density sketch | Pros | Cons |
| --- | --- | --- | --- |
| **A. Fixed counts (recommended)** | Easy 6, Medium 10, Hard 16 occupied cells among free cells | Deterministic, easy fixtures, clear version pin | May feel sparse/dense until playtested |
| B. Fixed fill ratio | e.g. ~30% of free cells | Scales with board size automatically | Fractional rounding must be specified |
| C. Empty board MVP | 0 occupied | Simplest generator | Weak challenge; likely fails product intent |
| D. Procedural “almost matched” clusters | intentional near-runs | More interesting openings | Harder to specify; higher rejection rate |

**Proposed recommendation (not Accepted):** Option A fixed occupied counts:

| Profile | Board | Obstacles | Initial occupied pieces | Free cells after obstacles |
| --- | --- | --- | --- | --- |
| Easy | 5 | 1 | 6 | 24 |
| Medium | 6 | 2 | 10 | 34 |
| Hard | 7 | 4 | 16 | 45 |

Placement algorithm sketch (still Proposed):

1. Enumerate free cells in row-major order.
2. Sample `occupiedCount` distinct free cells via sequential `randBound` without replacement (Fisher–Yates on the free-cell list using the approved PRNG).
3. For each selected cell, draw `shape` then `direction` (GEN-04 catalogue order).
4. If the completed board has any H/V run ≥ 3, **discard the entire board attempt** and retry (GEN-05). Do not auto-clear or locally repair by inventing a different product rule (PD-08).

Obstacle placement: sample `obstacleCount` distinct cells from the full board via the same without-replacement method, sorted to row-major before serialization.

**Owner must approve:** density numbers (or empty-board exception), placement order, and reject-vs-repair policy (recommend reject-only).

---

### GEN-04 — Piece supply and production `rulesVersion`

**Question:** Exact draw order for offers + `futurePieces`, supply length, and which `rulesVersion` generated challenges use.

Shape catalogue (Proposed fixed order): `circle`, `diamond`, `triangle`  
Direction catalogue (Proposed fixed order): `up`, `right`, `down`, `left`

**Draw of one piece:** `shape = catalogue[randBound(3)]`, then `direction = catalogue[randBound(4)]`.

**Supply length (Proposed):**

`supplyLength = moveLimit + 2`

Interpretation: three initial offers consume the first three supply draws; after `moveLimit` legal moves under normal replacement, the tray still has pieces through turn `moveLimit − 1`, and the final budget turn may leave `futurePieces` empty so `core-001.v2` terminal-null semantics apply without inventing fillers (PD-07).

Concrete stream construction (Proposed):

1. Draw `supplyLength` pieces into ordered list `S`.
2. `offers = S[0..2]`
3. `futurePieces = S[3..]`

**Production `rulesVersion` (unresolved — do not silently choose):**

| Option | Effect |
| --- | --- |
| **A. Generate as `core-001.v2` (recommended for new ranked content)** | Matches approved terminal empty-stream tray; needs owner confirmation that production ranked challenges use v2 |
| B. Generate as `core-001.v1` | Historical abort-on-empty-stream; final-budget empty stream cannot complete a legal move under v1 engine semantics |
| C. Config-selectable, default v2 | Flexible; ranked daily must still pin one value per challenge |

v1 golden gameplay fixtures remain untouched either way. Generator fixtures are a separate tree (GEN-02).

**Owner must approve:** catalogue orders, supply formula, stream split, and production `rulesVersion` policy for newly generated challenges.

---

### GEN-05 — Generation failure

**Question:** How many attempts, what retries, and what typed failure?

**Proposed recommendation (not Accepted):**

1. Validate config first (profile known, Monster rejected for MVP API, board/moves/obstacles match profile or explicitly custom-approved config, `occupiedCount` ≤ free cells, seed in range, `generatorVersion` supported, `rulesVersion` supported).
2. Attempt budget: `maxAttempts = 256` full board+supply generations per call (constant, versioned).
3. Each attempt: obstacles → occupied cells → pieces → `parseInitialGameState` → optional GEN-06 checks. On any structural/match failure, discard and retry with continued PRNG state (**do not re-seed** mid-call; attempt loop consumes the same stream so the sequence is reproducible).
4. Alternative to discuss: re-seed each attempt from `seed + attemptIndex` via a defined mixing step. **Recommend single-stream continuation** for simpler parity vectors unless owner prefers attempt isolation.
5. If exhausted: return typed fail-closed `ChallengeGenerationFailure` with a non-transport internal code such as `generation_exhausted` (exact enum spelling on approval). No partial board. No infinite loop.
6. Impossible configs (e.g. obstacles ≥ board cells, occupiedCount too large) fail **before** the attempt loop with `invalid_config`.

**Owner must approve:** `maxAttempts`, whether PRNG continues across retries, and failure code vocabulary.

---

### GEN-06 — Playability and quality

**Question:** What is required beyond structural validity?

Structural validity ≠ solvable ≠ Easy/Medium/Hard.

| Tier | Check | MVP proposal |
| --- | --- | --- |
| S0 Structural | `parseInitialGameState`, profile sizes, obstacle count/order, supply length, no initial match | **Required** after approval |
| S1 Soft playability | At least one empty non-blocked cell; three non-null offers; `moveLimit ≥ 1` | **Required** |
| S2 Shallow engine probe | From the generated state, enumerate a small bounded set of legal taps/offers and require ≥1 `MoveApplied` | **Proposed optional** for generator v1; if included, must pin enumeration order |
| S3 Strategic quality / true difficulty | Human playtests, score distributions, completion rates | **Post-generator empirical process**; not a silent claim of Easy/Medium/Hard correctness |

**Proposed recommendation:** Ship generator v1 with S0+S1 only. Record S2 as a later `generatorVersion` bump if approved. Never label outputs as balance-verified.

**Owner must approve:** which tiers are mandatory for `gen-001.v1`.

---

### GEN-07 — Cross-runtime parity

**Question:** How will Dart and TypeScript prove identical generation?

**Proposed canonical artifact (not Accepted):**

```json
{
  "generatorVersion": "gen-001.v1",
  "rulesVersion": "core-001.v2",
  "seed": 1,
  "profile": "easy",
  "config": { "boardSize": 5, "moveLimit": 15, "obstacleCount": 1, "occupiedCount": 6 },
  "blocked": [[...]],
  "cells": [[...]],
  "offers": [...],
  "futurePieces": [...],
  "turnsUsed": 0,
  "score": 0,
  "status": "in_progress"
}
```

Comparison: canonicalize JSON key order as produced by a pinned serializer (or compare parsed structures field-by-field with deep equality). Include SHA-256 manifests under `docs/contracts/generator/gen-001.v1/CHECKSUMS.txt`.

Parity status rules:

- Client-only fixtures + Dart tests → report **client PASS**, **client/backend generator parity NOT_RUN**.
- Only after an authorized backend TypeScript generator executes the same vectors → may claim parity PASS.

**Owner must approve:** schema fields, serializer canonicalization, and fixture directory layout.

---

## Recommended defaults (summary)

| GEN | Recommended default | Status |
| --- | --- | --- |
| GEN-01 | PCG32, uint32 seed, rejection `randBound` | **Proposed** |
| GEN-02 | `generatorVersion = gen-001.v1`, separate fixture tree | **Proposed** |
| GEN-03 | Fixed occupied counts 6 / 10 / 16; reject-and-retry on initial match | **Proposed** |
| GEN-04 | Catalogue order circle/diamond/triangle × up/right/down/left; `supplyLength = moveLimit + 2`; production rules **lean v2** | **Proposed** (rulesVersion especially) |
| GEN-05 | `maxAttempts = 256`; fail `generation_exhausted` / `invalid_config` | **Proposed** |
| GEN-06 | S0+S1 required; S2 optional later; no difficulty claims | **Proposed** |
| GEN-07 | Separate generator fixtures + checksums; parity NOT_RUN until backend exists | **Proposed** |

## Already approved vs requiring owner approval

**Already approved (may be assumed by implementation once GEN rows land):** PD-06 profiles, PD-07 supply finiteness + v2 terminal-null semantics, PD-08 no initial match, PD-13 rules versioning obligation, ADR-001 pure Dart boundary, PZD-17…20 engine APIs.

**Requires explicit owner approval before Phase C:**

1. GEN-01 PRNG + seed contract  
2. GEN-02 `generatorVersion` vocabulary and fixture root  
3. GEN-03 density counts and reject-only policy  
4. GEN-04 piece catalogues, supply formula, **production `rulesVersion`**  
5. GEN-05 attempt budget and failure codes  
6. GEN-06 mandatory quality tier set  
7. GEN-07 schema / checksum / parity evidence rules  

## Unresolved constraints (carry to Jira)

- Production ranked challenges: `core-001.v1` vs `core-001.v2` (GEN-04).
- Early board-full + empty stream tray (still unapproved product outcome; generator must not invent one).
- Whether free-play offline generation may use a different profile/density than ranked daily.
- How daily challenge UTC date maps to `seed` (transport/challenge-id concern; not frozen by GEN-01).
- Backend TypeScript generator authorization and schedule → parity remains **NOT_RUN** until then.
- Empirical difficulty validation process (PZD-35 / playtest) is outside this gate’s acceptance of “profiles exist”.

## Stop line

Phase B ends here. No generator source, no generator fixtures, no `PZD-21-GENERATOR.md` algorithm lock, and no claim of client/backend generator parity until the owner approves the required GEN decisions (or amends them in writing).

Phase C may continue on this same branch only after that approval.
