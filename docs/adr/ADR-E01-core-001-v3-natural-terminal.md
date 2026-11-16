# ADR-E01 — CORE-001.v3 natural terminal and offer tray

Status: **Proposed** (not Accepted) — revised after PZD-39 adversarial review
Date: 2026-11-17
Review companion: [CORE-001-V3-ARCHITECTURE-REVIEW.md](../engine/CORE-001-V3-ARCHITECTURE-REVIEW.md)
Owner review required before any Dart/TypeScript implementation.
Related: PZD-20 resolution, PZD-17/18/19, PZD-21 (`gen-001.v1`), Tournament T-10A, ADR-T02 TD-11, PZD-38 Gate C, Jira PZD-39.
Must not modify: historical `core-001.v1` / `core-001.v2` fixtures, generators, or PZD-38 Phase A ingress.

## 1. Context

Tournament V1 (owner T-10A) requires that a subgame which reaches a deterministic state with **no legal move remaining** finish successfully at its already earned verified score and allow advance to the next ordinal. Historical `core-001.v2` fails closed on early board-full with an empty stream (`early_board_end_empty_stream`) and only allows a single JSON `null` offer after move-budget exhaustion. That blocks ranked natural completion.

This ADR proposes separately versioned ruleset `core-001.v3` so v1/v2 remain byte-immutable.

## 2. Historical compatibility

| Version | Behavior preserved |
| --- | --- |
| `core-001.v1` | Empty stream never invents pieces; empty-stream commit fails closed (`empty_stream_not_terminal`). End = move limit **or** zero empty unblocked cells. |
| `core-001.v2` | Single terminal `null` only when `ended` ∧ `turnsUsed >= moveLimit` ∧ empty stream; continuing trays forbid null; early board-full + empty stream fails closed. |
| `gen-001.v1` | Unchanged. Challenges may pin `rulesVersion: core-001.v3` only after this ADR is Accepted and dual-engine parity PASS. |

Dispatch by stored `rulesVersion`. No silent migration of saved sessions or replays to v3.

## 3. Exact v3 state schema

### 3.1 Top-level `GameState` (v3)

| Field | Type | Nullability | Invariants |
| --- | --- | --- | --- |
| `rulesVersion` | string | required | Exactly `"core-001.v3"` |
| `boardSize` | int ≥ 1 | required | Square board |
| `moveLimit` | int ≥ 1 | required | ≤ 2^53−1 |
| `blocked` | `int[2][]` | required | Row-major unique in-range; cells empty |
| `cells` | `(Piece\|null)[][]` | required | `boardSize×boardSize`; board cell `null` means empty (not an offer spent marker) |
| `offers` | `OfferSlot[3]` | required | Length exactly 3; §3.2 |
| `futurePieces` | `Piece[]` | required | Finite ordered supply; may be `[]` |
| `turnsUsed` | int | required | `0 ≤ turnsUsed ≤ moveLimit` |
| `score` | int | required | `0 ≤ score ≤ 2^53−1`; integer-only; no terminal bonus |
| `status` | `"in_progress"` \| `"ended"` | required | Must match §5 |
| `terminalReason` | `TerminalReason` \| `null` | required | `null` iff `in_progress`; non-null iff `ended` |

Closed document: unexpected properties → parse failure.

`Piece` (board / stream / piece-offer payload): `{ "shape": <enum>, "direction": <enum> }` with the same enums as v1/v2. Board empty cells remain JSON `null`.

### 3.2 `OfferSlot` (tagged) — recommended

```json
"offers": [
  { "kind": "piece", "shape": "circle", "direction": "right" },
  { "kind": "spent" },
  { "kind": "piece", "shape": "diamond", "direction": "down" }
]
```

| `kind` | Extra fields | Meaning |
| --- | --- | --- |
| `piece` | `shape`, `direction` only | Selectable offer |
| `spent` | none | Consumed with no stream replacement |

Invariants:

- Exactly three slots; indices 0..2 stable.
- Initial published challenges: three `piece` slots (no initial `spent`).
- `spent` allowed while `in_progress` when produced by empty-stream commit.
- Multiple `spent` allowed.
- After a commit with **non-empty** stream, the consumed slot must be `piece` (replacement). A `spent` slot coexisting with a claim that the stream still owed a replacement is corrupt → parse/invariant failure.
- Bare JSON `null` inside `offers` is **invalid** on v3.
- Selecting `spent` → `offer_unavailable` (**MoveUnsafe**), never a natural terminal.

### 3.3 Alternatives

| Option | Decision |
| --- | --- |
| A. Tagged `OfferSlot` | **Recommended** |
| B. `Piece\|null` with v3 null-while-active | Rejected (collides with v2 null rules) |
| C. Variable-length tray | Rejected (breaks offerIndex contract) |

## 4. Cascade and scoring (unchanged from PZD-20)

