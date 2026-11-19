#!/usr/bin/env python3
"""PZD-47 canonical asset prep (icon-clip strategy).

Gameplay and the install icon share `app_icon_master_1024.png` — a resize of
Jira attachment 10000. Board/tray sample icon quadrants and clip to the
gameplay silhouette (see PremiumShapeAtlas / PiecePainter). Separating body
vs chevron from the flattened raster is not reliable; we do not claim that.

This script:
  1. Writes app_icon_master_1024 from the reference PNG
  2. Writes optional preview crops under uat/previews (unclipped quadrants)
  3. Writes side-by-side proof: icon quadrant vs clipped token face
  4. Keeps canonical/*.png as clipped token previews for docs (not runtime atlas)

Requires: Pillow, numpy, opencv-python-headless
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs/features/pzd-47/reference/Neon_Puzzle_Trophy_Icon.png"
OUT = ROOT / "apps/mobile/assets/branding/canonical"
UAT = ROOT / "docs/features/pzd-47/uat"
ICON_MASTER = ROOT / "apps/mobile/assets/branding/app_icon_master_1024.png"
MASTER = 256


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def geo_mask(h: int, w: int, kind: str) -> np.ndarray:
    yy, xx = np.mgrid[0:h, 0:w]
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    dx, dy = xx - cx, yy - cy
    r = min(w, h) * 0.42
    if kind == "circle":
        m = dx * dx + dy * dy <= r * r
    elif kind == "diamond":
        m = (np.abs(dx) + np.abs(dy)) <= r * 1.05
    elif kind == "triangle":
        top = cy - r
        bot = cy + r * 0.82
        t = (yy - top) / (bot - top + 1e-9)
        m = (yy >= top) & (yy <= bot) & (np.abs(dx) <= r * 0.95 * np.clip(t, 0, 1) + 1)
    else:
        m = (np.abs(dx) <= r * 0.9) & (np.abs(dy) <= r * 0.9)
    return (m.astype(np.uint8) * 255)


def clipped_preview(rgb: np.ndarray, kind: str) -> Image.Image:
    h, w = rgb.shape[:2]
    alpha = geo_mask(h, w, kind)
    alpha = cv2.GaussianBlur(alpha, (5, 5), 0)
    rgba = np.dstack([rgb, alpha])
    im = Image.fromarray(rgba, "RGBA")
    return im.resize((MASTER, MASTER), Image.Resampling.LANCZOS)


def main() -> None:
    assert SRC.is_file(), SRC
    assert sha(SRC) == (
        "32d53c61874e1c7a6e19c51bcf96cfb0f70d4ddbbe753df6695ace1fc8f5e48b"
    ), "reference SHA mismatch"

    icon = Image.open(SRC).convert("RGBA")
    master = icon.resize((1024, 1024), Image.Resampling.LANCZOS).convert("RGB")
    ICON_MASTER.parent.mkdir(parents=True, exist_ok=True)
    master.save(ICON_MASTER)
    UAT.mkdir(parents=True, exist_ok=True)
    master.save(UAT / "02-icon-no-center-arrows.png")
    master.save(UAT / "08-ios-appicon-1024.png")
    master.save(UAT / "02-icon-composed-from-canonical-masters.png")

    arr = np.array(icon)
    h0, w0 = arr.shape[:2]
    q = w0 // 2
    regions = {
        "circle": ((40, 40, q - 16, q - 16), "circle", 0),
        "diamond": ((q + 16, 40, w0 - 40, q - 16), "diamond", 3),
        "triangle": ((40, q + 16, q - 16, h0 - 40), "triangle", 0),
        "trophy": ((q + 16, q + 16, w0 - 40, h0 - 40), "trophy", None),
    }
    OUT.mkdir(parents=True, exist_ok=True)
    preview = UAT / "previews"
    preview.mkdir(exist_ok=True)
    bodies: dict[str, Image.Image] = {}
    native: dict[str, int] = {}
    manifest = {
        "version": "pzd47-canonical-clipped-sprite-v4",
        "strategy": (
            "Runtime atlas = app_icon_master_1024 (attachment 10000 resized). "
            "PiecePainter samples quadrant src rects and clips to silhouette. "
            "canonical/*_body.png are clipped previews for docs/UAT only."
        ),
        "source_attachment": {
            "path": str(SRC.relative_to(ROOT)),
            "sha256": sha(SRC),
            "bytes": SRC.stat().st_size,
            "jira_attachment_id": "10000",
        },
        "assets": {},
    }

    for name, (box, kind, turns) in regions.items():
        x0, y0, x1, y1 = box
        crop = arr[y0:y1, x0:x1]
        clipped = clipped_preview(crop[..., :3], kind)
        path = OUT / (f"{name}_body.png" if turns is not None else "trophy.png")
        clipped.save(path)
        bodies[name] = clipped
        bg = Image.new("RGBA", clipped.size, (8, 12, 40, 255))
        bg.alpha_composite(clipped)
        bg.convert("RGB").save(preview / f"{name}_body_preview.jpg", quality=95)
        if turns is not None:
            native[name] = turns
            manifest["assets"][name] = {
                "preview": f"assets/branding/canonical/{name}_body.png",
                "sha256": sha(path),
                "native_direction_turns_from_up": turns,
                "runtime": "srcRect on app_icon_master_1024 + shapePath clip",
            }
        else:
            manifest["assets"]["trophy"] = {
                "preview": "assets/branding/canonical/trophy.png",
                "sha256": sha(path),
                "playable": False,
            }

    Image.new("RGBA", (8, 8), (0, 0, 0, 0)).save(OUT / "direction_chevron_up.png")
    manifest["assets"]["direction_chevron_up"] = {
        "note": "Unused in v4 icon-clip mode (compat placeholder).",
        "sha256": sha(OUT / "direction_chevron_up.png"),
    }
    manifest["native_turns_from_up"] = native
    manifest["direction_layer"] = {
        "mode": "whole_sprite_rotation",
        "turns": {"up": 0, "right": 1, "down": 2, "left": 3},
        "note": (
            "Rotate clipped icon sample by (desired - native) quarter-turns. "
            "Diamond silhouette remains 45° under 90° rotation."
        ),
    }

    side = Image.new("RGB", (960, 560), (8, 12, 40))
    for col, name in enumerate(("circle", "diamond", "triangle")):
        box, _, _ = regions[name]
        x0, y0, x1, y1 = box
        top = Image.new("RGBA", (220, 220), (8, 12, 40, 255))
        top.alpha_composite(
            Image.fromarray(arr[y0:y1, x0:x1], "RGBA").resize(
                (220, 220), Image.Resampling.LANCZOS
            )
        )
        side.paste(top.convert("RGB"), (40 + col * 310, 40))
        bot = Image.new("RGBA", (180, 180), (8, 12, 40, 255))
        bot.alpha_composite(bodies[name].resize((180, 180), Image.Resampling.LANCZOS))
        side.paste(bot.convert("RGB"), (60 + col * 310, 310))
    side.save(UAT / "10-side-by-side-parity.png")

    manifest["icon_master"] = {
        "path": "apps/mobile/assets/branding/app_icon_master_1024.png",
        "sha256": sha(ICON_MASTER),
        "source": "original_attachment_resized_1024",
        "runtime_atlas": True,
    }
    (OUT / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("icon_master", sha(ICON_MASTER))
    print("wrote", OUT / "MANIFEST.json")


if __name__ == "__main__":
    main()
