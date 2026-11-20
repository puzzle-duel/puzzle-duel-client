# PZD-47 — Visual parity manifest

Status: **READY_FOR_OWNER_PHYSICAL_UAT** (do not merge / do not mark Done)

## Binding reference

| Field | Value |
| --- | --- |
| Identity | Green circle + purple diamond + golden flat-top hexagon |
| Owner PNG | `docs/features/pzd-47/reference/hexagon-icon-visual-reference.png` |
| Dimensions | `1024 × 1024` |
| SHA-256 | `dff57723ed17a469f5bd437a589c0f51e5ef970c657248d59638de77c99b689c` |
| Material pin | `pzd47-hexagon-identity-v1` |

Earlier Neon trophy attachment remains archival under `reference/Neon_Puzzle_Trophy_Icon.png` — not the current binding silhouette.

## Canonical shape system

| Role | Path |
| --- | --- |
| Geometry | `apps/mobile/lib/presentation/widgets/premium/shape_geometry.dart` |
| Materials | `…/premium/material_palette.dart` + `premium_shape_materials.dart` |
| Body + chevron painter | `…/premium/premium_piece_renderer.dart` |
| Widget façade | `…/piece_glyph.dart` → `PremiumPieceRenderer` |
| Board | `board_paint_utils.dart` → `PiecePainter` |
| Tray | `offer_tray.dart` → `PieceGlyph` |
| App icon | `premium/app_icon_composer.dart` (shared renderer + Canvas trophy) |
| Icon generator | `tools/pzd47/generate_app_icons.py` |

### Layer mapping

1. **Body** — circle / 45° diamond / flat-top hexagon; bevel, face gradient, specular, contact shadow.
2. **Direction** — one dark stroke chevron (`ProtoShapeGeometry.directionInk`); body never rotates with direction.
3. **Trophy** — icon-only Canvas cup; not a playable piece; raster crops are not loaded at export time.

### Domain mapping

Serialized `Shape.triangle` / wire `triangle` unchanged. Presentation + a11y label: **hexagon**. See `DOMAIN_VISUAL_MAPPING.md`.

## Direction matrix (12 / 12)

Covered by geometry tests + goldens in:

- `apps/mobile/test/presentation/piece_glyph_triangle_arrow_test.dart`
- `apps/mobile/test/presentation/pzd47_premium_shapes_test.dart`
- `apps/mobile/test/presentation/pzd47_golden_artifacts_test.dart` (CI integrity)

## Platform icons + display name

| Platform | Path / value |
| --- | --- |
| iOS AppIcon | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` |
| iOS display name | `CFBundleDisplayName` = **Puzzle Duel** |
| Android mipmaps / adaptive | `mipmap-*`, `drawable-*/ic_launcher_foreground.png` |
| Android label | `android:label` = **Puzzle Duel** |
| Trophy scale | `pieceSize * 0.46` in `PremiumAppIconComposer` |

## UAT evidence index

| Set | Location | Role |
| --- | --- | --- |
| **PZD-47 canonical** | `docs/features/pzd-47/uat/` + `uat/polish/` | Hexagon-identity boards, tray, icon |
| PZD-23 folder (refreshed) | `docs/mobile/uat-evidence/pzd23-visual/` | Offline practice captures regenerated with current renderer on this UAT branch — not pre-hexagon historical archive |
| PZD-42 folder (refreshed) | `docs/mobile/uat-evidence/pzd42-visual/` | Tournament UI captures regenerated similarly |

Pre-hexagon historical bits remain on `main` / earlier commits; this branch keeps current-renderer evidence in those folders for regression of adjacent surfaces.
