# PZD-47 — Implementation evidence

Branch: `feature/PZD-47-premium-shapes-app-icon`  
Status: **READY_FOR_OWNER_VISUAL_UAT** — do not merge / do not mark Jira Done

## Acceptance checklist

| AC | Result | Notes |
| --- | --- | --- |
| AC-01 Attachment inspect + SHA | **PASS** | `Neon_Puzzle_Trophy_Icon.png` 1653310 bytes, SHA-256 `32d53c61874e1c7a6e19c51bcf96cfb0f70d4ddbbe753df6695ace1fc8f5e48b` |
| AC-02 No center circular arrows | **PASS** | Attachment center crop shows neon tile gutters only; clean master installed |
| AC-03 Icon↔board↔tray canonical | **PASS w/ honesty** | Shared `PiecePainter` + `PremiumShapeMaterials` for board/tray; icon master derived from attachment raster. Shapes reconstructed (not pixel-extracted layers). |
| AC-04 12/12 directions + diamond 45° | **PASS** | Geometry + golden matrix |
| AC-05 5×5 / 6×6 / dense 7×7 / tray | **PASS** | UAT captures under `docs/features/pzd-47/uat/` |
| AC-06 iOS + Android native icons | **PASS (assets)** / device home-screen proof TBD below |
| AC-07 Regression | See commands |
| AC-08 Owner visual approval | **PENDING** | Explicit owner UAT required |

## Commands run

```text
flutter analyze                         → No issues found
flutter test                            → +339 All tests passed
(cd packages/puzzle_duel_rules && dart analyze && dart test) → +140 All tests passed
python3 tools/pzd47/generate_app_icons.py → iOS AppIcon + Android mipmap/adaptive
```

Platform builds:

| Build | Result |
| --- | --- |
| `flutter build ios --no-codesign` | **PASS** (`Runner.app` 20.3MB) |
| `flutter build apk --debug` | **PASS** (`app-debug.apk`) |
| Installed iOS home-screen photo | **NOT_RUN** (no interactive install in this session) |
| Installed Android launcher photo | **NOT_RUN** |

## Visual UAT package

| # | Artifact |
| --- | --- |
| 1 | `reference/Neon_Puzzle_Trophy_Icon.png` (Jira attachment / clean master) |
| 2 | `reference/crops/*` (shape + center crops) |
| 3 | `uat/03-board-5x5.png` |
| 4 | `uat/04-board-6x6.png` |
| 5 | `uat/05-board-7x7-dense.png` |
| 6 | `uat/06-tray-selected.png` |
| 7 | `uat/07-renderer-shapes-strip.png` + `uat/10-side-by-side-parity.png` |
| 8 | iOS AppIcon set under `apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/` |
| 9 | Android launcher under `apps/mobile/android/app/src/main/res/mipmap-*/` + adaptive foregrounds |

## Known visual discrepancies (honest)

1. **Not pixel-perfect vs icon raster.** Flutter painter reconstructs bevel/highlight/chevron from the attachment appearance. Expect small differences in specular softness, bevel thickness, and neon cell glow (board cells stay restrained; neon is icon-frame only).
2. **Trophy** remains raster artwork inside the installed icon only; it is not a playable piece and is not drawn by `PiecePainter`.
3. **Device home-screen screenshots** of the installed launcher icon were not captured in this automation session (`NOT_RUN`). Asset configuration is complete; owner/device proof still requested.

## Owner ask

Please review the UAT package and reply with explicit visual PASS / FAIL before any merge.
