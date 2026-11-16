# Puzzle Duel Client

Flutter/Flame iOS and Android client for Puzzle Duel.

## Layout

| Path | Role |
| --- | --- |
| `apps/mobile/` | Flutter application (`puzzle_duel_mobile`) |
| `packages/puzzle_duel_rules/` | Pure Dart rules + `gen-001.v1` generator |
| `docs/` | Blueprint, ADRs, contracts, engine reports |

## Toolchain (ADR-001)

- Flutter **3.50.0** / Dart **3.14.0**
- Flame **1.38.2**
- Design imports: `package:material_ui` (not deprecated `package:flutter/material.dart`)
- iOS minimum **15.0**, Android minSdk **24**

## Quick start

```bash
# Use Flutter 3.50.0 on PATH
cd packages/puzzle_duel_rules && dart test
cd ../../apps/mobile
flutter pub get
flutter analyze
flutter test
flutter run
```

Startup is guest-first and offline-capable. Local generator output is **not** a ranked score.

Documentation and architecture decisions land through pull requests. Do not deploy or merge without review.

Bootstrap report: [docs/mobile/PZD-22-BOOTSTRAP.md](docs/mobile/PZD-22-BOOTSTRAP.md).
