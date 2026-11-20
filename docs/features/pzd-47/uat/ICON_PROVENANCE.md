# PZD-47 App Icon — Shared Renderer Provenance

| Field | Value |
| --- | --- |
| Composer | `PremiumAppIconComposer` |
| Shape painter | `PremiumPieceRenderer` |
| Material version | `pzd47-hexagon-identity-v1` |
| Owner reference | `docs/features/pzd-47/reference/hexagon-icon-visual-reference.png` |
| Master | `apps/mobile/assets/branding/app_icon_master_1024.png` |
| Top-left | Green circle (`Shape.circle`) Up |
| Top-right | Purple diamond (`Shape.diamond`) Up |
| Bottom-left | Golden hexagon (`Shape.triangle` → hexagon presentation) Up |
| Bottom-right | Clean Canvas trophy (no rectangular plate; no raster load) |
| Trophy scale | `pieceSize * 0.46` (`PremiumAppIconComposer.trophyScale`) |
| Trophy optical lift | `-pieceSize * 0.05` (`trophyOpticalLift`) — aligns BR cup with BL hexagon |
| Direction glyph | One shared dark stroke chevron (`ProtoShapeGeometry.directionInk`) |
| Display name | **Puzzle Duel** (iOS `CFBundleDisplayName`, Android `android:label`) |
| Export | `PZD47_EXPORT_ICON=1 flutter test test/presentation/premium_app_icon_composer_test.dart` |
| Platform icons | `python3 tools/pzd47/generate_app_icons.py` |

Shared implementation — not palette-only parity. See `DOMAIN_VISUAL_MAPPING.md`.

Archival crops (`reference/crops/trophy.png`, etc.) are **not** used by export.
