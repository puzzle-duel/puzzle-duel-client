#!/usr/bin/env python3
"""Generate iOS AppIcon + Android mipmap / adaptive icons from PZD-47 master.

Source of truth:
  apps/mobile/assets/branding/app_icon_master_1024.png
derived from Jira attachment 10000 (Neon Puzzle Trophy Icon.png) with
center circular arrows already absent (verified in center crop).
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MASTER = ROOT / "apps/mobile/assets/branding/app_icon_master_1024.png"
IOS_DIR = ROOT / "apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID_RES = ROOT / "apps/mobile/android/app/src/main/res"

# (filename, pixel size) — matches Contents.json in AppIcon.appiconset
IOS_SIZES = [
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]

ANDROID_MIPMAP = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Adaptive foreground is 108dp canvas; keep artwork inside ~66dp safe zone
# by letterboxing the full icon onto a larger transparent-like dark canvas.
ANDROID_ADAPTIVE_FG = {
    "drawable-mdpi": 108,
    "drawable-hdpi": 162,
    "drawable-xhdpi": 216,
    "drawable-xxhdpi": 324,
    "drawable-xxxhdpi": 432,
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sips_resize(src: Path, dst: Path, size: int) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["sips", "-z", str(size), str(size), str(src), "--out", str(dst)],
        check=True,
        capture_output=True,
    )


def sips_pad_icon(src: Path, dst: Path, canvas: int, content: int) -> None:
    """Place [content]×[content] icon centered on [canvas] dark adaptive FG."""
    tmp = dst.with_suffix(".tmp.png")
    sips_resize(src, tmp, content)
    # Composite via sips onto solid background by creating padded master.
    # Use CoreGraphics-free approach: create solid navy PNG then overlay.
    bg = dst.with_suffix(".bg.png")
    # Create solid color background using sips from master cropped+padded
    subprocess.run(
        [
            "sips",
            "--setProperty",
            "format",
            "png",
            "-z",
            str(canvas),
            str(canvas),
            str(src),
            "--out",
            str(bg),
        ],
        check=True,
        capture_output=True,
    )
    # Darken: not perfect; better write raw PNG background.
    _write_solid_png(bg, canvas, canvas, (8, 10, 36, 255))
    # Overlay resized icon centered using Python PPM composite
    _composite_center(bg, tmp, dst, canvas, content)
    tmp.unlink(missing_ok=True)
    bg.unlink(missing_ok=True)


def _write_solid_png(path: Path, w: int, h: int, rgba: tuple[int, int, int, int]) -> None:
    import struct
    import zlib

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = b"".join(
        b"\x00" + bytes(rgba) * w for _ in range(h)
    )
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def _decode_rgba(path: Path) -> tuple[int, int, list[bytes]]:
    import struct
    import zlib

    data = path.read_bytes()
    pos = 8
    width = height = None
    color = None
    idat = b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        ctype = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        pos = pos + 12 + length
        if ctype == b"IHDR":
            width, height, bit, color, comp, filt, inter = struct.unpack(
                ">IIBBBBB", chunk
            )
        elif ctype == b"IDAT":
            idat += chunk
        elif ctype == b"IEND":
            break
    assert width and height and color in (2, 6)
    bpp = 3 if color == 2 else 4
    raw = zlib.decompress(idat)
    stride = width * bpp
    rows: list[bytearray] = []
    i = 0
    for _y in range(height):
        filt = raw[i]
        i += 1
        row = bytearray(raw[i : i + stride])
        i += stride
        if filt == 1:
            for x in range(bpp, stride):
                row[x] = (row[x] + row[x - bpp]) & 255
        elif filt == 2:
            up = rows[-1] if rows else bytes(stride)
            for x in range(stride):
                row[x] = (row[x] + up[x]) & 255
        elif filt == 3:
            up = rows[-1] if rows else bytes(stride)
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + ((left + up[x]) // 2)) & 255
        elif filt == 4:
            up = rows[-1] if rows else bytes(stride)
            for x in range(stride):
                a = row[x - bpp] if x >= bpp else 0
                b = up[x]
                c = up[x - bpp] if x >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                row[x] = (row[x] + pr) & 255
        rows.append(row)
    # normalize to RGBA rows
    out: list[bytes] = []
    for row in rows:
        if bpp == 4:
            out.append(bytes(row))
        else:
            rgba = bytearray()
            for x in range(0, stride, 3):
                rgba.extend(row[x : x + 3])
                rgba.append(255)
            out.append(bytes(rgba))
    return width, height, out


def _encode_rgba(path: Path, w: int, h: int, rows: list[bytes]) -> None:
    import struct
    import zlib

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\x00" + row for row in rows)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def _composite_center(
    bg_path: Path, fg_path: Path, dst: Path, canvas: int, content: int
) -> None:
    _bw, _bh, bg_rows = _decode_rgba(bg_path)
    fw, fh, fg_rows = _decode_rgba(fg_path)
    assert fw == content and fh == content
    ox = (canvas - content) // 2
    oy = (canvas - content) // 2
    out = [bytearray(row) for row in bg_rows]
    for y in range(content):
        for x in range(content):
            fo = x * 4
            fr, fg, fb, fa = fg_rows[y][fo : fo + 4]
            if fa == 0:
                continue
            dx = ox + x
            dy = oy + y
            bo = dx * 4
            br, bg, bb, ba = out[dy][bo : bo + 4]
            a = fa / 255.0
            out[dy][bo] = int(fr * a + br * (1 - a))
            out[dy][bo + 1] = int(fg * a + bg * (1 - a))
            out[dy][bo + 2] = int(fb * a + bb * (1 - a))
            out[dy][bo + 3] = 255
    _encode_rgba(dst, canvas, canvas, [bytes(r) for r in out])


def write_adaptive_xml() -> None:
    anydpi = ANDROID_RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
""",
        encoding="utf-8",
    )
    values = ANDROID_RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    colors = values / "colors.xml"
    if colors.exists():
        text = colors.read_text(encoding="utf-8")
        if "ic_launcher_background" not in text:
            text = text.replace(
                "</resources>",
                '    <color name="ic_launcher_background">#080A24</color>\n</resources>',
            )
            colors.write_text(text, encoding="utf-8")
    else:
        colors.write_text(
            """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#080A24</color>
</resources>
""",
            encoding="utf-8",
        )


def main() -> int:
    if not MASTER.exists():
        print(f"missing master icon: {MASTER}", file=sys.stderr)
        return 1
    print(f"master={MASTER}")
    print(f"sha256={sha256(MASTER)}")

    for name, size in IOS_SIZES:
        out = IOS_DIR / name
        sips_resize(MASTER, out, size)
        print(f"ios {name} {size}px")

    for folder, size in ANDROID_MIPMAP.items():
        out = ANDROID_RES / folder / "ic_launcher.png"
        sips_resize(MASTER, out, size)
        print(f"android {folder}/ic_launcher.png {size}px")

    for folder, canvas in ANDROID_ADAPTIVE_FG.items():
        content = int(round(canvas * (66 / 108)))
        out = ANDROID_RES / folder / "ic_launcher_foreground.png"
        sips_pad_icon(MASTER, out, canvas, content)
        print(f"android {folder}/ic_launcher_foreground.png canvas={canvas}")

    write_adaptive_xml()
    print("adaptive ic_launcher.xml written")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
