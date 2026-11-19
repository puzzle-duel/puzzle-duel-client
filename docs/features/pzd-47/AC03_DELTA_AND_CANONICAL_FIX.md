# PZD-47 AC-03 — Visual deltas and canonical fix

## What was wrong (HEAD `147a90f`)

| Surface | Source |
| --- | --- |
| App icon | Jira flattened raster resized |
| Board / tray | Procedural `PiecePainter` gradients (approximation) |

Same **visual language**, not the **same objects** — failed strict AC-03.

## Concrete deltas (pre-fix UAT)

Observed in earlier `uat/10-side-by-side-parity.png` and dense 7×7:

1. Material / lighting — icon specular + bevel vs flatter painter gradients
2. Bevel thickness — icon extrusion vs thin path stroke
3. Chevron — icon recessed raster cutout vs vector path
4. Edge AA — icon source AA vs path rasterization at cell size
5. Color — approximate tokens vs attachment averages

## Why body/chevron layer separation failed

Attachment 10000 is a **flattened** raster. Attempts to extract filled bodies + a separate chevron master (flood / geo / OpenCV inpaint) produced:

- frame/neon plate bleed into “bodies”
- holes and jagged silhouettes after chevron removal
- highlight-seed flood that shredded mid-tones

Those residuals are **not** hidden: they proved 1:1 layered masters are not available without a PSD/source stack.

## Fix (v4) — shared attachment pixels + clipped sprites

| Consumer | Source |
| --- | --- |
| Install icon | `app_icon_master_1024.png` = attachment 10000 resized |
| Board / tray | `canonical/{circle,diamond,triangle}_body.png` — same attachment quadrants, geometric silhouette clip |

Direction = whole-sprite rotation relative to icon-native orientation (circle/triangle UP, diamond LEFT). Diamond silhouette stays 45° under 90° turns; triangle apex follows direction so the token remains the icon object.

Version pin: `pzd47-canonical-clipped-sprite-v4` (`PremiumShapeMaterials.version`).

Regenerate: `tools/pzd47/.venv/bin/python tools/pzd47/extract_canonical_shapes.py` then `python3 tools/pzd47/generate_app_icons.py`.

## Remaining honest residuals

1. Clip path vs organic 2.5D silhouette — outer bevel corners may be trimmed by circle/diamond/triangle paths.
2. Scale / filtering — board cells downscale 1024 quadrants with `FilterQuality.medium`.
3. Neon plate — excluded by clip; not drawn on board cells (by design).
4. Not claiming byte-identical pixels between a 600px icon quadrant and a ~40px cell — claiming **same master asset** + same baked chevron pixels inside the clip.

## Golden updates

PZD-47 / direction-family goldens updated because the renderer source changed from procedural paint → icon-clip sampling — not a blind baseline refresh. Review `docs/features/pzd-47/uat/` before owner PASS.
