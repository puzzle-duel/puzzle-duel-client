# PZD-39 — Stage B mobile compatibility gate

**Gate outcome:** **STAGE B — BLOCKED** (Flutter 3.50 toolchain unavailable)  
**Reviewed tip before this change:** `23b65534fa872c502391605b003bc615b9c4b97c`  
**PR:** https://github.com/puzzle-duel/puzzle-duel-client/pull/18  
**Base:** `docs/core-001-v3-ruleset-design`  
**Independent review comment:** [#6931837055](https://github.com/puzzle-duel/puzzle-duel-client/pull/18#issuecomment-6931837055)

This gate separates **source-level API compatibility** from **Flutter compilation/tests** and **iOS simulator build**.

---

## 1. Worktree safety

| Worktree | Branch / HEAD | Preserved |
| --- | --- | --- |
| Stage B (this work) | `feature/PZD-39-core001v3-dart-engine` | Yes — only tree modified |
| Client PZD-22 | `feature/PZD-22-flutter-app-bootstrap` | Yes (untouched) |
| Client PZD-23 | detached + staged visuals | Yes (untouched) |
| Client design | `docs/core-001-v3-ruleset-design` @ `a09866b` | Yes |
| Backend Phase A | `feature/PZD-38-trusted-ingress` | Yes |
| Backend design | `docs/core-001-v3-ruleset-design` @ `727e1b4` | Yes |

Stage B working tree was clean at start. No reset/clean/stash/force-push.

---

## 2. Public API change

| Before | After |
| --- | --- |
| `List<Piece?> offers` | `List<OfferSlot> offers` |

JSON wire for v1/v2 remains piece objects / JSON `null`. Dart **type** surface changed for all versions.

---

## 3. Consumer inventory (Stage B tree)

### Production (compile-time break before fix)

| File | Lines | Old assumption | Classification (pre-fix) |
| --- | ---: | --- | --- |
| `apps/mobile/lib/application/game_session.dart` | 166–188 | `offers[i] == null`, `Piece?` assignment | **Compile-time incompatible** |
| `apps/mobile/lib/presentation/game/offer_tray.dart` | 16, 50–52 | `List<Piece?>` | **Compile-time incompatible** |
| `apps/mobile/lib/presentation/game/game_screen.dart` | 60 | `offers ?? [null,null,null]` | **Compile-time incompatible** |

### Tests (compile-time break before fix)

| File | Lines | Issue |
| --- | ---: | --- |
| `apps/mobile/test/application/game_session_test.dart` | 22, 252, 275 | null / `Piece?` |
| `apps/mobile/test/application/animation_script_test.dart` | 21, 33 | null / `Piece?` |
| `apps/mobile/test/presentation/game_sfx_lifecycle_test.dart` | 19, 36, 48, 65, 335, 347 | null / `!` as `Piece` |
| `apps/mobile/test/app_smoke_test.dart` | 106, 198 | null checks |
| `apps/mobile/test/visual/pzd23_screenshot_capture_test.dart` | 82, 130 | null checks |

### Compatible / N/A

| Area | Notes |
| --- | --- |
| Board cells `List<List<Piece?>>` | Unchanged |
| `PieceGlyph` / painters | Take `Piece`, not offers |
| `packages/puzzle_duel_rules` internals + its tests | Already migrated |
| Historical v1/v2 **JSON** fixtures | Byte-identical; not Dart-type consumers |

---

## 4. Remediation (minimal, Stage B–owned)

Migrated mobile callers to version-aware OfferSlot accessors:

- Selectability: `OfferSlot.isSelectable` (rejects `OfferEmpty` and `OfferSpent`)
- Live piece: `OfferSlot.pieceOrNull`
- `OfferTray` now takes `List<OfferSlot>`; empty UI for non-selectable slots
- Default empty tray: `[OfferEmpty(), OfferEmpty(), OfferEmpty()]`

**Historical semantics preserved:** v2 terminal null still serializes as JSON `null` via `OfferEmpty`; UI still shows “—” and blocks selection. v3 spent cannot be selected as a live piece.

No ADR-E01 rule changes. PZD-22 / PZD-23 worktrees not modified.

---

## 5. Flutter SDK / executed checks

| Item | Result |
| --- | --- |
| Required | Flutter **3.50.0** / Dart **3.14.0** (ADR-001 / pubspec `flutter: ">=3.50.0 <3.51.0"`) |
| Host Flutter | **3.47.8** / Dart **3.13.7** (`/opt/homebrew/bin/flutter`) |
| Flutter 3.50 install on machine | **Not found** (search of common paths) |
| Download/upgrade | **Not performed** (requires explicit approval) |

```text
cd apps/mobile
flutter pub get
→ FAILED: puzzle_duel_mobile requires SDK ^3.14.0; current Dart is 3.13.7
  Suggestion: Try using the Flutter SDK version: 3.50.0
```

| Check | Status |
| --- | --- |
| `flutter pub get` (Accepted 3.50) | **NOT_RUN** (SDK missing) |
| `flutter analyze` | **NOT_RUN** |
| `flutter test` | **NOT_RUN** |
| iOS simulator build | **NOT_RUN** |

---

## 6. Pure Dart regression (still mandatory)

Portable `.dart-sdk/bin/dart` **3.14.0**, package `packages/puzzle_duel_rules`:

| Check | Exit | Totals |
| --- | ---: | --- |
| `dart format --set-exit-if-changed .` | 0 | clean |
| `dart analyze` | 0 | No issues found |
| `dart test` | 0 | **140 PASS / 0 FAIL / 0 SKIP** |

---

## 7. Historical v1/v2 semantics (source-level)

| Concern | Result |
| --- | --- |
| v1/v2 JSON wire | Unchanged (`OfferLive` → piece object; `OfferEmpty` → `null`) |
| Mobile selection of empty/spent | Blocked via `isSelectable` |
| No silent v3 dispatch for generated challenges | Generator still pins `core-001.v2` |
| Score / turns / board cells | Unchanged APIs |

Executable Flutter UI proof of the above: **NOT_RUN** until Flutter 3.50 is available.

---

## 8. Findings

| Sev | Item | Status |
| --- | --- | --- |
| P1 | `List<Piece?>` → `List<OfferSlot>` broke mobile compile | **Fixed in Stage B apps/mobile** (pending Flutter 3.50 verify) |
| P0 | None identified beyond that compile break | — |
| Env | Flutter 3.50.0 not installed | **Blocks** analyze/test/simulator |

---

## 9. Final decision

**STAGE B — BLOCKED**

Reason: mandatory Flutter quality gates for Accepted Flutter 3.50.0 could not be executed on this machine. Source-level P1 consumer migration is implemented in the Stage B branch, and pure Dart package tests remain green, but **INTEGRATION VERIFIED** is not claimed without:

1. Install/use Flutter 3.50.0 + Dart 3.14.0  
2. `cd apps/mobile && flutter pub get && flutter analyze && flutter test`  
3. Optional: iOS simulator compile in Stage B only (do not touch PZD-23)

---

## 10. NOT_RUN

- Flutter 3.50 `pub get` / `analyze` / `test`
- iOS simulator build
- Device UAT
- TypeScript Stage C / dual-engine Stage D
- Merge / deploy
