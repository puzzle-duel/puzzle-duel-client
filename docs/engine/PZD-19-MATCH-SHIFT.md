# PZD-19 match clear and simultaneous shift

Jira: [PZD-19](https://puzzle-duel-app.atlassian.net/browse/PZD-19).

Package: [`packages/puzzle_duel_rules`](../../packages/puzzle_duel_rules/README.md).

This task adds match detection, simultaneous clear, and one-cell simultaneous shift. It does not rematch, cascade, score, commit offer replacement, or decide game end.

## Public API

| Symbol | Role |
| --- | --- |
| `findMatches` | Unique matching coordinates in ascending row-major order. Shape only. |
| `clearMatches` | Returns `MatchClearResult`: original board, cleared cells, board after clear. No shift. |
| `applyShift` | One simultaneous shift from a pre-shift snapshot. Returns `ShiftResult`, or throws [ValidationFailure] before any move. |
| `MovedPiece` | `sourceIndex`, `from`, `to`, `shape`, `direction` for pieces that moved. |
| `resolveAfterPlacement` | After `PlacementApplied`: clear once; if cleared, shift once. |

Direct match and shift remain independently callable. A direct match phase does not shift.

## Match and clear

1. Require a non-empty square cell matrix. Empty or jagged boards throw `ValidationFailure` with `malformed_board` and invent no matches.
2. Scan the complete original board.
3. Horizontal and vertical runs of length ≥ 3 with the same `Shape`.
4. Direction does not matter. Diagonals are ignored.
5. Union overlapping runs. Each cell appears once.
6. Order cleared coordinates row-major.
7. Clear every unique cell at the same time.

## Shift

1. Before proposals, validate the square board and blocked list with the same PZD-17 codes used by state parsing: `malformed_board`, `blocked_out_of_range`, `duplicate_blocked`, `blocked_not_row_major`, and `blocked_cell_occupied`.
2. A piece sitting on a blocked cell fails closed. No `ShiftResult` and no movement records are produced. The caller matrix is not mutated.
3. Snapshot occupancy before any move.
4. Each survivor proposes exactly one neighbor from its direction.
5. Reject out-of-bounds, blocked, or start-occupied targets.
6. If two or more pieces claim one free cell, every claimant stays.
7. Apply accepted moves only after proposal evaluation.
8. Emit `MovedPiece` only for pieces that changed cells, sorted by `sourceIndex`.
9. No gravity, swaps, chain-following, or second step.

## Placement handoff toward PZD-20

`resolveAfterPlacement` is the smallest single-wave bridge:

1. Placement board from PZD-18.
2. Match/clear on that board.
3. One shift only when a clear happened.
4. Offer replacement, score, rematch, and end stay deferred.

Zero matches → `shift == null` (no survivor movement).

## Fixture coverage

| Fixture | Coverage |
| --- | --- |
| 05 | Placement → clear `[2,0][2,1][2,2]` → triangle `sourceIndex 0` to `[0,1]` |
| 06 | Five unique clears; no shift in the match phase |
| 07 | Contested destination; empty `moved` |
| 08 | Preoccupied destination; diamond `sourceIndex 12` only |
| 09 | Edge and blocked destinations; empty `moved` |

Full-move score deltas, offer commit, and `finalState` parity are implemented in [PZD-20-RESOLUTION.md](PZD-20-RESOLUTION.md).

## Deferred

- Flutter UI and backend replay.
