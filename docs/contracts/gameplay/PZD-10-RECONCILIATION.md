# PZD-10 — Contract reconciliation

Status: implementation record for review. This document does not accept the Blueprint or an ADR. The owner has approved terminal representation A.

Jira: https://puzzle-duel-app.atlassian.net/browse/PZD-10

## Classification

| Finding | Class | Historical `01`–`12` outputs |
| --- | --- | --- |
| PD-07 terminal tray | Normative replay addition, new ruleset `core-001.v2` | Unchanged. v1 checkers still abort when `futurePieces` is empty. They do not invent a piece. |
| PD-08 initial board | Non-breaking additional validation | Unchanged. Full-move starts already had no run of 3. Phase fixtures still may. |
| PD-09 end after cascade | Non-breaking additional regression | Unchanged. New fixture `13-cascade-reopen-end.json` pins the approved cases. `end_conditions` still pins the no-clear fill. |
| PD-10 in-bounds precedence | Non-breaking additional regression | Unchanged. The empty-cell ended tap in `end_conditions` still expects `game_ended`. New taps cover blocked and occupied cells. |
| PD-11 `moved` | No change | Unchanged. Stationary pieces stay omitted. |
| PD-12 cascade termination | Checker safety, not a score cap | Unchanged. Valid cascades still score every wave. The 20-wave stop remains a hang-guard. A non-progressing clear is a separate abort. |
| PD-13 `core-001.v1` | Documentation clarification | Unchanged. The identifier was already the fixture const. |

## PD-07 — terminal offer representation

The owner approved representation A, the nullable spent slot.

Classification: this is not serialization alone. A final legal move that previously had no defined replay result now ends with a concrete tray. PD-13 requires a new rules version when normative replay results change. The new contract is `core-001.v2` under `docs/contracts/gameplay/v2/`. `core-001.v1` golden fixtures `01`–`12` stay byte-identical, and the v1 checkers still abort on an empty stream. No migration of a v1 replay onto v2 is claimed.

v2 rules:

- `offers` stays a three-element array.
- While `status` is `in_progress`, every slot is a playable piece. A null slot in that state is rejected.
- Placement, matching, cascade, and score are resolved before the terminal tray is written.
- JSON `null` is written only when that resolved move reaches `moveLimit` and `futurePieces` is empty. The consumed slot becomes null. The other two slots stay. No piece is generated or copied in.
- Reaching `moveLimit` is the approved final permitted move. Ending only because no empty non-blocked cell remains is a different condition. An empty stream on that early board end does not become a null slot.
- If the stream is empty and the resolved move would leave the game `in_progress`, the checker aborts and does not return an active null tray.
- An ended tray has at most one null. Two or three nulls are rejected. An in-progress tray cannot contain null.
- A later tap on an ended game returns `game_ended` and does not consume an offer or change state.
- Out-of-bounds and malformed coordinates still have no precedence.

Early board end with `futurePieces` empty is not given a tray representation. The checkers abort and leave the caller unchanged. These alternatives are recorded and not chosen:

- Write the same nullable spent slot used for the move-budget final move.
- Leave the consumed piece in its slot and end the game.
- Invent or copy a replacement piece.

PD-07 still does not decide whether an early full-board end drops unused pieces when the stream is not empty. A non-empty stream still follows the existing replenishment step. That is not a new terminal-null rule.

`fixtures/01-terminal-null-slot.json` is the positive case: move limit 1, cascade score 300, slot 0 null, slots 1 and 2 unchanged, then empty, blocked, and occupied taps return `game_ended`. `invalid/null-offer-while-active.json` is the active-null rejection. `invalid/early-board-end-empty-stream.json` is the unspecified early fill. `invalid/terminal-offer-counts.json` covers two nulls, three nulls, an active null, and one valid spent slot. Both checkers also refuse an empty stream on a move that does not end the game.

## PD-08 through PD-12

PD-08 rejection is `unresolved_initial_match` on a full-move start. `invalid/unresolved-initial-match.json` is that negative case. `cross_union` remains a legal match-phase fixture. No generator exists in this repository, so regeneration of an invalid start is not implemented; the checker rejects it. Generator retry policy stays with the later generator specification. Corrupt save recovery is not defined.

PD-09 and PD-10 are pinned by `fixtures/13-cascade-reopen-end.json` plus the existing no-clear scenario in `11-end-conditions.json`. End status is taken from the board and move budget after the cascade. In-bounds ended taps on an empty cell, a blocked cell, and an occupied cell all return `game_ended` with no mutation. Out-of-bounds precedence is not pinned.

PD-12 records a wave only when that clear removes at least three occupied cells and the following shift does not change the occupied count. A valid cascade is therefore at most `floor(occupied / 3)` waves. The synthetic 20-wave check uses a progressing piece field inside the checker. It is not a golden fixture and it is not a gameplay limit. A clear that removes fewer than three pieces aborts as corrupt and is not returned as a verified score.

## Parity

`docs/contracts/gameplay/v1/` and `docs/contracts/gameplay/v2/` are each byte-identical in the client and backend reconciliation branches. Files `01` through `12` are unchanged from the historical v1 suite. v1 checksums change only where the schema description and README were corrected. v2 checksums cover the terminal fixture, the active-null probe, the unspecified early-board probe, and the offer-count probes.
