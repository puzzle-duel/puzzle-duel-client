# PZD-47 — Visual parity manifest

Status: **READY_FOR_OWNER_VISUAL_UAT** (do not merge / do not mark Done)

## Source inspection (AC-01)

| Field | Value |
| --- | --- |
| Jira | [PZD-47](https://puzzle-duel-app.atlassian.net/browse/PZD-47) |
| Attachment | `Neon Puzzle Trophy Icon.png` (id `10000`) |
| Repo copy | `docs/features/pzd-47/reference/Neon_Puzzle_Trophy_Icon.png` |
| Bytes | `1653310` (matches Jira attachment size) |
| Dimensions | `1254 × 1254` RGB PNG |
| SHA-256 | `32d53c61874e1c7a6e19c51bcf96cfb0f70d4ddbbe753df6695ace1fc8f5e48b` |
| Center circular arrows | **Absent** in attachment (verified via center crop) |

Clean icon alias (same bytes as attachment):

- `docs/features/pzd-47/reference/app_icon_clean_no_center_arrows.png`

## Canonical shape system (AC-03)

| Role | Path |
| --- | --- |
| Material / version tokens | `apps/mobile/lib/presentation/widgets/premium_shape_materials.dart` (`pzd47-canonical-shapes-v1`) |
| Shared body + direction renderer | `apps/mobile/lib/presentation/widgets/piece_glyph.dart` (`PiecePainter`) |
| Board consumption | `apps/mobile/lib/presentation/game/board/board_paint_utils.dart` → `paintPieceGlyph` → `PiecePainter` |
| Tray consumption | `apps/mobile/lib/presentation/game/offer_tray.dart` → `PieceGlyph` → `PiecePainter` |
| Theme color alignment | `apps/mobile/lib/theme/game_tokens.dart` |
| App icon master (1024) | `apps/mobile/assets/branding/app_icon_master_1024.png` |
| Icon generator | `tools/pzd47/generate_app_icons.py` |

### Layer mapping

1. **Body / material** — silhouette path (circle / 45° rounded diamond / rounded triangle) + bevel shell + face gradient + top-left specular + contact shadow.
2. **Direction glyph** — dark navy inset chevron, composited independently from gameplay `Direction`. Diamond body rotation does **not** rotate the logical direction marker.
3. **Trophy** — icon-only artwork retained from the approved attachment; **not** a playable piece.

### Reconstruction honesty

The Jira attachment is a flattened raster. Shape layers were reconstructed as a deterministic Flutter painter matching the icon crops (geometry, lighting direction, bevel, colors, inset chevron). This is **not** a claim of pixel-perfect equality with the raster. Owner visual UAT decides PASS.

## Direction mapping (AC-04)

| Shape | Directions covered |
| --- | --- |
| Circle | up, right, down, left |
| Diamond (45° body) | up, right, down, left |
| Triangle | up, right, down, left |

**12 / 12** combinations covered by widget + golden tests in:

- `apps/mobile/test/presentation/piece_glyph_triangle_arrow_test.dart`
- `apps/mobile/test/presentation/pzd47_premium_shapes_test.dart`

## Platform icons (AC-06)

| Platform | Path |
| --- | --- |
| iOS AppIcon set | `apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/` |
| Android legacy mipmaps | `apps/mobile/android/app/src/main/res/mipmap-*/ic_launcher.png` |
| Android adaptive | `mipmap-anydpi-v26/ic_launcher.xml` + `drawable-*/ic_launcher_foreground.png` + `@color/ic_launcher_background` |

Regenerate:

```bash
python3 tools/pzd47/generate_app_icons.py
```

## UAT evidence

See `docs/features/pzd-47/uat/` after capture tests are run.
