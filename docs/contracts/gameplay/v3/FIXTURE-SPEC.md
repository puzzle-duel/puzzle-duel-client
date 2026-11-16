# CORE-001.v3 golden fixture specification

Status: **Proposed** — expected outputs must be frozen after independent review, not copied from one engine.
Rules version: `core-001.v3`
Sibling historical suites remain immutable: `../v1/`, `../v2/`.

## Format

Each fixture JSON document:

| Field | Description |
| --- | --- |
| `id` | Stable snake_case id |
| `number` | Integer catalogue number |
| `kind` | `fullMove` \| `parseOnly` \| `hashOnly` \| `regression` |
| `rulesVersion` | `core-001.v3` (or historical for regression wrappers) |
| `summary` | Human description |
| `scenarios[]` | `given.state`, optional `when.moves`, `expected` |

`expected` for successful moves must include: per-step `legal`, `landing`, `turnsUsed`, `scoreDelta`, `waves`, `finalState` (full canonical state including `terminalReason`), and `stateHash` (SHA-256 of canonical final state JSON).

Reject/unsafe scenarios must include unchanged `state` and code/reason.

## Catalogue

| ID | Scenario | Expected invariant |
| --- | --- | --- |
| V3-01 | Normal legal placement | Valid state; scoreDelta 0 if no match; stream advances |
| V3-02 | Single-wave clear | `scoreDelta = uniqueCleared*100*1` |
| V3-03 | Multi-wave cascade | Full resolution before terminal; wave multipliers reset per move |
| V3-04 | Board becomes full | `ended` + `no_legal_moves` (or move_limit if simultaneous — precedence: evaluate move_limit first) |
| V3-05 | Cascade reopens space | Remains `in_progress` if budget and legal move remain |
| V3-06 | Stream empty, active piece offers remain | Not terminal solely due to empty stream |
| V3-07 | No legal move with empty cells | All offers `spent` (or equivalent); `no_legal_moves`; score preserved |
| V3-08 | Consumed offer, no replacement | Slot becomes `{kind:spent}`; others unchanged |
| V3-09 | Move budget exhausted | `move_limit_reached` |
| V3-10 | No available offers remain | Same as V3-07 natural completion |
| V3-11 | Illegal placement | Reject; zero mutation |
| V3-12 | Corrupted terminal proof | Fail closed (hash/reason mismatch) |
| V3-13 | Malformed tray | Fail closed (`malformed_offers` / unknown kind / bare null) |
| V3-14 | Corrupt initial state | `parseInitialGameState` rejects |
| V3-15 | Duplicate finalization | Idempotent identical terminal envelope |
| V3-16 | Serialize/parse round-trip | Canonical equality + hash stable |
| V3-17 | Historical v1 fixtures | Unchanged bytes / checksums |
| V3-18 | Historical v2 fixtures | Unchanged bytes / checksums |
| V3-19 | v2 early-board-end-empty-stream | Historical fail-closed preserved |
| V3-20 | Equivalent v3 early natural terminal | Board-full or no-legal-move succeeds under v3 |

### Additional edge cases from source audit

| ID | Scenario | Notes |
| --- | --- | --- |
| V3-21 | Pre-move unresolved match | `MoveUnsafe.unresolved_pre_move_match`; no score |
| V3-22 | Select spent slot | `offer_unavailable`; unchanged |
| V3-23 | Ended then in-bounds empty tap | `game_ended` |
| V3-24 | Handoff-irrelevant | Engine ignores writer/deadline fields (must not appear in state) |
| V3-25 | Generator pin | Challenge JSON with `rulesVersion: core-001.v3` parses; `gen-001.v1` RNG unchanged |

## Fixture authoring rules

1. Do not edit v1/v2 files or their `CHECKSUMS.txt`.
2. v3 expected boards/scores should be derived by dual independent references (Dart + TS) after implementation Stage B/C, then frozen.
3. Until freeze, this catalogue defines **oracles in prose**; JSON bodies may be scaffolds marked `"expected": {"status": "PENDING_FREEZE"}`.
4. Cross-repo copies must be byte-identical when published.

## Proposed directory layout

```
docs/contracts/gameplay/v3/
  README.md
  FIXTURE-SPEC.md          (this file)
  fixture.schema.json      (after ADR Acceptance)
  fixtures/                (after freeze)
  invalid/
  CHECKSUMS.txt            (after freeze)
  reference_check.py       (optional checker; not a product engine)
  validate.mjs
```
