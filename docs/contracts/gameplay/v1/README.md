# PZD-11 canonical gameplay fixtures v1

Status: fixture suite for review. `rulesVersion` is `core-001.v1`.
Jira: https://puzzle-duel-app.atlassian.net/browse/PZD-11
Rules text: [`../PZD-11-CONTRACT.md`](../PZD-11-CONTRACT.md)

This directory is the language-neutral vector for CORE-001. It is not a game engine, not an API, and not a difficulty profile. Monster, daily-attempt lifecycle, RNG, and all-time rank are outside the suite.

## Contract compliance

PASS against BLUEPRINT `CORE-001`, client `F01`, and the PZD-11 contract for placement, blocking, bounds, orthogonal matches, one-step simultaneous shift, cascade score, and end-of-game. The contract text is byte-identical in the open client and backend specification PRs (see parity below). ADRs that mention replay stay Proposed and are not changed here.

Naming gaps are listed under unresolved decisions. They do not change a pinned landing, clear set, or score.

## Catalog

| File | Contract case | Kind |
| --- | --- | --- |
| `fixtures/01-place-right-free.json` | `place_right_free` | full move |
| `fixtures/02-place-blocked-neighbor.json` | `place_blocked_neighbor` | full move |
| `fixtures/03-place-edge.json` | `place_edge` | full move |
| `fixtures/04-illegal-tap.json` | `illegal_tap` | full move, blocked and occupied |
| `fixtures/05-horizontal-match.json` | `horizontal_match` | full move, one wave plus one survivor step |
| `fixtures/06-cross-union.json` | `cross_union` | match phase |
| `fixtures/07-contested-shift.json` | `contested_shift` | shift phase |
| `fixtures/08-preoccupied-shift.json` | `preoccupied_shift` | shift phase |
| `fixtures/09-blocked-shift.json` | `blocked_shift` | shift phase, edge and blocked cell |
| `fixtures/10-two-wave-cascade.json` | `two_wave_cascade` | full move, two waves |
| `fixtures/11-end-conditions.json` | `end_conditions` | move limit, filled board, post-end tap |
| `fixtures/12-replay-determinism.json` | `replay_determinism` | two-move transcript, multiplier reset |
| `fixtures/13-cascade-reopen-end.json` | `cascade_reopen_end` | last cell reopens; last turn still ends; ended taps |

`invalid/` holds documents the structural check must reject: duplicate or out-of-range obstacles, a bad shape, a bad direction, an illegal turn count, an unknown `rulesVersion`, a piece written on a blocked cell, an offer tray that is not length 3, a piece with an unknown field, and a full-move start that already contains a run of 3. The duplicate obstacle probe is `blocked: [[1,2],[1,2]]`. Match-phase fixtures may contain an intentional run. They are not generated game starts.

Jira's busy-state case is `preoccupied_shift`: the destination is occupied at the start of the shift. CORE-001 does not define a separate busy flag.

## Coordinate and score trace

Rows increase downward. `up` decreases the row, `down` increases it, `left` decreases the column, `right` increases it. `place_right_free` lands on `[2,3]`. `place_edge` stays on `[0,2]` because up leaves the board.

`cells[row][column]` is the stored board. Row-major index is `row * boardSize + column`. Cleared cells are listed row-major. `moved` lists only pieces that change cells, sorted by source index. A wave's `moved` array is the shift caused by that clear. The next wave is the match found after the shift. `turnsUsed` on a step is the absolute total after the step.

| Case | Result |
| --- | --- |
| Free right placement | landing `[2,3]`, 1 turn, score 0, no waves |
| Blocked neighbor | landing `[2,2]`, 1 turn, score 0 |
| Top-edge up | landing `[0,2]`, 1 turn, score 0 |
| Horizontal three | clear `[2,0] [2,1] [2,2]`, wave 1 = 300; survivor triangle moves `[0,0]` to `[0,1]` and does not match |
| Cross | unique cells `[1,2] [2,1] [2,2] [2,3] [3,2]`, score 500, not 600 |
| Contested shift | both claimants stay |
| Preoccupied shift | `[2,1]` stays; the occupant of `[2,2]` steps to empty `[2,3]` |
| Two-wave cascade | wave 1 clears 3 circles for 300 and moves diamond `[4,3]` to `[4,2]`; wave 2 clears 3 diamonds for 600; total 900 |
| Replay move 2 | a new match scores 300 at wave 1 again; cumulative score 600, not 900 |

Hand arithmetic for the cascade is `3*100*1 + 3*100*2 = 900`. Each fixture's `derivation` records the same walk cell by cell.

## Verification

Both checkers use only the language runtime. No package is installed.

```bash
python3 docs/contracts/gameplay/v1/reference_check.py
node docs/contracts/gameplay/v1/validate.mjs
cd docs/contracts/gameplay/v1 && shasum -a 256 -c CHECKSUMS.txt
```

