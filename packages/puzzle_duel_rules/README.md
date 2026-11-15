# puzzle_duel_rules

Pure Dart game-state and input-validation package for Puzzle Duel.

Location: `packages/puzzle_duel_rules`. It is the first rules module named by [ADR-001](../../docs/adr/ADR-001-client-stack.md). It does not place a piece, match, clear, shift, score, or generate a board. It does not import Flutter, Flame, or `dart:ui`.

Jira: [PZD-17](https://puzzle-duel-app.atlassian.net/browse/PZD-17).

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

`core-001.v1` and `core-001.v2` are the only rulesets. Lists returned by a state are unmodifiable copies.

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

`blocked_tap`, `occupied_tap`, and `game_ended` are not produced. Out-of-bounds and malformed tap precedence is not decided here. A tap such as `[99, 4]` is a valid move model.

A v2 null slot is accepted only when `status` is `ended`, `turnsUsed >= moveLimit`, `futurePieces` is empty, and the tray has exactly one null. That is the visible form of the documented final-turn empty-stream slot. This package does not prove which move wrote the null.

## What this package does not decide

- An `in_progress` state may have an empty `futurePieces` list. The reference checkers reject that only while applying a move. Move execution is not implemented.
- An ended board with turns still remaining, an empty future stream, and three pieces can match the status rule. That is not approval of the early board-full transition. A null synthesized for that case is rejected. The early-board fixture is parsed and left without a null slot.
- No replacement piece is generated. No v1 state gains a null offer.
- A green test run is not golden gameplay parity. Placement and resolution are not implemented.

## Commands

From this directory, with Dart 3.14.0:

```bash
dart --version
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```

The local machine's Flutter 3.47.8 / Dart 3.13.7 is not the SDK used for those commands. The verification SDK is a disposable Dart 3.14.0 install outside this repository.

## Flutter 3.50 gate

Ran outside this repository and not committed. `flutter --version` reported Flutter 3.50.0, framework `ab2912035e`, Dart 3.14.0. `flutter pub get` locked `flame` 1.38.2 and `material_ui` 1.11.0.

`flutter analyze lib/gate.dart` named `GameWidget` and `ColorEffect`. It reported one info, `deprecated_member_use`, on `package:flutter/material.dart`, and no error. The process exit code was 1 because the analyzer counts that info. [ADR-001](../../docs/adr/ADR-001-client-stack.md) records a deprecation info and fails the gate on an analyzer error. No error was reported for those two APIs.

A separate file returned `material_ui` `ColorScheme`, `TextTheme`, and `FloatingActionButtonLocation` where the legacy Material library expected its own types. `flutter analyze` reported three `return_of_invalid_type` errors. Those public types are not interchangeable. `Color` passed into `ColorEffect` from `material_ui` produced no diagnostic.

No Flutter application or Flame dependency was added to this repository.

## CI

`.github/workflows/dart-rules.yml` runs the commands above on Ubuntu when this package or that workflow changes. It requests `contents: read`, uses no secrets, and does not use a macOS runner. It is path-filtered, so it must not be a required status until it runs on every pull request.

The fixture workflow and the pull-request quality gate are unchanged in purpose. The quality gate's text scan includes `.dart` so this package is not skipped. The backend repository was not modified, so its copy of that scanner does not yet list `.dart`.
