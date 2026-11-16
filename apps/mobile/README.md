# puzzle_duel_mobile

Puzzle Duel iOS/Android application bootstrap (PZD-22).

## Requirements

- Flutter **3.50.0**
- Dart **3.14.0**
- iOS deployment target **15.0**
- Android minSdk **24** (compileSdk/targetSdk from Flutter 3.50 toolchain: **36**)

Do not silently upgrade Flutter or Flame. Flame is pinned to **1.38.2**.

## Run locally

```bash
export PATH="/path/to/flutter-3.50.0/bin:$PATH"
cd apps/mobile
flutter pub get
flutter analyze
flutter test
flutter run
```

Guest-first startup needs no network, backend URL, authentication, ads, or analytics.

## Architecture

- `lib/application/` — session + generator adapter over `puzzle_duel_rules`
- `lib/presentation/` — Material UI shell (`package:material_ui`)
- `packages/puzzle_duel_rules/` — pure Dart engine (path dependency)

Flame is used only for a rendering smoke probe. It does not own rules state.

See [docs/mobile/PZD-22-BOOTSTRAP.md](../../docs/mobile/PZD-22-BOOTSTRAP.md).
