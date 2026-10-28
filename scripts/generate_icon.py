#!/usr/bin/env python3
"""Draw the original ExifBye icon as an RGB PNG using only the Python standard library."""
import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "Support/Assets.xcassets"
APP = ROOT / "AppIcon.appiconset"
APP.mkdir(parents=True, exist_ok=True)
SIZE = 1024


def rounded_box(x, y, cx, cy, hw, hh, radius):
    dx, dy = abs(x - cx) - hw + radius, abs(y - cy) - hh + radius
    return max(dx, 0) ** 2 + max(dy, 0) ** 2 <= radius ** 2 and dx <= radius and dy <= radius


def sparkle(x, y, cx, cy, radius):
    return (abs(x - cx) / radius) ** 0.6 + (abs(y - cy) / radius) ** 0.6 < 1


rows = bytearray()
for y in range(SIZE):
    rows.append(0)
    for x in range(SIZE):
        outline = rounded_box(x, y, 480, 554, 300, 230, 55) and not rounded_box(x, y, 480, 554, 270, 200, 30)
        mountains = 312 <= x <= 665 and 500 <= y <= 688 and (
            abs(y - (665 - 0.9 * (x - 312))) < 17 if x < 478 else abs(y - (516 + 0.9 * (x - 478))) < 17
        )
        sun = (x - 346) ** 2 + (y - 451) ** 2 < 33 ** 2
        star = sparkle(x, y, 765, 280, 126) or sparkle(x, y, 575, 215, 48)
        white = outline or mountains or sun or star
        rows.extend((255, 255, 255) if white else (12, 108 + y * 20 // SIZE, 116 + y * 18 // SIZE))


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)


png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
(APP / "AppIcon.png").write_bytes(png)
(APP / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}
}, indent=2) + "\n")
(ROOT / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n')
print("Generated RGB 1024×1024 app icon")
