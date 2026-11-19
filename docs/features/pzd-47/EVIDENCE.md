# PZD-47 — Implementation evidence

Branch: `feature/PZD-47-premium-shapes-app-icon`  
Status: **READY_FOR_OWNER_VISUAL_UAT** — do not merge / do not mark Jira Done

Follow-up on PR #22 HEAD `147a90f`: AC-03 now uses shared attachment pixels (clipped sprites) for board/tray; install icon is the same attachment resized. See `AC03_DELTA_AND_CANONICAL_FIX.md`.

## Acceptance checklist

| AC | Result | Notes |
| --- | --- | --- |
| AC-01 Attachment inspect + SHA | **PASS** | `Neon_Puzzle_Trophy_Icon.png` 1653310 bytes, SHA-256 `32d53c61874e1c7a6e19c51bcf96cfb0f70d4ddbbe753df6695ace1fc8f5e48b` |
| AC-02 No center circular arrows | **PASS** | Attachment center crop shows neon tile gutters only; clean master installed |
| AC-03 Icon↔board↔tray canonical | **PASS w/ honesty** | Version `pzd47-canonical-clipped-sprite-v4`. Same attachment pixels; board/tray = clipped quadrant sprites + whole-sprite direction rotation. Layered body/chevron extraction from flattened raster failed (documented). |
| AC-04 12/12 directions + diamond 45° | **PASS** | Geometry + golden matrix |
| AC-05 5×5 / 6×6 / dense 7×7 / tray | **PASS** | Flutter UAT captures under `docs/features/pzd-47/uat/` |
| AC-06 iOS + Android native icons | **PASS (assets)** / device home-screen proof TBD |
| AC-07 Regression | See commands |
| AC-08 Owner visual approval | **PENDING** | Explicit owner UAT required |

## Commands run

```text
flutter analyze                         → No issues found (when run)
flutter test                            → +339 All tests passed
python3 tools/pzd47/extract_canonical_shapes.py
python3 tools/pzd47/generate_app_icons.py
```

| Build | Result |
| --- | --- |
| Installed iOS home-screen photo | **NOT_RUN** |
| Installed Android launcher photo | **NOT_RUN** |

## Visual UAT package

| # | Artifact |
| --- | --- |
| 1 | `uat/01-original-jira-icon.png` |
| 2 | `uat/02-icon-no-center-arrows.png` + `uat/02-icon-composed-from-canonical-masters.png` |
| 3 | `uat/03-board-5x5.png` |
| 4 | `uat/04-board-6x6.png` |
| 5 | `uat/05-board-7x7-dense.png` |
| 6 | `uat/06-tray-selected.png` |
| 7 | `uat/07-renderer-shapes-strip.png` + `uat/10-side-by-side-parity.png` |
| 8 | `uat/08-ios-appicon-1024.png` |
| 9 | `uat/09-android-launcher-xxxhdpi.png` |

## Known visual discrepancies (honest)

1. Geometric silhouette clip can leave a ring of neon plate glow inside the path (visible in strip / side-by-side bottom row).
2. Flattened attachment has no separable chevron layer — direction uses whole-sprite rotation (triangle apex follows direction).
3. Scale/filtering differences between icon size and board cell size.
4. Device home-screen screenshots **NOT_RUN**.

## Owner ask

Review UAT package + `AC03_DELTA_AND_CANONICAL_FIX.md`. Explicit visual PASS / FAIL before merge.