Place → cascade clear/shift loop → integer `uniqueCleared×100×wave` → then offer commit → then terminal evaluation. Rejected/unsafe paths leave state unchanged. No terminal score bonus.

## 5. Terminal predicate (v3)

Evaluate **only** after successful placement, complete cascades, offer commit, and final structural validation:

1. If `turnsUsed >= moveLimit` → `status=ended`, `terminalReason=move_limit_reached`.
2. Else if `!hasLegalMove(state)` → `status=ended`, `terminalReason=no_legal_moves`.
3. Else → `status=in_progress`, `terminalReason=null`.

Empty `futurePieces` alone does not end the game.

**Precedence:** if both (1) and (2) hold after the same move, record **`move_limit_reached` only**.

### 5.1 `TerminalReason` (successful wire values only)

| Value | Meaning |
| --- | --- |
| `move_limit_reached` | Budget exhausted on a legal applied move |
| `no_legal_moves` | Natural completion; score retained |

Integrity failures are **not** terminal reasons on `MoveApplied` / stored ended states. They remain parse failures or `MoveUnsafe`.

## 6. Offer consumption (v3)

For consumed index `i` after cascades:

| Stream | Action |
| --- | --- |
| Non-empty | Slot `i` ← `{kind:piece,...}` from stream head; drop head |
| Empty | Slot `i` ← `{kind:spent}` |

Never invent pieces. Do not rewrite other slots.

## 7. Legal-move predicate

**Normative definition:**

```
hasLegalMove(S) :=
  S.status == in_progress AND
  ∃ offerIndex ∈ {0,1,2}, ∃ tap:
    applyPlacement(S, Move(offerIndex, tap)) is PlacementApplied
```

Must call the approved placement implementation (PZD-18), not a competing heuristic.

**PZD-18 lemma (current engine only):** directional placement accepts every in-bounds empty unblocked tap when the selected offer is a live `piece`. Therefore today:

```
hasLegalMove(S) ⇔ (∃ piece offer) ∧ (∃ empty unblocked cell)
```

If placement constraints change, the lemma may fail; the normative existential remains binding.

## 8. Precedence

1. Parse/validation failure → no mutation  
2. Placement unsafe (OOB, spent/unavailable offer) → `MoveUnsafe`  
3. Placement rejected (`game_ended`, `blocked_tap`, `occupied_tap`) → `MoveRejected`  
4. Unresolved pre-move match → `MoveUnsafe`  
5. Cascade/offer integrity failures → `MoveUnsafe`  
6. Else apply §5  

Never map unsafe outcomes to `no_legal_moves`.

## 9. Canonical serialization and hashing (v3)

**Single algorithm** (resolves prior sorted-vs-fixed-order contradiction):

1. Validate schema; reject non-integers / out-of-range ints / unexpected props.
2. `canonical_json_v3`: recursively encode values; arrays keep order; **objects sort keys by UTF-8 byte order**; compact JSON; UTF-8 bytes.
3. Enum/string content is ASCII wire tokens; do not apply Unicode compatibility normalization that would alter tokens.
4. `stateHash = lowercase hex(SHA-256(canonical_utf8_bytes))`.

Do not use Dart `Object.hashCode` or language map insertion order.

v1/v2 fixture file checksum ledgers are independent and immutable.

## 10. Failure semantics

Fail closed with no partial board/score for malformed tray/stream/geometry, unresolved pre-move match, cascade corruption, forged `terminalReason`/`score`/`stateHash`, unknown `rulesVersion`, and numeric overflow outside the JSON-safe domain.

## 11. Dart / TypeScript parity

Dart: extend `packages/puzzle_duel_rules` with v3 dispatch.  
TypeScript: new pure module for server replay (backend lacks a gameplay engine today; Py/Node checkers are not sufficient).  
Parity = identical accept/reject, board, offers, stream, score, turns, status, terminalReason, stateHash on frozen fixtures + historical v1/v2 regression.

## 12. Golden fixtures

See `docs/contracts/gameplay/v3/FIXTURE-SPEC.md`. Expected boards/hashes remain `PENDING_FREEZE` until dual-engine agreement.

## 13. Migration

Pin `core-001.v3` on new manifests only after Acceptance + parity PASS. Never rewrite historical sessions.

## 14. Security / replay risks

Client terminal flags are not authoritative. Server replays under pinned version. Tagged trays reduce null-smuggling across versions. Canonical hashes prevent serializer drift.

## 15. Acceptance criteria

1. Owner decides D1–D10 in the architecture review.  
2. Fixture freeze after dual engines.  
3. Dart+TS PASS + v1/v2 checksum regression.  
4. Tournament boundary respected.

## 16. Outstanding owner decisions

See decision table in `CORE-001-V3-ARCHITECTURE-REVIEW.md`. This ADR stays **Proposed** until those are explicitly accepted.
