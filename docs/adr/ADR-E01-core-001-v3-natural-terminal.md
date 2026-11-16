# ADR-E01 — CORE-001.v3 natural terminal and offer tray

Status: **Proposed** (not Accepted)
Date: 2026-11-17
Owner review required before any Dart/TypeScript implementation.
Related: PZD-20 resolution, PZD-17/18/19, PZD-21 generator (`gen-001.v1`), Tournament T-10A, ADR-T02 TD-11, PZD-38 Gate C.
Must not modify: historical `core-001.v1` / `core-001.v2` fixtures, generators, or Phase A ingress (PZD-38).

## 1. Context

Tournament V1 (owner T-10A) requires that a subgame which reaches a deterministic state with **no legal move remaining** finish successfully at its already earned verified score and allow advance to the next ordinal. Historical `core-001.v2` fails closed on early board-full with an empty stream (`early_board_end_empty_stream`) and only allows a single JSON `null` offer after move-budget exhaustion. That blocks ranked natural completion.

This ADR proposes a **separately versioned** ruleset `core-001.v3` so v1/v2 remain byte-immutable.

## 2. Historical compatibility

| Version | Behavior preserved |
| --- | --- |
| `core-001.v1` | Empty stream never invents pieces; empty-stream commit fails closed (`empty_stream_not_terminal`). End = move limit **or** zero empty unblocked cells. |
| `core-001.v2` | Single terminal `null` only when `ended` ∧ `turnsUsed >= moveLimit` ∧ empty stream; continuing trays forbid null; early board-full + empty stream fails closed. |
| `gen-001.v1` | Unchanged. Challenges may later pin `rulesVersion: core-001.v3` only after this ADR is Accepted and parity PASS. |

Dispatch remains by stored `rulesVersion`. No silent migration of saved sessions or replays to v3.

## 3. Exact v3 state schema

All v1/v2 fields remain with identical types except as noted.

### 3.1 Top-level `GameState` (v3)

| Field | Type | Nullability | Invariants |
| --- | --- | --- | --- |
| `rulesVersion` | string | required | Exactly `"core-001.v3"` |
| `boardSize` | int ≥ 1 | required | Square board |
| `moveLimit` | int ≥ 1 | required | |
| `blocked` | `int[2][]` | required | Row-major unique in-range; cells empty |
| `cells` | `(Piece\|null)[][]` | required | `boardSize×boardSize` |
| `offers` | `OfferSlot[3]` | required | Length exactly 3; see §3.2 |
| `futurePieces` | `Piece[]` | required | Finite ordered supply; may be `[]` |
| `turnsUsed` | int | required | `0 ≤ turnsUsed ≤ moveLimit` |
| `score` | int ≥ 0 | required | Integer-only; no terminal bonus |
| `status` | `"in_progress"` \| `"ended"` | required | Must match terminal predicate §5 |
| `terminalReason` | `TerminalReason` \| `null` | required for v3 | `null` iff `in_progress`; non-null iff `ended` |

Closed document: no unexpected properties (same as v1/v2 parsers).

### 3.2 Recommended `OfferSlot` (tagged; unambiguous)

**Recommendation: tagged slots — do not overload JSON `null`.**

```json
"offers": [
  { "kind": "piece", "shape": "circle", "direction": "right" },
  { "kind": "spent" },
  { "kind": "piece", "shape": "diamond", "direction": "down" }
]
```

| `kind` | Extra fields | Meaning |
| --- | --- | --- |
| `piece` | `shape`, `direction` (same enums as v1/v2) | Selectable offer |
| `spent` | none | Slot consumed with no replacement from stream |

Invariants:

- Exactly three slots.
- `spent` is allowed while `in_progress` when `futurePieces` is empty (v3).
- Multiple `spent` slots are allowed.
- There is no “never populated” state distinct from `spent` in serialized form; initial challenges must publish three `piece` slots.
- Selecting a `spent` slot is `offer_unavailable` (unsafe / fail-closed), same operational class as v2 null selection.

### 3.3 Valid / invalid JSON examples

