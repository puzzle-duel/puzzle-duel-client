# PZD-18 directional placement

Jira: [PZD-18](https://puzzle-duel-app.atlassian.net/browse/PZD-18).

Package: [`packages/puzzle_duel_rules`](../../packages/puzzle_duel_rules/README.md).

This task adds the placement phase only. Match, clear, simultaneous shift, cascade, scoring, and final end evaluation remain for later work.

## Public API

| Symbol | Role |
| --- | --- |
| `applyPlacement(GameState, Move)` | Placement phase entry point. |
| `PlacementApplied` | Landing, placed piece, post-placement cells, absolute `turnsUsed`, unchanged score, and offer-consumption intent. |
| `PlacementRejected` | Approved gameplay codes `blocked_tap`, `occupied_tap`, `game_ended` with the unchanged input state. |
| `PlacementUnsafe` | Safety stops `tap_out_of_bounds` and `offer_unavailable`. Not transport gameplay codes. |
| `OfferWillReplace` | After later resolution, replace only `offerIndex` with the first future piece. |
| `OfferReplacementDeferred` | Empty future stream. Do not invent a piece or write a terminal null here. |

`PlacementApplied` is not a finished `GameState`. It does not claim `ended` after filling the last empty cell. A later clear may reopen space.

## Placement rules

1. If the tap is outside the board, stop as `PlacementUnsafe.tapOutOfBounds` and leave state unchanged. This runs whether the game is `in_progress` or `ended`. It is a safety stop for an unspecified out-of-bounds case, not an approved transport-level precedence over `game_ended`.
2. For an in-bounds tap when `status` is already `ended`, reject with `game_ended`, including empty, blocked, or occupied cells. Board, offers, future pieces, turns, and score stay unchanged.
3. Reject a blocked tap (`blocked_tap`) or occupied tap (`occupied_tap`) without changing state.
4. Compute one adjacent cell from the selected piece direction.
5. If that cell is in bounds, empty, and not blocked, land there. Otherwise land on the tap.
6. Never search farther than one cell. Direction does not change.
7. Increment turns by exactly one. Score is unchanged until a later scoring phase.

## Offer handoff

Reference checkers replace the consumed offer after match, clear, shift, cascade, and score. This package records the same intent:

- Non-empty `futurePieces` → `OfferWillReplace`.
- Empty `futurePieces` → `OfferReplacementDeferred`. V1 must abort rather than invent a piece. V2 may write one terminal null only after resolution when the move reaches `moveLimit`. Early board-full with an empty stream stays unspecified.

No random generation. Other offer slots are not rewritten by this phase.

## Limits

- Out-of-bounds and malformed tap precedence is not an approved product rule. This package stops an out-of-bounds tap with `PlacementUnsafe` so it never becomes `game_ended`, `blocked_tap`, or `occupied_tap`. That does not invent a transport schema decision for those cases.
- Golden fixture `finalState` includes post-resolution offers, waves, and status. Placement-only projection may match landing and turns while full-move parity remains **NOT_RUN**.
- Flutter UI and backend replay are out of scope.
