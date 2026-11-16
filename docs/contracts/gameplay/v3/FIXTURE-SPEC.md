# CORE-001.v3 golden fixture specification

Status: **Proposed catalogue — executable vectors NOT frozen**
Companion review: `docs/engine/CORE-001-V3-ARCHITECTURE-REVIEW.md`

**Important:** A prose catalogue is **not** executable Dart/TypeScript parity. Until Stage D freeze, expected boards/hashes are `PENDING_FREEZE`.

## Format

| Field | Description |
| --- | --- |
| `id` / `number` / `kind` / `rulesVersion` / `summary` | Metadata |
| `scenarios[]` | `given`, optional `when.moves`, `expected` |
| `expected.stateHash` | SHA-256 of `canonical_json_v3(finalState)` once frozen |
| `expected.status` | May be `PENDING_FREEZE` before dual-engine agreement |

## Freeze protocol

1. Implement Dart + TS v3 independently.  
2. Run the same inputs; require byte-identical canonical states and hashes.  
3. Write fixture bodies + `CHECKSUMS.txt`.  
4. Re-run historical v1/v2 checksums unchanged.  
5. Only then claim golden parity PASS.

## Catalogue

| ID | Scenario | Expected invariant | Freeze |
| --- | --- | --- | --- |
| V3-01 | Normal legal placement | Valid state; stream advances if non-empty | PENDING_FREEZE |
| V3-02 | Single-wave clear | `scoreDelta = uniqueCleared*100*1` (hand-checkable arithmetic) | ARITH_OK / board PENDING_FREEZE |
| V3-03 | Multi-wave cascade | Full resolution before terminal; per-move wave reset | PENDING_FREEZE |
| V3-04 | Board becomes full | `ended`; reason `no_legal_moves` unless move-limit also true → then `move_limit_reached` | PENDING_FREEZE |
| V3-05 | Cascade reopens space | `in_progress` if budget + legal move remain | PENDING_FREEZE |
| V3-06 | Empty stream, playable piece offers | Not terminal solely due to empty stream | PENDING_FREEZE |
| V3-07 | No legal move; empty cells remain | All offers `spent`; `no_legal_moves`; score preserved | PENDING_FREEZE |
| V3-08 | Consume with empty stream | Slot → `{kind:spent}`; others unchanged | PENDING_FREEZE |
| V3-09 | Move budget exhausted | `move_limit_reached` | PENDING_FREEZE |
| V3-10 | No available offers remain | Natural `no_legal_moves` | PENDING_FREEZE |
| V3-11 | Illegal placement | Reject; zero mutation | PENDING_FREEZE |
| V3-12 | Corrupted terminal proof | Fail closed | PENDING_FREEZE |
| V3-13 | Malformed tray / bare null / unknown kind | Parse fail closed | PENDING_FREEZE |
| V3-14 | Corrupt initial state | `parseInitialGameState` rejects | PENDING_FREEZE |
| V3-15 | Duplicate finalization | Identical terminal envelope | PENDING_FREEZE |
| V3-16 | Serialize/parse round-trip | Canonical equality + stable hash | PENDING_FREEZE |
| V3-17 | Historical v1 fixtures | Unchanged bytes/checksums | **Historical ledger** |
| V3-18 | Historical v2 fixtures | Unchanged bytes/checksums | **Historical ledger** |
| V3-19 | v2 early-board-end-empty-stream | Historical fail-closed preserved | **Historical** |
| V3-20 | v3 early natural terminal | Board-full / no-legal success under v3 | PENDING_FREEZE |
| V3-21 | Pre-move unresolved match | `MoveUnsafe`; no score | PENDING_FREEZE |
| V3-22 | Select spent slot | `offer_unavailable`; unchanged | PENDING_FREEZE |
| V3-23 | Ended then empty tap | `game_ended` | PENDING_FREEZE |
| V3-24 | Multiple spent slots mid-game | Valid `in_progress` if a piece offer + empty cell remain | PENDING_FREEZE |
| V3-25 | Last playable offer consumed | Ends `no_legal_moves` if no other piece offers / cells | PENDING_FREEZE |
| V3-26 | Move-limit and no-legal-move simultaneous | Reason **`move_limit_reached` only** | PENDING_FREEZE |
| V3-27 | Malformed piece / extra properties | Parse reject | PENDING_FREEZE |
| V3-28 | Duplicate/invalid blocked | Parse reject | PENDING_FREEZE |
| V3-29 | Integer overflow / non-int score | Parse reject | PENDING_FREEZE |
| V3-30 | JSON key-order independence | Same `stateHash` for permuted keys | PENDING_FREEZE |
| V3-31 | Version-dispatch mismatch | v3 rules on v2 state rejected / not reinterpreted | PENDING_FREEZE |
| V3-32 | Forged terminalReason on in_progress | Parse reject | PENDING_FREEZE |
| V3-33 | Spent slot while stream non-empty (corrupt) | Invariant/parse reject | PENDING_FREEZE |
| V3-34 | Repeated terminal evaluation | Idempotent ended snapshot | PENDING_FREEZE |
| V3-35 | Cross-language hash parity | Dart hash == TS hash | PENDING_FREEZE (Stage D) |

## Directory layout (after Acceptance / freeze)

```
docs/contracts/gameplay/v3/
  README.md
  FIXTURE-SPEC.md
  fixture.schema.json
  fixtures/
  invalid/
  CHECKSUMS.txt
  reference_check.py   # optional; not a product engine
  validate.mjs
```