`reference_check.py` replays the thirteen golden files, the cascade hang-guard, the corrupt-cascade check, and the empty-stream refusal.
`validate.mjs` replays them in a separate program, checks structure, checks the ten rejection probes, checks that `fixture.schema.json` enums and closed phase results match the checker, checks the cascade hang-guard, and checks `CHECKSUMS.txt`.

JSON Schema covers document shape, enums, and closed objects. Draft 2020-12 `uniqueItems` compares array elements with deep equality, so `blocked: [[1,2],[1,2]]` is not unique. The schema sets that keyword on blocked coordinates. `validate.mjs` still rejects the same pair itself, because no JSON Schema package is installed. The checker also enforces the cross-field rules the schema does not state: `cells` length equals `boardSize`, blocked cells are empty and row-major, `turnsUsed` does not exceed `moveLimit`, and `status` matches the board.

The two programs do not import each other. They still follow one reading of the contract, so their agreement is not a second source of rules. The `derivation` field on each fixture is the reviewable trace.

Not executed, and not claimed: a Dart client engine, a TypeScript product engine, or backend application tests. Neither repository contains an engine. Cross-repo agreement for this suite is identical file bytes.

## Client / backend parity

Both repositories keep `docs/contracts/gameplay/v1/` byte-identical. From that directory in either checkout:

```bash
shasum -a 256 -c CHECKSUMS.txt
```

Copy the directory unchanged when the two sides drift. Do not edit one copy in place. A rules change needs a new directory such as `v2` after approval. `CHECKSUMS.txt` covers every file in this directory except itself.

The specification markdown was compared, not rewritten:

| File | Git blob | SHA-256 |
| --- | --- | --- |
| `docs/contracts/gameplay/PZD-11-CONTRACT.md` | `23744cda9a5404bf4183ce5ea9590f9f4ee3bf20` | `2fc75b69fc8745886e2f6f59af025dbd4b8dc8928c3ea4ec2ecdd2acbd5bed93` |
| `docs/cursor/PZD-11-HANDOFF.md` | `8ef7a3ec7c0d3ff4bb08157239bd499b847761e8` | `0c0d2d2797834e380ca4be1fbee32805f9dd8d76c5b30abdea490d7f77e36c16` |

Those blobs match client commit `335d2fc69bfd9b44613edc249504ca81876fa353` and backend commit `4c81c6388f591f35f9f6942c62d0cdaa368d9f8b`. `cmp` on the raw files reported identical bytes. Client specification PR: https://github.com/puzzle-duel/puzzle-duel-client/pull/2. Backend specification PR: https://github.com/puzzle-duel/puzzle-duel-backend/pull/2.

PZD-10 appends an amendment to the contract. The current contract blob is `546baf5773c1ea35a85d40dbf2f41227c2f1465e`. Its SHA-256 is `f3028fd01de5694ddc1d3b94877d9f2d64a0bfc355e6e72e726348140e69c4b7`. The table above is the pre-amendment specification.

## Owner amendments and remaining gaps

1. `in_progress` / `ended` and error codes `blocked_tap` / `occupied_tap` / `game_ended` are the names this suite uses. PZD-10 PD-13 approves `rulesVersion` `core-001.v1` as the first official gameplay ruleset identifier. That approval does not freeze these status or error strings as the transport schema. Landings, clears, and scores do not depend on renaming them.
2. What happens to the offer tray when a legal move is played and `futurePieces` is already empty is not chosen. The approved rule is that the supply is fixed before the game and the final permitted move does not require a replacement. No fixture takes that path. If a fixture did, both checkers abort instead of inventing a piece. The abort is not a defined tray representation. The open choice is recorded in `docs/contracts/gameplay/PZD-10-RECONCILIATION.md`.
3. A generated full-move start must not already contain a horizontal or vertical run of 3. The checkers reject that start and do not clear it or award points before the first move. A match-phase fixture may contain an intentional run. Resume of a corrupt saved board is not specified.
4. End is evaluated after matching, clearing, shifting, cascade, and scoring. `cascade_reopen_end` pins a last empty cell that a clear reopens while turns remain, and the same clear on the final permitted turn, which ends because the move limit is exhausted. `end_conditions` still pins a fill that does not clear. The game ends when the resolved board has no empty non-blocked cell or `turnsUsed` has reached `moveLimit`.
5. When the game has already ended, an in-bounds tap on an empty, blocked, or occupied cell returns `game_ended` and does not change the board, score, turns, or offers. Out-of-bounds and malformed coordinates stay unresolved.
6. `moved` omits pieces that stay. The post-shift board shows them. The contract requires source-index order and does not require stay records.
7. The production rules have no maximum wave count. Each recorded clear removes at least three occupied cells, and a shift does not create pieces, so a valid cascade is at most `floor(occupied / 3)` waves. A proposed clear that does not remove three pieces is a corrupt state: both checkers abort and do not record that wave or present a partial score as verified. If a match is still present when 20 progressing waves have already been applied, both checkers abort and do not apply another wave. That 20 is a review hang-guard, not a rule, and no golden fixture depends on it.

Daily attempt lifecycle, RNG, seed versioning, and the all-time rank formula remain Proposed elsewhere and are not decided here.
