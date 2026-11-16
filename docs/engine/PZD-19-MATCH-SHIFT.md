# PZD-19 match clear and simultaneous shift

Jira: [PZD-19](https://puzzle-duel-app.atlassian.net/browse/PZD-19).

Package: [`packages/puzzle_duel_rules`](../../packages/puzzle_duel_rules/README.md).

This task adds match detection, simultaneous clear, and one-cell simultaneous shift. It does not rematch, cascade, score, commit offer replacement, or decide game end.

## Public API

| Symbol | Role |
| --- | --- |
| `findMatches` | Unique matching coordinates in ascending row-major order. Shape only. |
| `clearMatches` | Returns `MatchClearResult`: original board, cleared cells, board after clear. No shift. |
| `applyShift` | One simultaneous shift from a pre-shift snapshot. Returns `ShiftResult`. |
| `MovedPiece` | `sourceIndex`, `from`, `to`, `shape`, `direction` for pieces that moved. |
| `resolveAfterPlacement` | After `PlacementApplied`: clear once; if cleared, shift once. |

Direct match and shift remain independently callable. A direct match phase does not shift.

## Match and clear

1. Scan the complete original board.
2. Horizontal and vertical runs of length ≥ 3 with the same `Shape`.
3. Direction does not matter. Diagonals are ignored.
4. Union overlapping runs. Each cell appears once.
5. Order cleared coordinates row-major.
6. Clear every unique cell at the same time.

## Shift

1. Snapshot occupancy before any move.
2. Each survivor proposes exactly one neighbor from its direction.
3. Reject out-of-bounds, blocked, or start-occupied targets.
4. If two or more pieces claim one free cell, every claimant stays.
5. Apply accepted moves only after proposal evaluation.
6. Emit `MovedPiece` only for pieces that changed cells, sorted by `sourceIndex`.
7. No gravity, swaps, chain-following, or second step.

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

Score deltas and full-move `finalState` parity remain **NOT_RUN**.

## Deferred

- Cascade rematch loops and wave multipliers (PZD-20).
- Score accumulation and offer commit.
- Final `ended` evaluation after resolution.
- Flutter UI and backend replay.
