# PZD-10 — Contract reconciliation

Status: implementation record for review. This document does not accept the Blueprint, accept an ADR, or choose the terminal offer representation.

Jira: https://puzzle-duel-app.atlassian.net/browse/PZD-10

## Classification

| Finding | Class | Historical `01`–`12` outputs |
| --- | --- | --- |
| PD-07 terminal tray | Blocked representation choice | Unchanged. Checkers still abort when `futurePieces` is empty. They do not invent a piece. |
| PD-08 initial board | Non-breaking additional validation | Unchanged. Full-move starts already had no run of 3. Phase fixtures still may. |
| PD-09 end after cascade | Non-breaking additional regression | Unchanged. New fixture `13-cascade-reopen-end.json` pins the approved cases. `end_conditions` still pins the no-clear fill. |
| PD-10 in-bounds precedence | Non-breaking additional regression | Unchanged. The empty-cell ended tap in `end_conditions` still expects `game_ended`. New taps cover blocked and occupied cells. |
| PD-11 `moved` | No change | Unchanged. Stationary pieces stay omitted. |
| PD-12 cascade termination | Checker safety, not a score cap | Unchanged. Valid cascades still score every wave. The 20-wave stop remains a hang-guard. A non-progressing clear is a separate abort. |
| PD-13 `core-001.v1` | Documentation clarification | Unchanged. The identifier was already the fixture const. |

## PD-07 — terminal offer representation (not implemented)

Approved behavior: the ordered supply is fixed before the game, it is sufficient for the move budget, nothing is generated on demand, and the final permitted move does not need a replacement. Official participants share that versioned sequence.

Current v1 serialization cannot express the final move. `offers` has length exactly 3. Both checkers replace the used slot from `futurePieces` and abort when that list is empty. Fixture `11-end-conditions.json` still has a spare future piece on its last legal move, so its bytes stay valid.

No approved document chooses among these incompatible terminal representations:

1. **Nullable spent slot.** `offers` stays length 3. After the final permitted move, the used slot becomes `null` when no future piece remains. Earlier in-progress states still hold three pieces.
2. **Shorter tray.** The used slot is removed, so `offers` length becomes 2. This breaks the length-3 invariant on the terminal state.
3. **Keep the used piece.** The slot still shows the piece just played. A reader cannot tell a spent slot from a piece that is still offered.
4. **Drop `offers` on the terminal state.** The required state field disappears.

Recommendation: **nullable spent slot**, only for the legal move that exhausts the stream. It keeps three positions for active play, does not invent a piece, and is visibly different from an offered piece. Historical fixtures never take this path, so their outputs can stay byte-identical under `core-001.v1`.

This recommendation is not implemented. Implementing any of the four would change replay output for that move and needs an owner decision before a versioned fixture is added.

Positive coverage of a completed final move with an empty stream is therefore absent. Negative coverage is present: an otherwise legal move with `futurePieces: []` aborts, and the caller state is not rewritten with a filler piece.

## PD-08 through PD-12

PD-08 rejection is `unresolved_initial_match` on a full-move start. `invalid/unresolved-initial-match.json` is that negative case. `cross_union` remains a legal match-phase fixture. No generator exists in this repository, so regeneration of an invalid start is not implemented; the checker rejects it. Generator retry policy stays with the later generator specification. Corrupt save recovery is not defined.

PD-09 and PD-10 are pinned by `fixtures/13-cascade-reopen-end.json` plus the existing no-clear scenario in `11-end-conditions.json`. End status is taken from the board and move budget after the cascade. In-bounds ended taps on an empty cell, a blocked cell, and an occupied cell all return `game_ended` with no mutation. Out-of-bounds precedence is not pinned.

PD-12 records a wave only when that clear removes at least three occupied cells and the following shift does not change the occupied count. A valid cascade is therefore at most `floor(occupied / 3)` waves. The synthetic 20-wave check uses a progressing piece field inside the checker. It is not a golden fixture and it is not a gameplay limit. A clear that removes fewer than three pieces aborts as corrupt and is not returned as a verified score.

## Parity

`docs/contracts/gameplay/v1/` is byte-identical in the client and backend reconciliation branches. Files `01` through `12` are unchanged from main. Checksums cover the added fixture and probe.
