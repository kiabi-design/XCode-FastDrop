#!/usr/bin/env python3
"""Generate simple app icon PNGs for all required sizes."""
import zlib
import struct
from pathlib import Path

def write_png(path: Path, width: int, height: int, color: tuple = (48, 209, 88)):
    """Write a simple solid color PNG."""
    # PNG signature
    png = b'\x89PNG\r\n\x1a\n'

    # IHDR chunk
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    ihdr_crc = zlib.crc32(b'IHDR' + ihdr) & 0xffffffff
    png += struct.pack('>I', len(ihdr)) + b'IHDR' + ihdr + struct.pack('>I', ihdr_crc)

    # IDAT chunk - simple solid color image data
    # Each row: filter byte (0) + RGB * width
    row = b'\x00' + bytes([color[0], color[1], color[2]]) * width
    raw_data = row * height
    compressed = zlib.compress(raw_data, 9)
    idat_crc = zlib.crc32(b'IDAT' + compressed) & 0xffffffff
    png += struct.pack('>I', len(compressed)) + b'IDAT' + compressed + struct.pack('>I', idat_crc)

    # IEND chunk
    iend_crc = zlib.crc32(b'IEND') & 0xffffffff
    png += struct.pack('>I', 0) + b'IEND' + struct.pack('>I', iend_crc)

    path.write_bytes(png)

# Required icon sizes for iOS
sizes = [
    # iPhone
    (20, 2, "20x20@2x.png"),
    (20, 3, "20x20@3x.png"),
    (29, 2, "29x29@2x.png"),
    (29, 3, "29x29@3x.png"),
    (40, 2, "40x40@2x.png"),
    (40, 3, "40x40@3x.png"),
    (60, 2, "60x60@2x.png"),
    (60, 3, "60x60@3x.png"),
    # iPad
    (20, 1, "20x20@1x~ipad.png"),
    (20, 2, "20x20@2x~ipad.png"),
    (29, 1, "29x29@1x~ipad.png"),
    (29, 2, "29x29@2x~ipad.png"),
    (40, 1, "40x40@1x~ipad.png"),
    (40, 2, "40x40@2x~ipad.png"),
    (76, 2, "76x76@2x~ipad.png"),
    (83, 2, "83.5x83.5@2x~ipad.png"),
    # App Store
    (1024, 1, "1024x1024.png"),
]

icon_dir = Path("/tmp/XCode-FastDrop/FastDrop/Assets.xcassets/AppIcon.appiconset")
icon_dir.mkdir(parents=True, exist_ok=True)

for base_size, scale, filename in sizes:
    size = int(base_size * scale)
    write_png(icon_dir / filename, size, size)
    print(f"Generated {filename} ({size}x{size})")

print("Done! Icons generated in Assets.xcassets/AppIcon.appiconset/")