Valid in-progress with one spent slot and remaining playable offer:

```json
{
  "rulesVersion": "core-001.v3",
  "boardSize": 5,
  "moveLimit": 30,
  "blocked": [],
  "cells": [[null, null, null, null, null], [null, null, null, null, null], [null, null, null, null, null], [null, null, null, null, null], [null, null, null, null, null]],
  "offers": [
    { "kind": "spent" },
    { "kind": "piece", "shape": "circle", "direction": "up" },
    { "kind": "spent" }
  ],
  "futurePieces": [],
  "turnsUsed": 12,
  "score": 900,
  "status": "in_progress",
  "terminalReason": null
}
```

Valid natural terminal (no legal moves; offers all spent; empty cells remain):

```json
{
  "rulesVersion": "core-001.v3",
  "status": "ended",
  "terminalReason": "no_legal_moves",
  "offers": [
    { "kind": "spent" },
    { "kind": "spent" },
    { "kind": "spent" }
  ],
  "futurePieces": [],
  "score": 1200
}
```

Invalid (v3 rejects bare null offers):

```json
"offers": [null, {"kind":"piece","shape":"circle","direction":"up"}, {"kind":"spent"}]
```

Invalid (ended without reason):

```json
"status": "ended", "terminalReason": null
```

### 3.4 Alternatives considered

| Option | Pros | Cons | Decision |
| --- | --- | --- | --- |
| A. Tagged `OfferSlot` (recommended) | Explicit spent vs piece; stable hashing; no collision with v2 null rules | Slightly larger JSON; dual parsers | **Recommend** |
| B. Reuse `Piece\|null` with v3-only null-while-active | Smaller delta from v2 | Null overloaded; hashing/`null` vs missing; easy to mis-dispatch v2 | Reject as default |
| C. Variable-length tray | Matches “remaining offers” intuition | Breaks offerIndex 0..2 contract; UI/generator churn | Reject |

## 4. Cascade and scoring invariants (unchanged)

Preserve PZD-20:

1. Place, then cascade.
2. Clear unique matching cells; score `uniqueCleared × 100 × wave`.
3. Shift only after successful clear; cascade until no match.
4. Bound `floor(occupiedAfterPlacement / 3)`.
5. Commit offer replacement only after full cascade.
6. Integer score only; no terminal bonus; reject/unsafe leave state unchanged.

## 5. Terminal predicate (v3)

After a **successful** move path (placement + cascades + offer commit + final validation):

1. Let `S` be the candidate post-commit state (still structurally validated).
2. If `turnsUsed >= moveLimit` → `status=ended`, `terminalReason=move_limit_reached`.
3. Else if `!hasLegalMove(S)` → `status=ended`, `terminalReason=no_legal_moves`.
4. Else → `status=in_progress`, `terminalReason=null`.

Notes:

- Empty `futurePieces` alone does **not** end the game.
- Board-full is covered by `!hasLegalMove` when no empty unblocked cell remains.
- All-spent offers with empty cells remaining → `no_legal_moves` (Tournament-critical).
- Integrity failures never become natural terminals.

### 5.1 `TerminalReason` enum (v3 wire)

| Value | Meaning |
| --- | --- |
| `move_limit_reached` | Budget exhausted on a legal move path |
| `no_legal_moves` | Successful natural completion; score retained |
| `integrity_failure` | **Not** stored on successful `MoveApplied`; reserved for proof envelopes / rejected forged terminals |

Forged `terminalReason` / score on parse must fail closed (`inconsistent_status` or new `forged_terminal`).

## 6. Offer consumption (v3)

After cascades, for consumed index `i`:

| Stream | Action |
| --- | --- |
| Non-empty | Replace slot `i` with `{kind:piece,...}` from stream head; drop head |
| Empty | Write `{kind:spent}` into slot `i` only |

Never invent a new random piece. Multiple spent slots OK. Do not rewrite other slots.

## 7. Legal-move predicate

```
hasLegalMove(state) -> bool
```

Preconditions: `state.status == in_progress`; otherwise false for further play (ended taps → `game_ended`).

