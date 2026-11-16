# puzzle_duel_rules

Pure Dart rules package for Puzzle Duel.

Location: `packages/puzzle_duel_rules`. Named by [ADR-001](../../docs/adr/ADR-001-client-stack.md). It does not import Flutter, Flame, or `dart:ui`.

Jira: [PZD-17](https://puzzle-duel-app.atlassian.net/browse/PZD-17), [PZD-18](https://puzzle-duel-app.atlassian.net/browse/PZD-18), [PZD-19](https://puzzle-duel-app.atlassian.net/browse/PZD-19), [PZD-20](https://puzzle-duel-app.atlassian.net/browse/PZD-20), [PZD-21](https://puzzle-duel-app.atlassian.net/browse/PZD-21).

## Public API

| Symbol | Role |
| --- | --- |
| `Coordinate` | Immutable zero-based `[row, column]`. A negative component is rejected. An out-of-bounds tap is still a coordinate. |
| `Piece`, `Shape`, `Direction` | `circle`, `diamond`, `triangle` and `up`, `right`, `down`, `left`. Unknown values and extra fields fail. |
| `GameState` | Immutable `rulesVersion`, `boardSize`, `moveLimit`, `blocked`, `cells`, `offers`, `futurePieces`, `turnsUsed`, `score`, and `status`. |
| `parseGameState` | Structural validation. An orthogonal run already on the board is kept. |
| `parseInitialGameState` | Same checks, and rejects a full-move start that already contains a horizontal or vertical run of 3. |
| `BoardGeometry`, `parseBoard` | Phase-fixture board: ruleset, size, blocked cells, cells, and optional `wave`. A match-phase run is not rejected. |
| `Move`, `parseMove` | `offerIndex` 0, 1, or 2, and a well-formed tap. Parsing a move does not play it. |
| `ValidationFailure` | Deterministic structural codes. It does not carry the rejected document. |
| `applyPlacement` | Placement phase. Returns `PlacementApplied`, `PlacementRejected`, or `PlacementUnsafe`. |
| `PlacementApplied` | Landing, placed piece, post-placement cells, absolute turns, unchanged score, offer-consumption intent. Not a finished move. |
| `GameplayRejection` | `blocked_tap`, `occupied_tap`, `game_ended`. |
| `OfferWillReplace` / `OfferReplacementDeferred` | Post-resolution offer handoff. Terminal null is not written here. |
| `findMatches` / `clearMatches` | Match scan and simultaneous clear. No shift. |
| `applyShift` / `MovedPiece` | Snapshot-based one-cell simultaneous shift. Invalid board/blocked geometry throws `ValidationFailure` first. |
| `resolveAfterPlacement` | Single wave: clear once after placement; shift once only if cleared. |
| `applyMove` | Full CORE-001 resolution: placement, cascades, integer scoring, offer commit, termination. |
| `MoveApplied` / `WaveResult` | Legal full-move outcome and per-wave clear/score/moved records. |
| `MoveRejected` / `MoveUnsafe` | Gameplay rejection or internal fail-closed stop; input state unchanged. Includes `unresolved_pre_move_match` when a resume board already has a run. |
| `generateChallenge` | Accepted `gen-001.v1` deterministic challenge builder (`core-001.v2` ranked output). |
| `Pcg32` / `GeneratedChallenge` | Portable PRNG and outer challenge metadata + immutable `GameState`. |

Details: [`docs/engine/PZD-18-PLACEMENT.md`](../../docs/engine/PZD-18-PLACEMENT.md), [`docs/engine/PZD-19-MATCH-SHIFT.md`](../../docs/engine/PZD-19-MATCH-SHIFT.md), [`docs/engine/PZD-20-RESOLUTION.md`](../../docs/engine/PZD-20-RESOLUTION.md), [`docs/engine/PZD-21-GENERATOR.md`](../../docs/engine/PZD-21-GENERATOR.md).

`core-001.v1` and `core-001.v2` are the only rulesets. Lists returned by a state are unmodifiable copies.

## Full-move resolution

`applyMove` places one piece, clears and shifts until no matches remain, scores each wave as `uniqueClearedCount * 100 * waveNumber`, commits the consumed offer, then sets `ended` when the move budget is exhausted or no unblocked empty cell remains. Cascades are bounded by `floor(occupiedAfterPlacement / 3)`.

## Placement

A legal placement lands one cell forward when that cell is in bounds, empty, and not blocked. Otherwise it lands on the tap. Exactly one turn is consumed. Score is unchanged until resolution. Status is not re-evaluated for board fill in the placement phase alone.

## Match and shift

`clearMatches` unions orthogonal shape runs of length ≥ 3 and clears unique cells once. `applyShift` proposes one neighbor per survivor from the pre-shift snapshot; contested or start-occupied destinations fail.

## Validation

| Check | Code | Where |
| --- | --- | --- |
| Missing or extra JSON field | `missing_field`, `unexpected_property` | State, piece, move, board |
| Ruleset other than v1 or v2 | `unknown_rules_version` | State and board |
| Board size or row shape | `malformed_board` | State and board |
| Coordinate that is not two nonnegative integers | `malformed_coordinate` | Coordinate and move tap |
| Blocked cell malformed or outside the board | `blocked_out_of_range` | State and board |
| Repeated blocked coordinate | `duplicate_blocked` | State and board |
| Blocked list not strictly row-major | `blocked_not_row_major` | State and board |
| Piece on a blocked cell | `blocked_cell_occupied` | State and board |
| Unknown shape or direction, or a non-object piece | `malformed_shape`, `malformed_direction`, `malformed_piece` | Piece, cell, offer, future piece |
| Offer tray length other than 3 | `malformed_offers` | State |
| Null slot on `core-001.v1` | `null_offer` | State |
| Null slot while `in_progress` on v2 | `null_offer_while_active` | State |
| More than one null slot on v2 | `multiple_null_offers` | State |
| One null that is not the documented terminal slot | `null_offer_not_terminal` | State |
| Turn count outside `0..moveLimit` | `illegal_turn_count` | State |
| Score that is not a nonnegative integer | `malformed_score` | State |
| Status that does not match occupancy and the move limit | `inconsistent_status` | State |
| Run of 3 already present on a full-move start | `unresolved_initial_match` | `parseInitialGameState` only |
| Offer index outside 0, 1, 2 | `illegal_offer_index` | Move |

Out-of-bounds taps return `PlacementUnsafe.tapOutOfBounds` / `MoveSafety.tapOutOfBounds` before any gameplay rejection, including when the game has already ended. That is a safety stop for an unspecified case, not a new transport-level precedence decision. In-bounds ended taps still return `game_ended`.

## Commands

From this directory, with Dart 3.14.0:

```bash
dart --version
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```

## Flutter 3.50 gate

Evidence remains in [`docs/engine/PZD-17-STATE.md`](../../docs/engine/PZD-17-STATE.md). This package still has no Flutter or Flame dependency.

## CI

`.github/workflows/dart-rules.yml` runs the package commands on Ubuntu when this package or that workflow changes. It is path-filtered and must not be a required status until it runs on every pull request.
