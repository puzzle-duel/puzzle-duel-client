# ADR-E01 — CORE-001.v3 natural terminal and offer tray

Status: **Accepted** — owner-approved D1–D10 architecture (design acceptance only; implementation unverified)
Date: 2026-11-17
Jira: [PZD-39](https://puzzle-duel-app.atlassian.net/browse/PZD-39)
Companions:
- [CORE-001-V3-ARCHITECTURE-REVIEW.md](../engine/CORE-001-V3-ARCHITECTURE-REVIEW.md)
- [canonical-v3-test-vectors.md](../contracts/gameplay/v3/canonical-v3-test-vectors.md)
- [FIXTURE-SPEC.md](../contracts/gameplay/v3/FIXTURE-SPEC.md)

Owner approved D1–D10 as documented in this ADR and its companion architecture review on 2026-11-17. This acceptance binds the v3 design only; Dart/TypeScript runtime implementation, fixture freeze, parity, release and deployment remain separately gated.
Must not modify: `core-001.v1` / `core-001.v2`, `gen-001.v1`, PZD-38 Phase A.

## 1. Context

Tournament T-10A requires successful natural completion when no legal placement remains, preserving earned score. `core-001.v2` fails closed on early board-full with empty stream. This ADR defines separately versioned `core-001.v3`.

## 2. Historical compatibility

| Version | Preserved |
| --- | --- |
| `core-001.v1` | Empty-stream abort; end = move limit or board-full empty cells |
| `core-001.v2` | Single terminal null only at budget+empty stream; early board-full+empty stream fail-closed |
| `gen-001.v1` | Unchanged; may later pin `rulesVersion: core-001.v3` after Acceptance + parity |

## 3. State schema (v3)

### 3.1 Fields

| Field | Type | Invariants |
| --- | --- | --- |
| `rulesVersion` | `"core-001.v3"` | Exact |
| `boardSize` | int ≥ 1 | ≤ 2^53−1 |
| `moveLimit` | int ≥ 1 | ≤ 2^53−1 |
| `blocked` | `int[2][]` | Row-major unique in-range; empty cells |
| `cells` | `(Piece\|null)[][]` | Square; cell `null` = empty board cell |
| `offers` | `OfferSlot[3]` | §3.2 |
| `futurePieces` | `Piece[]` | Ordered; may be `[]` |
| `turnsUsed` | int | `0…moveLimit` |
| `score` | int | `0…2^53−1` |
| `status` | `in_progress` \| `ended` | Must equal `deriveTerminalExpectation` (§5.3) |
| `terminalReason` | `move_limit_reached` \| `no_legal_moves` \| `null` | `null` iff in_progress |

Closed document. All string tokens are enumerated ASCII (`shape`, `direction`, `kind`, `status`, `rulesVersion`, `terminalReason`).

`Piece` = `{ "shape", "direction" }` (no `kind` on board/stream pieces).

### 3.2 OfferSlot (D1)

```json
{ "kind": "piece", "shape": "circle", "direction": "right" }
{ "kind": "spent" }
```

- Length exactly 3; indices stable.
- Bare `null` in `offers` invalid.
- `spent` has no other fields.
- Selecting `spent` → `offer_unavailable` (MoveUnsafe), not natural terminal.

### 3.3 Spent structural vs provenance (D4)

**Structural (parse may enforce):**

- Well-formed `spent` / `piece`.
- If any `spent` exists and a non-empty `futurePieces` would imply a deferred replacement still owed on that snapshot after a completed commit path, treat as corrupt when validating a **post-commit** snapshot that claims consistency with empty-stream spent rules: practical rule for published snapshots — **`spent` slots are only legal when `futurePieces` is empty`** (same spirit as review). Snapshots mid-illegal history remain rejectable by replay even if structure is pretty.

**Provenance (parser cannot prove alone):**

- That a `spent` slot was created by consuming a real offer requires immutable initial challenge + accepted move ledger + deterministic consumption during **authoritative server replay**.
- A syntactically valid forged snapshot is not “parse-proven legitimate history.”

## 4. Cascade / scoring

Unchanged PZD-20 mechanics. Checked integer arithmetic (§10) at every intermediate. No terminal bonus.

## 5. Legal placement, gameplay moves, terminal truth (P0-1)

### 5.1 `hasLegalPlacement(candidate)` — status-agnostic

Evaluates board, offers, blocked cells and PZD-18 placement geometry **without trusting `status` or `terminalReason`**.

```
hasLegalPlacement(C) :=
  ∃ offerIndex ∈ {0,1,2} where offers[offerIndex].kind == piece
  ∧ ∃ tap in-bounds:
      approved PZD-18 placement validation would yield PlacementApplied
      on a provisional view of C that ignores claimed status
      (treat as if gameplay were allowed solely for geometry testing)
```

Implementations must reuse PZD-18 rules (landing/direction/blocked/occupied), not a divergent heuristic.

**PZD-18 lemma (current code only):** any empty unblocked in-bounds tap with a live piece offer is placeable. Lemma is not the long-term contract if placement tightens.

### 5.2 `hasLegalMove(state)` — gameplay availability

```
hasLegalMove(S) :=
  S.status == in_progress
  ∧ S.turnsUsed < S.moveLimit
  ∧ hasLegalPlacement(S)
```

Used to decide whether the player may still submit moves. **Must not** be used as the sole check that a claimed `ended` terminal is truthful.

### 5.3 `deriveTerminalExpectation(candidate)` — terminal truth

After schema validation of a candidate post-commit (or initial) board/offers/budget:

```
if turnsUsed >= moveLimit:
  expectedStatus = ended
  expectedReason = move_limit_reached
else if !hasLegalPlacement(candidate):
  expectedStatus = ended
  expectedReason = no_legal_moves
else:
  expectedStatus = in_progress
  expectedReason = null
```

Reject input if claimed `status`/`terminalReason` ≠ expected.

Empty `futurePieces` alone never forces ended.

### 5.4 Mandatory examples (spec)

| # | Candidate | Result |
| --- | --- | --- |
| 1 | Playable offers+cells, claimed `ended/no_legal_moves` | **Reject** (expectation in_progress) |
| 2 | `turnsUsed >= moveLimit`, claimed `in_progress` | **Reject** |
| 3 | All spent / no placement, budget remaining, claimed `in_progress` | **Reject** |
| 4 | No legal placement, budget remaining, claimed `ended/no_legal_moves` | **Accept** |
| 5 | Budget exhausted and no placement | **`move_limit_reached` only** |
| 6 | Valid ended state; `hasLegalMove` query | **false**; terminal truth unchanged |

### 5.5 After a successful applied move

Compute post-commit candidate → set status/reason via §5.3 (same as derive). Never end before cascades+commit complete.

## 6. Offer consumption

Non-empty stream → replace consumed index with `piece` from head. Empty stream → `{kind:spent}` at index only.

## 7. Hashing vs validation vs ranked authority (P0-2)

| Layer | Purpose | Not purpose |
| --- | --- | --- |
| **A. Canonical state hash** | Deterministic bytes; cross-language equality; detect drift vs **trusted** reference | Authenticate attacker-chosen score/board |
| **B. State validation** | Schema, enums, tray shape, terminal consistency (§5.3), numeric bounds | Prove score was earned |
| **C. Authoritative ranked replay** | Pin challenge; replay server-accepted moves; recompute waves/score/terminal; compare to trusted ledger/checkpoint | Trust client `stateHash` |

Client-supplied `stateHash` is never ranked authority. Checkpoints must be server-authenticated and bound to prior replay evidence—not arbitrary client checkpoints.

## 8. Canonical JSON (D5) — byte contract

Gameplay state admits only enumerated ASCII string tokens and JSON numbers that are integers in `-(2^53-1)…(2^53-1)` (gameplay scores/turns additionally ≥ 0).

Algorithm `canonical_json_v3`:

1. Reject floats, `NaN`, `Infinity`, `-0` if distinguishable from `0`, non-integers, out-of-range ints, unknown properties, non-ASCII string contents in state tokens.
2. `null` → bytes `null`. Missing required field → schema error (not hashed).
3. Integers → base-10 ASCII without leading zeros (except `0`), no exponent.
4. Strings → JSON string with `"` and `\` escaped as `\"` and `\\`; control chars U+0000–U+001F as `\u00XX` lowercase hex (not expected in enum tokens; still defined). Reject unpaired surrogates / invalid UTF-8 at ingest.
5. Arrays: preserve order; canonicalize elements.
6. Objects: sort keys by UTF-8 byte lexicographic order; canonicalize values; emit compact form (no insignificant whitespace): `{` `key` `:` `value` `,` … `}`.
7. `stateHash = lowercase hex(SHA-256(UTF-8 bytes of canonical form))`.

Independent minimal digests: see `canonical-v3-test-vectors.md` (**SPECIFIED**). Full GameState digests remain **PENDING_FREEZE**.

Do not define the contract as “whatever `JSON.stringify` / `jsonEncode` does.”

v1/v2 fixture file checksum ledgers unchanged.

## 9. Initial challenges (D10)

`parseInitialGameState` for new v3 challenges must require:

- `status=in_progress`, `terminalReason=null`
- `turnsUsed=0`, `moveLimit≥1`, `score=0`
- Three `piece` offers; `hasLegalPlacement` true
- No unresolved initial match
- Valid geometry/blocked/stream/`rulesVersion`

Impossible initial → fail closed. **Do not** auto-complete as zero-move success.

`parseGameState` may inspect non-initial snapshots but still enforces §5.3 consistency.

## 10. Integer safety (D6)

Before assigning results, both languages must fail closed if any intermediate leaves `0…2^53-1` (or would lose integer exactness):

- `turnsUsed + 1`
- clear counts / wave index
- `uniqueCleared * 100 * wave`
- sum of wave scores
- `score + scoreDelta`
- canonical integer emission

Do not rely on post-hoc parse after silent float/precision loss. Historical v1/v2 arithmetic behavior unchanged on their versions.

## 11. Dart / TypeScript

Dart: v3 dispatch in `puzzle_duel_rules`. TS: new pure replay module. Parity only after freeze protocol (D9).

## 12. Fixtures

See FIXTURE-SPEC. Prose ≠ PASS.

## 13–16. Migration, security, acceptance, decisions

Pin v3 on ranked manifests only after dual-engine parity PASS, historical v1/v2 regression and independent release verification; design acceptance alone is insufficient. Security: replay authority. Acceptance: D1–D10 design approval recorded on 2026-11-17; separate implementation/testing and release gates remain. Decisions table in architecture review.

## Owner decision record — 2026-11-17

The product owner explicitly approved **D1–D10 in their entirety** as defined in the paired revised ADR-E01 and `CORE-001-V3-ARCHITECTURE-REVIEW.md` at backend PR #14 (`91838d9`) and client PR #17 (`1dc16a4`). This decision makes **ADR-E01 Accepted for technical design**. It does **not** authorize merging PRs, implementing or releasing code, marking PZD-39 Done, or declaring Dart/TypeScript parity PASS. Expected v3 golden outputs remain pending freeze. Historical v1/v2 and `gen-001.v1` remain immutable.
