#!/usr/bin/env python3
"""
Generate FastDrop app icon - green droplet with liquid/metaball style
Matches the concept's #30d158 green with gradient and highlight effects
"""
from PIL import Image, ImageDraw, ImageFilter
import os
import json

# FastDrop brand colors
GREEN_PRIMARY = (48, 209, 88)      # #30d158
GREEN_LIGHT = (125, 255, 160)      # #7dffa0
GREEN_DARK = (8, 56, 35)           # #083823
GREEN_GLOW = (84, 255, 128)        # #54ff80
WHITE = (255, 255, 255)

def create_icon(size: int) -> Image.Image:
    """Create a single icon at given size"""
    # Create base image with transparency
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Center and radius calculations
    cx, cy = size // 2, size // 2
    # Droplet fits in 85% of canvas
    r = int(size * 0.38)

    # Draw background circle (subtle dark green base)
    bg_radius = int(size * 0.45)
    for i in range(bg_radius, 0, -1):
        alpha = int(30 * (1 - i / bg_radius))
        draw.ellipse([cx - i, cy - i, cx + i, cy + i], fill=(*GREEN_DARK, alpha))

    # Draw main droplet shape (metaball style - circle with tapered top)
    # Using multiple circles for metaball merge effect

    # Main body circle
    body_y = cy + int(r * 0.15)
    draw.ellipse([cx - r, body_y - r, cx + r, body_y + r], fill=GREEN_PRIMARY)

    # Top circle (smaller, creates droplet taper)
    top_r = int(r * 0.65)
    top_y = cy - int(r * 0.55)
    draw.ellipse([cx - top_r, top_y - top_r, cx + top_r, top_y + top_r], fill=GREEN_PRIMARY)

    # Merge bridge
    bridge_r = int(r * 0.8)
    bridge_y = cy - int(r * 0.15)
    draw.ellipse([cx - bridge_r, bridge_y - bridge_r, cx + bridge_r, bridge_y + bridge_r], fill=GREEN_PRIMARY)

    # Apply slight blur for metaball merge look
    img = img.filter(ImageFilter.GaussianBlur(radius=max(1, size // 100)))

    draw = ImageDraw.Draw(img)

    # Redraw crisp shape after blur
    # Main body
    draw.ellipse([cx - r, body_y - r, cx + r, body_y + r], fill=GREEN_PRIMARY)
    # Top
    draw.ellipse([cx - top_r, top_y - top_r, cx + top_r, top_y + top_r], fill=GREEN_PRIMARY)
    # Bridge
    draw.ellipse([cx - bridge_r, bridge_y - bridge_r, cx + bridge_r, bridge_y + bridge_r], fill=GREEN_PRIMARY)

    # Highlight (top-left) - simulates light reflection
    highlight_r = int(r * 0.35)
    hl_x = cx - int(r * 0.35)
    hl_y = top_y - int(r * 0.15)
    for i in range(highlight_r, 0, -1):
        alpha = int(180 * (1 - i / highlight_r) ** 2)
        draw.ellipse([hl_x - i, hl_y - i, hl_x + i, hl_y + i], fill=(*WHITE, alpha))

    # Secondary highlight (smaller, brighter)
    hl2_r = int(r * 0.15)
    hl2_x = cx - int(r * 0.2)
    hl2_y = top_y - int(r * 0.35)
    for i in range(hl2_r, 0, -1):
        alpha = int(255 * (1 - i / hl2_r))
        draw.ellipse([hl2_x - i, hl2_y - i, hl2_x + i, hl2_y + i], fill=(*WHITE, alpha))

    # Rim light (right edge) - subtle glow
    rim_r = int(r * 0.12)
    rim_x = cx + int(r * 0.7)
    rim_y = body_y
    for i in range(rim_r, 0, -1):
        alpha = int(120 * (1 - i / rim_r))
        draw.ellipse([rim_x - i, rim_y - i, rim_x + i, rim_y + i], fill=(*GREEN_LIGHT, alpha))

    # Inner glow (subtle, center-ish)
    glow_r = int(r * 0.5)
    glow_cx = cx
    glow_cy = cy + int(r * 0.1)
    for i in range(glow_r, int(glow_r * 0.6), -1):
        alpha = int(40 * (1 - (i - glow_r * 0.6) / (glow_r * 0.4)))
        draw.ellipse([glow_cx - i, glow_cy - i, glow_cx + i, glow_cy + i], fill=(*GREEN_LIGHT, alpha))

    return img

def main():
    icon_dir = "/tmp/XCode-FastDrop/FastDrop/Assets.xcassets/AppIcon.appiconset"

    # Required sizes from Contents.json
    sizes = [
        (20, 1, "iphone"), (20, 2, "iphone"), (20, 3, "iphone"),
        (29, 1, "iphone"), (29, 2, "iphone"), (29, 3, "iphone"),
        (40, 1, "iphone"), (40, 2, "iphone"), (40, 3, "iphone"),
        (60, 1, "iphone"), (60, 2, "iphone"), (60, 3, "iphone"),
        (20, 1, "ipad"), (20, 2, "ipad"),
        (29, 1, "ipad"), (29, 2, "ipad"),
        (40, 1, "ipad"), (40, 2, "ipad"),
        (76, 1, "ipad"), (76, 2, "ipad"),
        (83.5, 2, "ipad"),
        (1024, 1, "ios-marketing"),
    ]

    for base_size, scale, idiom in sizes:
        size = int(base_size * scale)
        filename = f"{int(base_size)}x{int(base_size)}"
        if scale > 1:
            filename += f"@{scale}x"
        if idiom == "ipad":
            filename += "~ipad"
        filename += ".png"

        img = create_icon(size)
        # Ensure RGBA mode for transparency
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        img.save(os.path.join(icon_dir, filename), "PNG")
        print(f"Generated {filename} ({size}x{size})")

    print("\nAll icons generated!")

    # Verify
    for f in os.listdir(icon_dir):
        if f.endswith('.png'):
            path = os.path.join(icon_dir, f)
            sz = os.path.getsize(path)
            print(f"  {f}: {sz} bytes")

if __name__ == "__main__":
    main()