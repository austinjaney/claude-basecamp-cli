#!/usr/bin/env python3
"""Generate a macOS app icon with proper squircle mask and padding.

Rasterizes the pixel-art Claude mascot SVG into a 1024x1024 PNG with:
- Apple-standard superellipse (squircle) shape
- ~10% padding per side (artwork area 824x824 within 1024x1024)
- Anti-aliased mask edges via sub-pixel sampling
- Transparent background outside the squircle

Uses only Python stdlib (struct + zlib) — no Pillow or other image libs needed.
"""

import struct
import zlib
import os

# --- Constants ---
SIZE = 1024
SCALE = 2  # SVG is 512x512, target is 1024x1024
CENTER = SIZE // 2  # 512
HALF_AXIS = 412  # (SIZE - 2*100) / 2 — gives 100px inset per side
SQUIRCLE_N = 5  # Apple's superellipse exponent
AA_SAMPLES = 4  # sub-pixel grid per axis (4x4 = 16 samples)

# --- Colors (R, G, B, A) ---
BG_COLOR = (0x2A, 0x37, 0x3D, 0xFF)
ORANGE = (0xE8, 0x71, 0x4F, 0xFF)
BLACK = (0x11, 0x11, 0x11, 0xFF)
TRANSPARENT = (0, 0, 0, 0)

# --- SVG rect definitions (from claude-adjusted.svg, in SVG coords 512x512) ---
# Order matters: background first, then body parts, then eyes on top
RECTS = [
    # Background
    (0, 0, 512, 512, BG_COLOR),
    # Body
    (96, 96, 320, 32, ORANGE),
    (96, 128, 320, 32, ORANGE),
    # Ears
    (64, 160, 384, 32, ORANGE),
    (64, 192, 384, 32, ORANGE),
    # Lower body
    (96, 224, 320, 32, ORANGE),
    (96, 256, 320, 32, ORANGE),
    (96, 288, 320, 32, ORANGE),
    # Eyes
    (160, 160, 32, 64, BLACK),
    (320, 160, 32, 64, BLACK),
    # Legs
    (128, 352, 32, 64, ORANGE),
    (192, 352, 32, 64, ORANGE),
    (288, 352, 32, 64, ORANGE),
    (352, 352, 32, 64, ORANGE),
]


def squircle_coverage(px, py):
    """Return the fraction of a pixel inside the squircle (0.0 to 1.0).

    Uses sub-pixel sampling for anti-aliasing at the mask edge.
    """
    count = 0
    step = 1.0 / AA_SAMPLES
    offset = step / 2  # center of each sub-pixel
    for si in range(AA_SAMPLES):
        for sj in range(AA_SAMPLES):
            sx = px + offset + si * step
            sy = py + offset + sj * step
            dx = abs(sx - CENTER) / HALF_AXIS
            dy = abs(sy - CENTER) / HALF_AXIS
            if dx ** SQUIRCLE_N + dy ** SQUIRCLE_N <= 1.0:
                count += 1
    return count / (AA_SAMPLES * AA_SAMPLES)


def render():
    """Render the icon to a 1024x1024 RGBA pixel buffer."""
    # Start with transparent canvas
    buf = [TRANSPARENT] * (SIZE * SIZE)

    # Scale factor for artwork within the icon (0.72 = 72% of canvas)
    # This leaves visible background padding around the character
    ART_SCALE = 0.72
    ART_OFFSET = int(SIZE * (1 - ART_SCALE) / 2)  # center the artwork

    # Paint SVG rects
    for (rx, ry, rw, rh, color) in RECTS:
        if color == BG_COLOR:
            # Background fills the entire canvas (squircle mask clips it)
            sx, sy = rx * SCALE, ry * SCALE
            sw, sh = rw * SCALE, rh * SCALE
        else:
            # Character artwork is scaled down and centered
            sx = int(rx * SCALE * ART_SCALE) + ART_OFFSET
            sy = int(ry * SCALE * ART_SCALE) + ART_OFFSET
            sw = int(rw * SCALE * ART_SCALE)
            sh = int(rh * SCALE * ART_SCALE)
        for y in range(sy, sy + sh):
            row = y * SIZE
            for x in range(sx, sx + sw):
                buf[row + x] = color

    # Apply squircle mask
    for y in range(SIZE):
        row = y * SIZE
        for x in range(SIZE):
            coverage = squircle_coverage(x, y)
            if coverage <= 0.0:
                buf[row + x] = TRANSPARENT
            elif coverage < 1.0:
                r, g, b, a = buf[row + x]
                buf[row + x] = (r, g, b, int(a * coverage))

    return buf


def write_png(buf, path):
    """Write an RGBA pixel buffer as a PNG file (pure Python, no libs)."""

    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    # Build raw scanlines (filter byte 0 + RGBA pixels per row)
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)  # filter: none
        row = y * SIZE
        for x in range(SIZE):
            r, g, b, a = buf[row + x]
            raw.extend((r, g, b, a))

    with open(path, "wb") as f:
        # PNG signature
        f.write(b"\x89PNG\r\n\x1a\n")
        # IHDR
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)))
        # IDAT
        compressed = zlib.compress(bytes(raw), 9)
        f.write(chunk(b"IDAT", compressed))
        # IEND
        f.write(chunk(b"IEND", b""))


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(script_dir, "AppIcon_1024x1024.png")

    print("Rendering 1024x1024 icon with squircle mask...")
    buf = render()
    print("Writing PNG...")
    write_png(buf, out_path)
    print(f"Done: {out_path}")


if __name__ == "__main__":
    main()
