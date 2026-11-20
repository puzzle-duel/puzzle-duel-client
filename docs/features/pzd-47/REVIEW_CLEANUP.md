# PZD-47 — Independent review cleanup findings

Branch tip after cleanup: see git log on `uat/PZD-47-premium-renderer`.

## Root causes (verified)

1. **Geometry drift:** `shapePath` / `ProtoShapeGeometry.outerPath` already painted domain `Shape.triangle` as a flat-top hexagon, but `PiecePainter.pointInShape`, ray/edge probes, and `glyphOrigin` still used upright-triangle vertices. Containment tests could pass against a silhouette the painter no longer draws.

2. **Dead triangle-chevron helpers:** `triangleChevronOrigin` / `triangleSafeFaceFrac` in `shape_geometry.dart` were unused after the shared centered chevron layout; they encoded the old triangle optical nudges.

3. **Silent CI golden skips:** Pixel goldens skipped on `CI`/`GITHUB_ACTIONS` with no compensating always-on check that fixtures still exist — coverage could erode unnoticed.

4. **Stale docs:** `EVIDENCE.md` / `VISUAL_PARITY_MANIFEST.md` still described Neon triangle identity and raster trophy.

5. **Unused trophy raster load:** Icon export test still decoded `reference/crops/trophy.png` even though `PremiumAppIconComposer` paints a Canvas cup and ignores the image.

6. **PZD-23/42 PNGs:** 18 files under `docs/mobile/uat-evidence/` were regenerated with the hexagon renderer on this UAT branch. They are **current-renderer** captures in historical folders — not a silent overwrite of `main` history. Canonical PZD-47 package remains `docs/features/pzd-47/uat/`.

## Corrective actions taken

- Align `PiecePainter` containment/ray/edge/`glyphOrigin` with hexagon presentation; keep `triangleVertices` as legacy API.
- Remove unused `triangleChevronOrigin` / `triangleSafeFaceFrac`.
- Add `pzd47_golden_artifacts_test.dart`; document `PZD47_FORCE_GOLDENS=1` escape hatch.
- Refresh evidence/manifest/provenance docs; add `docs/mobile/uat-evidence/README.md`.
- Remove trophy raster load from export test.

## Unchanged by design

- Home / Profile / Tournament / startup / auth / scoring / generators.
- Trophy scale `0.46`; display name **Puzzle Duel**.
- Untracked prototype directories.
