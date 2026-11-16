# PZD-20 cascades, scoring, and termination

Jira: [PZD-20](https://puzzle-duel-app.atlassian.net/browse/PZD-20).

Package: [`packages/puzzle_duel_rules`](../../packages/puzzle_duel_rules/README.md).

This task completes the pure Dart CORE-001 move engine. It reuses PZD-17 state validation, PZD-18 placement, and PZD-19 match/shift without inventing new product rules.

## Public API

| Symbol | Role |
| --- | --- |
| `applyMove(GameState, Move)` | Full-move entry point. |
| `MoveApplied` | Legal outcome: `landing`, absolute `turnsUsed`, `scoreDelta`, `waves`, validated `finalState`. |
| `WaveResult` | One clearing wave: `wave`, `cleared`, `scoreDelta`, `moved`. |
| `MoveRejected` | Approved gameplay codes with the unchanged input state. |
| `MoveUnsafe` | Internal fail-closed stop with [MoveSafety] and the unchanged input. |

Results and nested collections are deeply immutable. The UI must not recalculate rules.

## Resolution lifecycle

1. Call `applyPlacement`.
2. On rejection or placement safety stop, map to `MoveRejected` / `MoveUnsafe` and stop.
3. After a placement request is accepted, if the **pre-move** `state.hasOrthogonalRun` is true, fail closed with `MoveSafety.unresolvedPreMoveMatch`. Do not cascade, score, commit offers, or return `MoveApplied`.
4. Scan matches with `clearMatches` on the post-placement board.
5. If no match, skip shift and end the cascade.
6. On a match, clear unique cells once, score the wave, then `applyShift` once.
7. Rematch the shifted board. Repeat until no matches remain.
8. Commit offer replacement from PZD-18 `OfferConsumption`.
9. Evaluate terminal status only after cascades and offer commit.
10. Construct `GameState`, reject residual matches, round-trip through `parseGameState`.
11. Return `MoveApplied`.

No global shift without a clear. Input state is never mutated.

## Corrupt pre-move / resume boundary

`parseGameState` may keep an existing orthogonal run (structural resume / inspection). `parseInitialGameState` rejects the same board with `unresolved_initial_match`.

`applyMove` follows the initial-move integrity rule for scoring: once placement would otherwise proceed, an unresolved pre-move run is an internal integrity failure (`unresolved_pre_move_match`), not a gameplay/transport rejection. Board, score, turns, offers, future pieces, rules version, and status stay unchanged. Approved codes `game_ended`, `blocked_tap`, and `occupied_tap`, plus out-of-bounds safety stops, still take effect first when placement rejects or stops before this check.

## Cascade bound

A successful clear removes at least three occupied pieces. Movement never adds pieces. After placement, the maximum number of valid clearing waves is:

`floor(occupiedPieceCountAfterPlacement / 3)`

That is a mathematical safety bound, not a gameplay wave cap. Fail closed when:

- a clear would remove fewer than three occupied pieces
- occupied count does not drop by the unique clear count
- another clear would exceed the proven bound
- shift geometry fails PZD-17 validation
- a shift overwrite is attempted
- the final state is invalid or still contains a match

No partial score or partial commit is returned after an internal failure.

## Scoring

Integer arithmetic only. For wave `n` (starting at 1 each player move):

`waveScore = uniqueClearedCount * 100 * n`

`scoreDelta` is the sum of wave scores. `finalState.score = original.score + scoreDelta`.

Placement alone, directional movement alone, rejected moves, and empty match phases do not score.

## Offer commit

| Case | Behavior |
| --- | --- |
| Non-empty future stream | Replace only the consumed slot with the first future piece; drop that one stream head. |
| `core-001.v1` empty stream | Fail closed (`empty_stream_not_terminal`). Do not invent a piece. |
| `core-001.v2` empty stream and `turnsUsed >= moveLimit` | After cascades, write JSON `null` into only the consumed slot; tray length stays 3. |
| `core-001.v2` empty stream and early board-full | Fail closed (`early_board_end_empty_stream`). No invented tray. |
| Continuing v2 game | Must not contain null offers. |

Never migrate v1 input into v2 during gameplay.

## Termination timing

Evaluate only after complete cascade resolution (and offer commit):

- `turnsUsed >= moveLimit`, or
- no unblocked empty cell remains → `ended`
- otherwise → `in_progress`

A clear that reopens space can keep the game `in_progress` when turns remain. Reaching the move limit still ends the game even if cells reopen. Already-ended in-bounds taps return `game_ended` without mutation. Out-of-bounds precedence stays the PZD-18 internal safety stop.

## Failure atomicity

`MoveRejected` and `MoveUnsafe` always carry the original unchanged state. Successful paths validate the final snapshot before returning. Callers never receive a half-applied board with a claimed score. An unresolved pre-move match yields no waves, no score delta, and no offer consumption.

## Golden fixture coverage

| Fixture | Dart engine coverage |
| --- | --- |
| v1 01–03 | Legal placement without match; offer replacement; `scoreDelta = 0` |
| v1 04 | Illegal taps; unchanged state |
| v1 05 | One-wave clear, survivor shift, score 300 |
| v1 06–09 | Phase helpers remain covered by PZD-19 tests |
| v1 10 | Two-wave cascade; 300 + 600 = 900; diamond `sourceIndex` 23 |
| v1 11 | Move-limit end; board-full end; post-end rejection |
| v1 12 | Two-move replay; wave multiplier reset; deep equality |
| v1 13 | Reopen after clear; later move-limit end |
| v2 01 | Terminal null offer after final permitted move |
| v2 early-board-end-empty-stream | Fail closed without inventing a tray |

Canonical fixture bytes and checksums are unchanged. Python/Node checkers are not a substitute for Dart golden parity.

## Known unresolved contract boundaries

- Out-of-bounds / malformed tap transport precedence remains unspecified; PZD-18 safety stops are preserved, not promoted to product codes.
- An early board-full end with an empty v2 stream has no approved tray representation.
- Challenge generation, Flutter UI, and backend replay remain out of scope.
