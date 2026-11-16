# PZD-21 — Challenge generator decision gate

Jira: [PZD-21](https://puzzle-duel-app.atlassian.net/browse/PZD-21).

Status: **Proposed — Owner Approval Required**

Every GEN-01…GEN-07 row below remains **Proposed — Owner Approval Required**. Nothing in this document is Accepted.

Branch: `feature/PZD-21-versioned-level-generator`  
Client `main` base at analysis: `b4f7500f3cd21d914f0846f7b2644ecfcb0d4696` (PZD-20 merged).

This document freezes **nothing**. It proposes a complete cross-runtime generator contract so the owner can approve, reject, or amend it before any production algorithm lands in `packages/puzzle_duel_rules`.

Do **not** treat recommendations below as Accepted. Do **not** implement Phase C until the required GEN rows are owner-approved. Do **not** use host `Random(seed)` / `Math.random` as the contract.

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

**Status: Proposed — Owner Approval Required**

**Question:** What seed encoding and deterministic PRNG produce identical integer sequences on Dart and TypeScript?

#### Compared options

| Option | Pros | Cons |
| --- | --- | --- |
| **A. PCG32 XSH-RR (recommended)** | Fully specifiable; portable 32-bit outputs; good enough for small draws | Must pin every wrap/rotate step |
| B. xorshift32 | Tiny | Weaker; still needs identical wrap rules |
| C. Counter-based (SplitMix64 truncate) | Easy “nth draw” reasoning | 64-bit intermediate pitfalls |

#### Recommended seed encoding

- Type: unsigned 32-bit integer `seed` in `0 … 4294967295` inclusive.
- JSON: integer number only (no float, no string). Values outside the range are `invalid_config`.
- Daily/challenge-id hashing into this range is a later transport concern, not part of GEN-01.

#### Recommended algorithm: PCG32 XSH-RR (single stream)

Constants (fixed for this Proposed contract):

```text
MULT = 6364136223846793005          # uint64
INC  = 1442695040664678687          # uint64; must be odd; fixed stream
MASK64 = 2^64 - 1
MASK32 = 2^32 - 1
```

Unsigned wrap rules (both languages must match):

| Language | Rule |
| --- | --- |
| Abstract | All `uint64` ops are mod `2^64`. All `uint32` ops are mod `2^32`. |
| Dart | Use `BigInt` for state (`& MASK64`), produce `int` outputs with `& MASK32`. Never use signed `int` 64-bit multiply as the sole state update. |
| TypeScript | Use `BigInt` for state (`& MASK64n`). Convert outputs with `Number(x & MASK32n) >>> 0`. Never use `number` multiply for state. |

#### Complete portable pseudocode

```text
function u64(x): return x & MASK64
function u32(x): return x & MASK32

function rotr32(x, r):
    # rotate-right of a uint32 by r bits; r is taken mod 32
    x = u32(x)
    r = r & 31
    return u32( (x >> r) | (x << ((-r) & 31)) )

# Internal LCG step. Advances state. Does not emit an output.
function step(rng):
    rng.state = u64(rng.state * MULT + INC)

# Seed initialization. Exactly two step() calls occur here.
# After seed32 returns, the next nextU32() is the first consumer draw.
function seed32(rng, seed):
    assert 0 <= seed <= 4294967295
    rng.state = 0
    step(rng)                              # warm-up #1
    rng.state = u64(rng.state + u32(seed))   # mix seed into state
    step(rng)                              # warm-up #2
    # No additional warm-up. First nextU32() is the first consumer draw.

# Emit one uint32. Uses oldstate for the output function, then advances.
function nextU32(rng):
    oldstate = rng.state                    # capture BEFORE advance
    step(rng)                              # newstate is now rng.state
    xorshifted = u32( ((oldstate >> 18) ^ oldstate) >> 27 )
    rot        = oldstate >> 59            # top 5 bits; already in 0..31
    return rotr32(xorshifted, rot)         # equivalent to:
                                           # (xorshifted >> rot)
                                           # | (xorshifted << ((-rot) & 31))
```

Notes:

1. Output extraction always uses **`oldstate`**, never the post-`step` state.
2. `seed32` performs exactly two `step` calls and **zero** `nextU32` calls.
3. The first consumer `nextU32` after `seed32` is draw index 0 of the stream.
4. There is exactly one stream per `generateChallenge` call. No parallel streams in Proposed `gen-001.v1`.

#### `randBound(n)` — unbiased rejection sampling

**P1 fix:** Do **not** store the acceptance bound as a `uint32`.  
`floor(2^32 / n) * n` equals `2^32` whenever `n` divides `2^32` (for example `n = 1, 2, 4, 8, 16, 32, …`). Narrowing that product with `u32(...)` wraps it to `0`, so `u < threshold` never succeeds and the loop never terminates.

Correct contract: keep `limit` as an integer in `1 … 2^32` inclusive (use `uint64` / `BigInt` in Dart and TypeScript). Compare the `uint32` draw `u` against that wide `limit`.

```text
TWO32 = 4294967296                         # 2^32; not a uint32 value

function randBound(rng, n):
    # Valid n: integer, 1 <= n <= 2^32
    # n < 1 or n > 2^32 is a contract violation (generator bug / invalid_config).
    assert 1 <= n <= TWO32
    if n == TWO32:
        return nextU32(rng)                # one draw; full uint32 range

    # Largest multiple of n that is <= 2^32.
    # When n divides 2^32, limit == 2^32 (NOT reduced with u32).
    # When n does not divide 2^32, limit == floor(2^32 / n) * n < 2^32.
    limit = floor(TWO32 / n) * n           # integer; may equal TWO32

    # FORBIDDEN (infinite loop when n | 2^32):
    #   threshold = u32(floor(TWO32 / n) * n)   # becomes 0 for n=4, etc.

    loop:
        u = nextU32(rng)                   # u in 0 .. 2^32-1
        if u < limit:                      # wide compare; if limit==TWO32, always true
            return u % n
```

Language notes:

| Language | `limit` storage | Compare |
| --- | --- | --- |
| Dart | `BigInt` (or checked `int` that can hold `4294967296`) | `(BigInt.from(u) < limit)` then `(u % n)` |
| TypeScript | `bigint` | `(BigInt(u) < limit)` then `(u % n)` |

For Proposed `gen-001.v1`, production `randBound` calls use catalogue sizes `3`/`4` and cell-pool sizes up to `boardSize^2` (≤ 49 for Hard). The `n == 2^32` branch is unused there but remains defined.

#### Proposed `randBound` self-check vectors (seed = 0)

After `seed32(rng, 0)`, the first raw `nextU32` is `903765998`. Each row below starts from a **fresh** `seed32(rng, 0)` and performs a single `randBound(n)`.

| n | `limit` | first `u` | accepted immediately? | `randBound` result | `nextU32` draws consumed |
| ---: | ---: | ---: | --- | ---: | ---: |
| 1 | 4294967296 | 903765998 | yes | 0 | 1 |
| 2 | 4294967296 | 903765998 | yes | 0 | 1 |
| 3 | 4294967295 | 903765998 | yes | 2 | 1 |
| **4** | **4294967296** | **903765998** | **yes** | **2** | **1** |
| 5 | 4294967295 | 903765998 | yes | 3 | 1 |
| 24 | 4294967280 | 903765998 | yes | 14 | 1 |
| 25 | 4294967275 | 903765998 | yes | 23 | 1 |
| 32 | 4294967296 | 903765998 | yes | 14 | 1 |
| 4294967296 | (full-range branch) | 903765998 | yes | 903765998 | 1 |

**`n = 4` specifically:** because `4` divides `2^32`, `limit = 4294967296`. Every `uint32` satisfies `u < limit`, so the first draw is always accepted. Under seed `0`, that draw is `903765998` and `903765998 % 4 = 2`. The broken `u32(...)` threshold would have been `0` and would never accept.

Successive `randBound(4)` on one seed-`0` stream (each call one draw): `2, 2, 3, 2, 1`.

Rejection note: for `n = 3`, `limit = 4294967295`, so only `u = 4294967295` is rejected and forces a second `nextU32`. The seed-`0` first draw is not that value, so the table row still shows one draw.

Verified with the same Python/Node BigInt PCG32 references used for the raw seed vectors below.

#### Proposed PRNG self-check vectors (not generator fixtures)

Verified independently with two separate BigInt implementations (Python and Node.js) using the pseudocode above. These are **PRNG-only** vectors. They are not challenge fixtures and do not authorize generator code.

After `seed32(rng, seed)`, the first 10 `nextU32` values:

**seed = 0**

| i | uint32 | hex |
| ---: | ---: | --- |
| 0 | 903765998 | `0x35de5fee` |
| 1 | 2422751314 | `0x90684052` |
| 2 | 1652705799 | `0x62824a07` |
| 3 | 1618866650 | `0x607df1da` |
| 4 | 1060317981 | `0x3f332b1d` |
| 5 | 2689674566 | `0xa0512d46` |
| 6 | 1577384509 | `0x5e04fa3d` |
| 7 | 1403947984 | `0x53ae8bd0` |
| 8 | 255367340 | `0x0f3898ac` |
| 9 | 3521512243 | `0xd1e60333` |

**seed = 1**

| i | uint32 | hex |
| ---: | ---: | --- |
| 0 | 4022946169 | `0xefc94979` |
| 1 | 586434100 | `0x22f44634` |
| 2 | 778513971 | `0x2e672e33` |
| 3 | 4210363984 | `0xfaf50e50` |
| 4 | 465824167 | `0x1bc3e9a7` |
| 5 | 3279466709 | `0xc378b0d5` |
| 6 | 2798243867 | `0xa6c9d01b` |
| 7 | 2464351017 | `0x92e30329` |
| 8 | 356655726 | `0x1542226e` |
| 9 | 566711777 | `0x21c755e1` |

**seed = 4294967295**

| i | uint32 | hex |
| ---: | ---: | --- |
| 0 | 451480749 | `0x1ae90cad` |
| 1 | 2087654271 | `0x7c6f137f` |
| 2 | 3085751845 | `0xb7ecd625` |
| 3 | 2110723429 | `0x7dcf1565` |
| 4 | 2880235874 | `0xabace962` |
| 5 | 856832213 | `0x331238d5` |
| 6 | 2237111505 | `0x85579cd1` |
| 7 | 552382290 | `0x20ecaf52` |
| 8 | 1572602624 | `0x5dbc0300` |
| 9 | 2704297521 | `0xa1304e31` |

Future Dart/TypeScript PRNG units must match these tables exactly before any challenge fixture is trusted.

**Owner must approve:** algorithm choice, constants, seed range/serialization, init protocol, wide-`limit` `randBound` (not `u32`-narrowed), and these self-check vectors.

---

### GEN-02 — Generator version

**Status: Proposed — Owner Approval Required**

**Question:** How is the generation algorithm versioned independently of `rulesVersion`?

| Field | Meaning |
| --- | --- |
| `generatorVersion` | Opaque string id for the **generation algorithm + draw order + density policy**, e.g. `gen-001.v1` |
| `rulesVersion` | Gameplay rules id already used by the engine (`core-001.v1` or `core-001.v2`) |
| `profileId` / config | Easy / Medium / Hard parameter set (board, moves, obstacles, occupiedCount) |

Rules:

1. Changing RNG, obstacle/occupied selection order, density, rejection sampling, piece catalogue order, or supply length formula **requires a new `generatorVersion`**.
2. Historical ranked challenges store `(generatorVersion, rulesVersion, profile/config, seed)` and must regenerate identically under that generator version forever.
3. Bumping `rulesVersion` alone must not silently change board/stream generation.
4. Fixture directory proposal: `docs/contracts/generator/gen-001.v1/` (separate from gameplay `v1`/`v2`).

**Owner must approve:** id vocabulary, fixture root path, and storage obligation on ranked challenges.

---

### GEN-03 — Initial board density and Fisher–Yates selection

**Status: Proposed — Owner Approval Required**

**Question:** How many non-blocked cells start occupied, and how are cells chosen deterministically?

Empty boards pass `parseInitialGameState` but are **not** assumed adequate production challenges (PD-06 / BLUEPRINT).

| Option | Density sketch | Pros | Cons |
| --- | --- | --- | --- |
| **A. Fixed counts (recommended)** | Easy 6, Medium 10, Hard 16 occupied cells among free cells | Deterministic, easy fixtures | May feel sparse/dense until playtested |
| B. Fixed fill ratio | e.g. ~30% of free cells | Scales automatically | Rounding must be pinned |
| C. Empty board MVP | 0 occupied | Simplest | Weak challenge |
| D. Near-match clusters | intentional almost-runs | More interesting | Harder to specify |

#### Recommended density

| Profile | Board | Obstacles | Initial occupied pieces | Free cells after obstacles |
| --- | ---: | ---: | ---: | ---: |
| Easy | 5 | 1 | 6 | 24 |
| Medium | 6 | 2 | 10 | 34 |
| Hard | 7 | 4 | 16 | 45 |

#### Exact cell lists

```text
function allCells(boardSize):
    # Row-major: (0,0), (0,1), …, (0,N-1), (1,0), …
    return [ (r,c) for r in 0..N-1 for c in 0..N-1 ]
```

#### Exact Fisher–Yates helper (partial, forward)

Recommended: **partial Fisher–Yates from the front**, not a full shuffle of unused tails.

```text
# Selects k distinct items from list `pool` (length m), preserving
# relative randomness via in-place swaps on a working copy.
# Consumes exactly k calls to randBound.
#
# Direction: i runs upward from 0 to k-1 inclusive.
# At step i, j is chosen uniformly from i .. m-1 inclusive
# (randBound(m - i) + i), then swap pool[i] <-> pool[j].
# Result prefix pool[0 .. k-1] is the selected set in selection order.
#
# This is a partial shuffle: only the first k positions are finalized.
# Indices k .. m-1 are left as leftover scratch and must not be used.

function selectK(rng, pool, k):
    m = length(pool)
    assert 0 <= k <= m
    work = copy(pool)                      # shallow copy of cell refs
    for i in 0 .. k-1:
        j = i + randBound(rng, m - i)       # one draw; range size m-i
        swap work[i], work[j]
    return work[0 .. k-1]                  # selection order, length k
```

Random draws consumed by `selectK(..., k)`: **exactly `k`** `randBound` calls (each may itself reject and consume multiple `nextU32` values internally).

#### Exact per-attempt board construction order

Inside one board attempt, after `seed32` has already run for the whole `generateChallenge` call:

```text
1) obstacle phase
   cells = allCells(boardSize)             # length N*N, row-major
   blockedSelected = selectK(rng, cells, obstacleCount)
   blocked = sort_row_major(blockedSelected)
   # Serialization always uses blocked sorted ascending by (row, column).
   # Selection order from selectK is discarded after sorting.

2) occupied phase
   free = [cell in allCells(boardSize) if cell not in blocked]
   # free is already row-major because allCells is row-major.
   occupiedSelected = selectK(rng, free, occupiedCount)
   # Keep occupiedSelected in selectK order for piece assignment.

3) piece-on-cell phase (still board attempt; not the offer stream)
   for each cell in occupiedSelected:      # selection order
       shape     = SHAPES[randBound(rng, 3)]
       direction = DIRECTIONS[randBound(rng, 4)]
       write piece into that cell
   # Draws: occupiedCount * (1 + 1) = 2 * occupiedCount randBound calls.

4) validate board-only
   if any H/V run of identical Shape length >= 3: FAIL this attempt
   if parse constraints on blocked/cells fail: FAIL this attempt
   # On FAIL: discard board; do NOT draw offers/futurePieces (see GEN-05).
```

Draw accounting for a **successful** board attempt before supply:

| Stage | `randBound` count |
| --- | ---: |
| Obstacles | `obstacleCount` |
| Occupied cell selection | `occupiedCount` |
| Piece shape+direction | `2 * occupiedCount` |
| **Total board draws** | `obstacleCount + 3 * occupiedCount` |

**Owner must approve:** density numbers, partial Fisher–Yates direction/index rule, obstacle-then-occupied order, and reject-only (no local repair).

---

### GEN-04 — Piece supply and production `rulesVersion`

**Status: Proposed — Owner Approval Required**

**Question:** Exact draw order for offers + `futurePieces`, supply length, and which `rulesVersion` generated challenges use.

Shape catalogue (Proposed fixed order): `circle`, `diamond`, `triangle`  
Direction catalogue (Proposed fixed order): `up`, `right`, `down`, `left`

```text
function drawPiece(rng):
    shape     = SHAPES[randBound(rng, 3)]
    direction = DIRECTIONS[randBound(rng, 4)]
    return Piece(shape, direction)
```

#### Supply length

```text
supplyLength = moveLimit + 2
```

Stream construction (**only after a board attempt is accepted** — GEN-05):

```text
S = [drawPiece(rng) for _ in 1 .. supplyLength]   # supplyLength pieces
offers       = S[0], S[1], S[2]
futurePieces = S[3], S[4], …, S[supplyLength-1]
```

Draws for supply: `2 * supplyLength` `randBound` calls.

#### Why `moveLimit + 2` matches `core-001.v2` terminal-null

Example: Easy profile, `moveLimit = 15`.

| Quantity | Value | Role |
| --- | ---: | --- |
| `supplyLength` | 17 | total pieces drawn into `S` |
| initial `offers` | 3 | `S[0..2]` |
| initial `futurePieces` | 14 | `S[3..16]` |

Legal-move replacement under PZD-18/20 (non-empty future): each successful move replaces exactly one consumed offer with `futurePieces.first` and drops that head.

| After legal move # | `turnsUsed` | `futurePieces.length` | Notes |
| ---: | ---: | ---: | --- |
| 0 (start) | 0 | 14 | three offers filled |
| 1 | 1 | 13 | |
| … | … | … | |
| 14 | 14 | 0 | fourteenth replacement emptied the stream; tray still has 3 pieces |
| 15 (final budget) | 15 | 0 | placement finds `OfferReplacementDeferred` |

On move 15 with `core-001.v2`: cascades and scoring finish first; then because `turnsUsed >= moveLimit` and the stream is empty, only the consumed offer slot becomes JSON `null`; tray length stays 3 (PD-07 / PZD-20). No filler piece is generated.

If `supplyLength` were only `moveLimit` (15): offers 3 + future 12 → after 12 replacements the stream is empty at `turnsUsed = 12`, so moves 13–15 would hit empty-stream before the final budget under continuing play — either abort (v1) or non-terminal empty-stream failure (v2), which is not the intended final-move null path.

If `supplyLength = moveLimit + 2` and the game ends earlier by board-full, leftover future pieces simply remain unused; that is allowed. Early board-full with an **already empty** stream remains an unapproved product outcome and must not be synthesized by the generator.

#### Production `rulesVersion` (still unresolved)

| Option | Effect |
| --- | --- |
| **A. Generate as `core-001.v2` (recommended for new ranked content)** | Matches the terminal empty-stream tray above |
| B. Generate as `core-001.v1` | Empty stream aborts; final-budget null path unavailable |
| C. Config-selectable, default v2 | Ranked daily must still pin one value per challenge |

**Owner must approve:** catalogues, supply formula, stream split, and production `rulesVersion`.

---

### GEN-05 — Generation failure and PRNG flow

**Status: Proposed — Owner Approval Required**

**Question:** How many attempts, what retries, how PRNG advances on failure, and when supply is drawn?

#### Recommended control flow

```text
function generateChallenge(config, seed):
    validateConfig(config)                 # no PRNG; invalid_config on hard errors
    rng = new Rng()
    seed32(rng, seed)                      # exactly two internal step() calls

    for attempt in 1 .. maxAttempts:       # maxAttempts = 256 Proposed
        board = tryBuildBoard(rng, config) # consumes board draws only
        if board is Failure:
            # PRNG state is NOT rewound and NOT re-seeded.
            # Draws already consumed by this failed attempt stay consumed.
            # offers/futurePieces are NOT drawn on this attempt.
            continue
        # Board accepted (no initial match; blocked/cells structurally OK).
        supply = drawSupply(rng, config.moveLimit)
        state = assembleInitialGameState(config, board, supply)
        parseInitialGameState(state.toJson())   # must succeed
        apply S0/S1 checks (GEN-06)
        return immutable GeneratedChallenge(...)

    return ChallengeGenerationFailure(generation_exhausted)
```

#### Critical PRNG rules

1. **Single stream, continued across failed attempts.** Do not call `seed32` again inside the attempt loop. Do not derive `seed + attemptIndex` unless a future `generatorVersion` explicitly changes this (not recommended for `gen-001.v1`).
2. **Failed board attempts consume only board-phase draws** (obstacles + occupied selection + per-cell shape/direction). They do **not** draw `offers` / `futurePieces`.
3. **Supply is drawn only after a board is accepted.** Therefore a challenge that succeeds on attempt 3 has: `seed32` + board draws from attempts 1–2 (discarded boards) + board draws from attempt 3 + exactly one supply draw sequence.
4. Same `(generatorVersion, config, seed)` always performs the same sequence of `nextU32` calls, including those spent on rejected boards, so outputs stay reproducible.
5. Impossible configs fail **before** `seed32` / the loop with `invalid_config` (examples: Monster in MVP API, `obstacleCount >= boardSize^2`, `occupiedCount > free cells`, unsupported versions, seed out of range).
6. No infinite loops. Exhaustion returns typed fail-closed `generation_exhausted` with no partial challenge.

**Owner must approve:** `maxAttempts`, continue-on-failure PRNG policy, supply-after-accept ordering, and failure code names.

---

### GEN-06 — Playability and quality

**Status: Proposed — Owner Approval Required**

Structural validity ≠ solvable ≠ Easy/Medium/Hard.

| Tier | Check | MVP proposal |
| --- | --- | --- |
| S0 Structural | `parseInitialGameState`, profile sizes, obstacle count/order, supply length, no initial match | **Required** after approval |
| S1 Soft playability | ≥1 empty non-blocked cell; three non-null offers; `moveLimit ≥ 1` | **Required** |
| S2 Shallow engine probe | Bounded legal `applyMove` search requiring ≥1 `MoveApplied` | Optional later `generatorVersion` |
| S3 Strategic quality | Human playtests, score distributions | Empirical; never a silent difficulty claim |

**Recommended:** `gen-001.v1` ships S0+S1 only.

**Owner must approve:** mandatory tiers for `gen-001.v1`.

---

### GEN-07 — Cross-runtime parity

**Status: Proposed — Owner Approval Required**

**Proposed canonical artifact:**

```json
{
  "generatorVersion": "gen-001.v1",
  "rulesVersion": "core-001.v2",
  "seed": 1,
  "profile": "easy",
  "config": {
    "boardSize": 5,
    "moveLimit": 15,
    "obstacleCount": 1,
    "occupiedCount": 6
  },
  "blocked": [[0, 0]],
  "cells": [],
  "offers": [],
  "futurePieces": [],
  "turnsUsed": 0,
  "score": 0,
  "status": "in_progress"
}
```

Comparison: deep equality on parsed structures, plus SHA-256 manifests under `docs/contracts/generator/gen-001.v1/CHECKSUMS.txt` once fixtures exist.

Parity status rules:

- Client-only fixtures + Dart tests → **client PASS**, **client/backend generator parity NOT_RUN**.
- Only after an authorized backend TypeScript generator executes the same vectors → parity may be PASS.

Also require the GEN-01 PRNG self-check tables to pass in both languages before challenge fixtures are compared.

**Owner must approve:** schema fields, serializer rules, and fixture directory layout.

---

## Recommended defaults (summary)

| GEN | Recommended default | Status |
| --- | --- | --- |
| GEN-01 | PCG32 XSH-RR pseudocode + vectors above | **Proposed — Owner Approval Required** |
| GEN-02 | `generatorVersion = gen-001.v1`, separate fixture tree | **Proposed — Owner Approval Required** |
| GEN-03 | Occupied 6/10/16; partial FY `i..m-1`; obstacles then occupied | **Proposed — Owner Approval Required** |
| GEN-04 | Catalogues; `supplyLength = moveLimit + 2`; lean v2 | **Proposed — Owner Approval Required** |
| GEN-05 | `maxAttempts = 256`; continue PRNG; supply only after accepted board | **Proposed — Owner Approval Required** |
| GEN-06 | S0+S1 required; no difficulty claims | **Proposed — Owner Approval Required** |
| GEN-07 | Schema + checksums; parity NOT_RUN until backend exists | **Proposed — Owner Approval Required** |

## Already approved vs requiring owner approval

**Already approved:** PD-06 profiles, PD-07 supply finiteness + v2 terminal-null semantics, PD-08 no initial match, PD-13 rules versioning obligation, ADR-001 pure Dart boundary, PZD-17…20 engine APIs.

**Requires explicit owner approval before Phase C:** GEN-01 through GEN-07 as specified in this revision.

## Unresolved constraints (carry to Jira)

- Production ranked challenges: `core-001.v1` vs `core-001.v2` (GEN-04).
- Early board-full + empty stream tray (still unapproved; generator must not invent one).
- Whether free-play offline generation may use a different profile/density than ranked daily.
- How daily challenge UTC date maps to `seed` (transport/challenge-id; not frozen by GEN-01).
- Backend TypeScript generator authorization → parity remains **NOT_RUN**.
- Empirical difficulty validation (playtest) is outside this gate.

## Stop line

Phase B remains open for owner approval. No generator source, no frozen generator fixtures, no `PZD-21-GENERATOR.md` algorithm lock, and no client/backend generator parity claim until the owner approves the required GEN decisions (or amends them in writing).

Phase C may continue on this same branch only after that approval.
