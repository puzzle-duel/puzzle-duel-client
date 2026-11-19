# PZD-47 — Visual parity manifest

Status: **READY_FOR_OWNER_VISUAL_UAT** (do not merge)

## Source (AC-01)

| Field | Value |
| --- | --- |
| Attachment | `Neon Puzzle Trophy Icon.png` id `10000` |
| Repo copy | `docs/features/pzd-47/reference/Neon_Puzzle_Trophy_Icon.png` |
| SHA-256 | `32d53c61874e1c7a6e19c51bcf96cfb0f70d4ddbbe753df6695ace1fc8f5e48b` |
| Bytes | `1653310` |

## Canonical runtime (AC-03) — shared by icon + board + tray

Version: `pzd47-canonical-clipped-sprite-v4`

| Asset | Path | Role |
| --- | --- | --- |
| Install icon master | `apps/mobile/assets/branding/app_icon_master_1024.png` | Attachment 10000 → 1024 |
| Clipped gameplay sprites | `apps/mobile/assets/branding/canonical/{circle,diamond,triangle}_body.png` | Same attachment + silhouette clip |
| Manifest | `apps/mobile/assets/branding/canonical/MANIFEST.json` | Hashes + strategy |

### Consumers

| Consumer | Path |
| --- | --- |
| Board / tray | `PremiumShapeAtlas` → `PiecePainter` (`piece_glyph.dart`) — clipped sprites + whole-sprite rotation |
| App icon | `tools/pzd47/generate_app_icons.py` from `app_icon_master_1024.png` |

### Direction mapping

| Direction | Whole-sprite quarter-turns from UP |
| --- | --- |
| up | 0 |
| right | 1 |
| down | 2 |
| left | 3 |

Icon-native: circle/triangle = UP (0), diamond = LEFT (3). Painter applies `(desired - native) % 4`.

## Delta / honesty

See `AC03_DELTA_AND_CANONICAL_FIX.md`.
