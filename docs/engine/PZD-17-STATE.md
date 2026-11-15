# PZD-17 immutable state and input validation

The first rules module is the pure Dart package [`packages/puzzle_duel_rules`](../../packages/puzzle_duel_rules/README.md). It validates `core-001.v1` and `core-001.v2` state and move documents. It does not place, match, clear, shift, score, or generate a puzzle.

[ADR-001](../adr/ADR-001-client-stack.md) stays Accepted. This change does not accept another ADR and does not edit [the gameplay fixtures](../contracts/gameplay/v1/README.md) or [the v2 terminal-offer suite](../contracts/gameplay/v2/README.md).

## Flutter 3.50 compatibility gate

Ran outside both repositories. Not committed. Flutter 3.50.0, framework `ab2912035e`, Dart 3.14.0. `flutter pub get` locked Flame 1.38.2 and `material_ui` 1.11.0.

### Positive control: `GameWidget` and `ColorEffect`

Command without flags:

```text
flutter analyze lib/gate.dart
exit 1
errors 0
warnings 0
infos 1
```

The single info is `deprecated_member_use` on `package:flutter/material.dart`. That command is **not** PASS. Exit code 1 is the recorded result.

Command with infos non-fatal (supported on this SDK):

```text
flutter analyze --no-fatal-infos lib/gate.dart
exit 0
errors 0
warnings 0
infos 1
```

That command is **PASS** for the positive `GameWidget` / `ColorEffect` check. The deprecation info remains recorded. It is not treated as an analyzer error.

### Negative control: `material_ui` versus legacy Material public types

Separate file. Intentionally assigns `material_ui` `ColorScheme`, `TextTheme`, and `FloatingActionButtonLocation` where the legacy Material library expects its own types.

```text
flutter analyze lib/boundary_public.dart
exit 1
errors 3
warnings 0
infos 1
```

The three errors are `return_of_invalid_type`. Those public types are not interchangeable. This negative control is expected to fail and is not the positive gate.

A separate check passes a `material_ui` `Color` into Flame `ColorEffect`:

```text
flutter analyze lib/boundary.dart
exit 0
errors 0
warnings 0
infos 0
```

### First-party scaffold implication

Any first-party signature that must assign `material_ui` `ColorScheme`, `TextTheme`, or `FloatingActionButtonLocation` to the legacy Material types of the same names remains **FAIL**. Avoid those crossings or wait for remediation before application scaffolding. `Color` into `ColorEffect` is not that failure. No Flutter application was created by this task.

The pure Dart package was tested with the disposable Dart 3.14.0 SDK.

## Limits that stay open

A parsed move is not a played move. `blocked_tap`, `occupied_tap`, and `game_ended` are not decided. Out-of-bounds tap precedence is not decided.

An empty `futurePieces` list on an `in_progress` state is not rejected here. The reference checkers reject that while applying a move.

One v2 null is accepted only when the saved fields show `ended`, `turnsUsed >= moveLimit`, and an empty future stream. That does not prove the move which wrote the null. An early full board does not gain a synthesized null. A null in that early-end shape is rejected.

These tests do not replay landings, waves, or scores. Checker agreement on the fixtures remains the contract reference. This package is not that replay.