Definition (must reuse approved placement rules, not a heuristic):

```
exists offerIndex in {0,1,2}:
  offers[offerIndex].kind == piece
  AND exists tap in empty unblocked cells:
    applyPlacement(state, Move(offerIndex, tap)) is PlacementApplied
```

Under current directional placement (PZD-18), any empty unblocked tap with a live piece offer yields `PlacementApplied`. Therefore today:

```
hasLegalMove ≡ (∃ piece offer) ∧ (∃ empty unblocked cell)
```

If future rules add placement constraints, the existential over `applyPlacement` remains normative; the simplification must be re-proven.

## 8. Terminal precedence (v3 dispatch)

Preserve v1/v2 branch precedence for non-v3. For v3 move application:

1. Malformed input / validation failure → no mutation
2. Placement unsafe (`tap_out_of_bounds`, `offer_unavailable`) → `MoveUnsafe`, unchanged
3. Placement rejected (`game_ended`, `blocked_tap`, `occupied_tap`) → `MoveRejected`, unchanged
4. Unresolved pre-move match → `MoveUnsafe.unresolved_pre_move_match`
5. Cascade safety failures → `MoveUnsafe`, unchanged
6. Offer commit integrity → fail closed
7. Else apply terminal predicate §5

Never map unsafe/cascade failures to `no_legal_moves`.

## 9. Canonical serialization and hashing

- Canonical JSON: UTF-8, sorted object keys, no insignificant whitespace, arrays keep order, integers without exponents.
- Piece object key order: `kind`, `shape`, `direction` for piece slots; spent: `kind` only.
- State hash: `SHA-256` hex of canonical JSON of the full `GameState`.
- Dart `Object.hashCode` is **not** a cross-language proof.
- Replay proof envelope (recommended): `{ rulesVersion, stateHash, score, status, terminalReason, turnsUsed }`.

## 10. Failure semantics

Fail closed (no partial board/score) for: invalid geometry; wrong offer length/kinds; bare null offers on v3; corrupt stream; negative budget; unresolved pre-move match; nonterminating/corrupt cascade; hash mismatch; forged terminal/score; unknown `rulesVersion`.

## 11. Dart / TypeScript parity

| Runtime | Location (planned) | Role |
| --- | --- | --- |
| Dart | `packages/puzzle_duel_rules` | Product engine; add `RulesVersion.core001V3` dispatch |
| TypeScript | New pure module under backend (e.g. `src/engine/core001/`) | Server replay; **not** the existing Python/Node checkers alone |

Parity requires identical: accept/reject, board, offers, stream, score, turns, status, terminalReason, stateHash on frozen v3 fixtures, plus historical v1/v2 regression unchanged.

Backend today: `src/generator.mts` only (`gen-001.v1` + `core-001.v2` pin). Contract checkers under `docs/contracts/gameplay/v{1,2}` are **not** product engines (PZD-16).

## 12. Golden fixtures

See `docs/contracts/gameplay/v3/FIXTURE-SPEC.md`. Vectors remain **Proposed** until independently reviewed expected outputs are frozen; do not hard-code from a single implementation.

## 13. Migration

- New challenges/manifests pin `core-001.v3` only after Acceptance + parity PASS.
- Existing published v1/v2 challenges stay on their versions.
- Client must not rewrite stored local v1/v2 sessions to v3.

## 14. Security / replay risks

- Client-reported `status` / `terminalReason` / `score` are not authoritative.
- Server must replay under pinned version.
- Forged natural terminal must not publish ranks.
- Tray tagging prevents ambiguous null smuggling across versions.

## 15. Acceptance criteria (for later Acceptance of this ADR)

1. Owner approves tagged tray + terminal reasons + predicate.
2. Fixture catalogue reviewed; checksum ledger created.
3. Dart + TS engines PASS golden + v1/v2 regression.
4. Tournament integration contract reviewed (engine does not own entitlement/deadlines).

## 16. Outstanding owner decisions

See end of companion report / §Owner approval request. ADR stays **Proposed** until those are signed.
