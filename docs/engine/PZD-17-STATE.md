# PZD-17 immutable state and input validation

The first rules module is the pure Dart package [`packages/puzzle_duel_rules`](../../packages/puzzle_duel_rules/README.md). It validates `core-001.v1` and `core-001.v2` state and move documents. It does not place, match, clear, shift, score, or generate a puzzle.

[ADR-001](../adr/ADR-001-client-stack.md) stays Accepted. This change does not accept another ADR and does not edit [the gameplay fixtures](../contracts/gameplay/v1/README.md) or [the v2 terminal-offer suite](../contracts/gameplay/v2/README.md).

## Flutter 3.50 compatibility gate

The gate ran from a disposable Flutter 3.50.0 SDK outside both repositories. Dart in that SDK is 3.14.0. `flutter pub get` resolved Flame 1.38.2. Analysis of a file that constructs `GameWidget` and `ColorEffect` produced one deprecation info for `package:flutter/material.dart` and no analyzer error. The process exit code was 1 because that info is counted.

`ColorScheme`, `TextTheme`, and `FloatingActionButtonLocation` from `material_ui` 1.11.0 are not assignable to the legacy Material types of the same names. The analyzer reported `return_of_invalid_type` for each. A `material_ui` `Color` was accepted by `ColorEffect`.

No Flutter application was created. The pure Dart package was tested with the disposable Dart 3.14.0 SDK.

## Limits that stay open

A parsed move is not a played move. `blocked_tap`, `occupied_tap`, and `game_ended` are not decided. Out-of-bounds tap precedence is not decided.

An empty `futurePieces` list on an `in_progress` state is not rejected here. The reference checkers reject that while applying a move.

One v2 null is accepted only when the saved fields show `ended`, `turnsUsed >= moveLimit`, and an empty future stream. That does not prove the move which wrote the null. An early full board does not gain a synthesized null. A null in that early-end shape is rejected.

These tests do not replay landings, waves, or scores. Checker agreement on the fixtures remains the contract reference. This package is not that replay.
