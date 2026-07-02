#!/usr/bin/env python3
"""Generates MetalCraft.app's icon (scripts/icon.icns).

Design: macOS squircle over a deep-space gradient with aurora glows
(the launcher's Aurora theme), an isometric pixel-textured block in the
center (echoing the in-app instance icons) with metallic edge highlights.

Renders at 4096px, downsamples with Lanczos, and assembles a multi-size
.icns directly (PNG-in-icns chunks — no Apple tools needed).

    pip3 install pillow && python3 scripts/generate-icon.py
"""
import io
import random
import struct
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 4                      # supersampling factor
SIZE = 1024
C = SIZE * SS

VIOLET = (124, 92, 255)     # Aurora accent
BLUE = (74, 168, 255)       # Aurora secondary
BG_TOP = (17, 19, 36)
BG_BOTTOM = (27, 17, 54)


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_rgb(c1, c2, t):
    return tuple(int(lerp(a, b, t)) for a, b in zip(c1, c2))


def scale_rgb(c, f):
    return tuple(min(255, int(v * f)) for v in c)


def masked(layer, mask):
    r, g, b, a = layer.split()
    return Image.merge("RGBA", (r, g, b, ImageChops.multiply(a, mask)))


def build() -> Image.Image:
    canvas = Image.new("RGBA", (C, C), (0, 0, 0, 0))

    # macOS icon-grid squircle: 824/1024 with ~185px corner radius.
    margin = 100 * SS
    box = (margin, margin, C - margin, C - margin)
    radius = 185 * SS
    mask = Image.new("L", (C, C), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)

    # Background: diagonal gradient.
    small = Image.new("RGBA", (64, 64))
    for y in range(64):
        for x in range(64):
            small.putpixel((x, y), lerp_rgb(BG_TOP, BG_BOTTOM, (x + y) / 126) + (255,))
    canvas.paste(small.resize((C, C), Image.BILINEAR), (0, 0), mask)

    # Aurora glows drifting in from the corners.
    glow = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((int(-0.15 * C), int(-0.05 * C), int(0.55 * C), int(0.45 * C)), fill=VIOLET + (160,))
    gd.ellipse((int(0.45 * C), int(0.55 * C), int(1.15 * C), int(1.1 * C)), fill=BLUE + (135,))
    glow = glow.filter(ImageFilter.GaussianBlur(0.09 * C))
    canvas.alpha_composite(masked(glow, mask))

    # A few floating pixel "particles" like the dashboard background.
    rng = random.Random(7)
    dots = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    for _ in range(26):
        x = rng.uniform(0.14, 0.86) * C
        y = rng.uniform(0.12, 0.88) * C
        side = rng.choice([5, 7, 9]) * SS
        color = rng.choice([VIOLET, BLUE, (215, 205, 255)])
        alpha = rng.randint(22, 60)
        dd.rectangle((x, y, x + side, y + side), fill=color + (alpha,))
    canvas.alpha_composite(masked(dots, mask))

    # --- Isometric pixel cube -------------------------------------------
    cx, cy_top = C / 2, C * 0.415      # center x, center y of the top diamond
    s = C * 0.26                        # half-width
    t = s * 0.5                         # 2:1 isometric squash
    h = s * 0.98                        # side-face height
    grid = 4                            # 4x4 pixel texture per face

    # Soft shadow + glow behind the cube for depth.
    depth = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    ddraw = ImageDraw.Draw(depth)
    ddraw.ellipse((cx - s * 1.05, cy_top + t + h - 0.03 * C,
                   cx + s * 1.05, cy_top + t + h + 0.10 * C), fill=(0, 0, 0, 130))
    ddraw.ellipse((cx - s * 1.25, cy_top - t - 0.06 * C,
                   cx + s * 1.25, cy_top + t + h + 0.02 * C), fill=(196, 178, 255, 46))
    depth = depth.filter(ImageFilter.GaussianBlur(0.035 * C))
    canvas.alpha_composite(masked(depth, mask))

    draw = ImageDraw.Draw(canvas)
    jitter = random.Random(42)

    def cell_fill(base, magnitude=0.10):
        return scale_rgb(base, 1 + jitter.uniform(-magnitude, magnitude))

    # Top face: diamond, bright violet→blue across the diagonal.
    def top_pt(i, j):
        return (cx + (i - j) * s, cy_top + (i + j - 1) * t)

    for gi in range(grid):
        for gj in range(grid):
            i0, j0 = gi / grid, gj / grid
            i1, j1 = (gi + 1) / grid, (gj + 1) / grid
            base = lerp_rgb((172, 143, 255), (128, 196, 255), (gi + gj) / (2 * grid - 2))
            draw.polygon([top_pt(i0, j0), top_pt(i1, j0), top_pt(i1, j1), top_pt(i0, j1)],
                         fill=cell_fill(base) + (255,))

    # Side faces: vertical parallelograms, left lighter than right.
    def side_pt(x0, y0, x1, y1, a, b):
        return (lerp(x0, x1, a), lerp(y0, y1, a) + b * h)

    def paint_side(x0, y0, x1, y1, c_from, c_to, shade):
        for ga in range(grid):
            for gb in range(grid):
                a0, b0 = ga / grid, gb / grid
                a1, b1 = (ga + 1) / grid, (gb + 1) / grid
                base = scale_rgb(lerp_rgb(c_from, c_to, (ga + gb) / (2 * grid - 2)), shade)
                draw.polygon([side_pt(x0, y0, x1, y1, a0, b0), side_pt(x0, y0, x1, y1, a1, b0),
                              side_pt(x0, y0, x1, y1, a1, b1), side_pt(x0, y0, x1, y1, a0, b1)],
                             fill=cell_fill(base) + (255,))

    w_top = (cx - s, cy_top)            # west corner of top diamond
    s_top = (cx, cy_top + t)            # south corner (front)
    e_top = (cx + s, cy_top)            # east corner
    paint_side(*w_top, *s_top, (124, 92, 255), (96, 148, 250), 0.74)   # left face
    paint_side(*s_top, *e_top, (124, 92, 255), (96, 148, 250), 0.46)   # right face

    # Metallic edge glints along the top rim and the front vertical edge.
    rim = (236, 230, 255)
    lw = max(3 * SS, 2)
    n_top = (cx, cy_top - t)
    draw.line([w_top, n_top, e_top], fill=rim + (215,), width=lw)
    draw.line([w_top, s_top, e_top], fill=rim + (150,), width=lw)
    draw.line([s_top, (s_top[0], s_top[1] + h)], fill=rim + (110,), width=lw)

    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def write_icns(img: Image.Image, path: Path):
    pngs = {}
    for size in (16, 32, 64, 128, 256, 512, 1024):
        buf = io.BytesIO()
        img.resize((size, size), Image.LANCZOS).save(buf, "PNG")
        pngs[size] = buf.getvalue()

    entries = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
               ("ic08", 256), ("ic09", 512), ("ic10", 1024),
               ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]
    body = b"".join(tag.encode() + struct.pack(">I", len(pngs[size]) + 8) + pngs[size]
                    for tag, size in entries)
    path.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    icon = build()
    icon.save(root / "icon-preview.png")
    write_icns(icon, root / "icon.icns")
    print(f"wrote {root / 'icon.icns'} and icon-preview.png")
