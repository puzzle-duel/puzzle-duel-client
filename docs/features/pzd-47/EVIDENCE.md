# PZD-47 — Implementation evidence

Branch: `uat/PZD-47-premium-renderer`  
Status: **READY_FOR_OWNER_PHYSICAL_UAT** — do not merge / do not mark Jira Done

## Approved visual identity

| Element | Presentation |
| --- | --- |
| Circle | Green glossy circle |
| Diamond | Purple glossy 45° diamond |
| Domain `Shape.triangle` | **Golden flat-top hexagon** (wire value unchanged) |
| Direction | One shared single-stroke dark chevron |
| App icon | Same `PremiumPieceRenderer` for three shapes + **Canvas trophy** |

See `DOMAIN_VISUAL_MAPPING.md` and `docs/features/pzd-47/reference/hexagon-icon-visual-reference.png`  
(SHA-256 `dff57723ed17a469f5bd437a589c0f51e5ef970c657248d59638de77c99b689c`).

## Acceptance checklist

| AC | Result | Notes |
| --- | --- | --- |
| Hexagon identity + shared renderer | **PASS** | `PremiumPieceRenderer` + `ProtoShapeGeometry.flatTopHexagon` |
| 12/12 directions | **PASS** | Geometry always; pixel goldens macOS + artifact integrity on CI |
| Board / tray / icon parity | **PASS** | Shared painter; icon via `PremiumAppIconComposer` |
| Trophy | **PASS** | Procedural Canvas cup — no rectangular plate / no crop load |
| Display name | **PASS** | iOS/Android **Puzzle Duel**; trophy scale `pieceSize * 0.46` |
| Owner physical UAT | **PENDING** | Tournament flow requires `PZD_UAT_*` dart-defines |

## Visual regression strategy

| Layer | Where | CI |
| --- | --- | --- |
| Geometry / containment / materials pin | `pzd47_premium_shapes_test.dart`, `triangle_chevron_optical_test.dart` | Always |
| Golden PNG artifact integrity | `pzd47_golden_artifacts_test.dart` | Always |
| Pixel `matchesGoldenFile` | direction / pzd47 goldens | macOS local; skip on Linux CI with explicit reason unless `PZD47_FORCE_GOLDENS=1` |
| UAT screenshots | `docs/features/pzd-47/uat/` | Local capture tests |

## Known honesty notes

1. Domain wire remains `triangle`; presentation is hexagon.
2. Historical `piece_glyph` helpers `triangleVertices` / `pointInTriangle` are retained for API/tests only — containment/ray probes use hexagon.
3. Reference crops under `docs/features/pzd-47/reference/crops/` are archival; runtime icon does not load `trophy.png`.

## Owner ask

Physical-device Tournament UAT with authenticated defines before merge.
