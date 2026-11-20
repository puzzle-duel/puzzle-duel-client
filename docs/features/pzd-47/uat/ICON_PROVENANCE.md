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
| Bottom-right | Clean Canvas trophy (no rectangular plate) |
| Direction glyph | One shared dark stroke chevron (`ProtoShapeGeometry.directionInk`) |
| Export | `PZD47_EXPORT_CHEVRON_EVIDENCE=1 flutter test test/presentation/simple_chevron_evidence_test.dart` |
| Platform icons | `python3 tools/pzd47/generate_app_icons.py` |

Shared implementation — not palette-only parity. See `DOMAIN_VISUAL_MAPPING.md`.
