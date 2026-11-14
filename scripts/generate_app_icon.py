#!/usr/bin/env python3
"""Draws Obviewer's app icon and writes the macOS AppIcon set.

The icon is a page of paper (the macOS icon squircle) with a purple silk
bookmark, a few lines of text, and the gold fleur-de-lis that closes every
note in the reader: ink on paper, with a hint of Louisiana.

Usage: python3 scripts/generate_app_icon.py [output .appiconset directory]
Needs only Pillow; the fleur-de-lis is drawn from curves, not a font.
"""

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

UNIT = 4                      # draw at 4x, then downsample
SIZE = 1024 * UNIT
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("App/Assets.xcassets/AppIcon.appiconset")

PAPER_TOP = (253, 252, 248)
PAPER_BOTTOM = (241, 238, 230)
INK = (35, 38, 43)
PURPLE = (70, 36, 122)        # after LSU purple #461D7C
PURPLE_DEEP = (52, 24, 94)
GOLD_LIGHT = (222, 184, 98)
GOLD_DEEP = (166, 120, 34)


def u(value):
    return int(round(value * UNIT))


def squircle_mask(inset=100, exponent=5.0):
    """macOS-style continuous-corner square on the 1024 grid (824 pt body)."""
    mask = Image.new("L", (SIZE, SIZE), 0)
    half = (1024 - 2 * inset) / 2
    centre = 512
    points = []
    for step in range(720):
        t = 2 * math.pi * step / 720
        c, s = math.cos(t), math.sin(t)
        x = half * math.copysign(abs(c) ** (2 / exponent), c)
        y = half * math.copysign(abs(s) ** (2 / exponent), s)
        points.append((u(centre + x), u(centre + y)))
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask


def vertical_gradient(top, bottom, box=(0, 0, SIZE, SIZE)):
    x0, y0, x1, y1 = box
    grad = Image.new("RGB", (1, y1 - y0))
    for y in range(y1 - y0):
        f = y / max(1, (y1 - y0 - 1))
        grad.putpixel((0, y), tuple(int(a + (b - a) * f) for a, b in zip(top, bottom)))
    return grad.resize((x1 - x0, y1 - y0))


def cubic(p0, p1, p2, p3, steps=48):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        pts.append((
            mt ** 3 * p0[0] + 3 * mt * mt * t * p1[0] + 3 * mt * t * t * p2[0] + t ** 3 * p3[0],
            mt ** 3 * p0[1] + 3 * mt * mt * t * p1[1] + 3 * mt * t * t * p2[1] + t ** 3 * p3[1],
        ))
    return pts


def path(start, *segments):
    """A run of cubic segments: each segment is (c1, c2, end)."""
    pts, current = [start], start
    for c1, c2, end in segments:
        pts += cubic(current, c1, c2, end)[1:]
        current = end
    return pts


def mirror(points):
    return [(-x, y) for x, y in points]


def fleur_de_lis_mask(centre, height):
    """A classic fleur-de-lis on a 240-unit design grid (x centred, y down)."""
    # Central petal: right edge, then the same edge mirrored back up.
    petal = path((0, 0), ((12, 26), (31, 50), (29, 80)), ((27, 106), (15, 120), (12, 136)))
    central = petal + [(12, 150), (-12, 150)] + mirror(petal)[::-1]
    # Side petal: rises from the band, arches outward, curls its tip back down.
    side = path(
        (14, 142),
        ((38, 96), (90, 62), (108, 98)),
        ((116, 116), (102, 134), (88, 126)),
        ((74, 118), (52, 126), (32, 148)),
    )
    # Tail below the band, and the two small lower curls.
    tail = path((10, 150), ((13, 172), (9, 194), (0, 216)))
    tail = tail + mirror(tail)[::-1]
    curl = path(
        (24, 150),
        ((44, 164), (60, 184), (47, 199)),
        ((37, 208), (25, 198), (32, 187)),
        ((37, 178), (28, 164), (16, 152)),
    )
    scale = height / 216
    cx, cy = centre
    top = cy - height / 2

    def place(points):
        return [(u(cx + x * scale), u(top + y * scale)) for x, y in points]

    mask = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(mask)
    for shape in (central, side, mirror(side), tail, curl, mirror(curl)):
        draw.polygon(place(shape), fill=255)
    band = place([(-50, 134), (50, 152)])
    draw.rounded_rectangle((band[0], band[1]), radius=u(8 * scale), fill=255)
    return mask


def main():
    mask = squircle_mask()
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # Soft shadow under the page.
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_alpha = mask.point(lambda a: int(a * 0.30))
    shadow.putalpha(shadow_alpha)
    shadow = shadow.transform(shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -u(10)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(u(14)))
    canvas.alpha_composite(shadow)

    # The page.
    page = vertical_gradient(PAPER_TOP, PAPER_BOTTOM).convert("RGBA")

    # Lines of text: a heavier title line, then body lines of uneven length.
    left = 236
    lines = [(left, 268, 250, 14, 120)] + [
        (left, 324, 340, 7, 52), (left, 356, 370, 7, 52), (left, 388, 310, 7, 52), (left, 420, 350, 7, 52),
    ]
    text_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    tdraw = ImageDraw.Draw(text_layer)
    for x, y, w, h, alpha in lines:
        tdraw.rounded_rectangle((u(x), u(y), u(x + w), u(y + h)), radius=u(h / 2), fill=INK + (alpha,))
    page.alpha_composite(text_layer)

    # The bookmark: a purple silk ribbon tucked in at the top, with a swallowtail end.
    rx0, rx1, ry1, notch = 664, 724, 560, 30
    ribbon_shape = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(ribbon_shape).polygon(
        [(u(rx0), 0), (u(rx1), 0), (u(rx1), u(ry1)), (u((rx0 + rx1) / 2), u(ry1 - notch)), (u(rx0), u(ry1))],
        fill=255,
    )
    ribbon_fill = Image.new("RGBA", (SIZE, SIZE), PURPLE_DEEP + (255,))
    horiz = Image.new("RGB", (u(rx1 - rx0), 1))
    for x in range(horiz.width):
        f = x / max(1, horiz.width - 1)
        shade = 0.5 - 0.5 * math.cos(2 * math.pi * f)   # lighter in the middle: a soft fold
        horiz.putpixel((x, 0), tuple(int(d + (p - d) * shade) for d, p in zip(PURPLE_DEEP, PURPLE)))
    ribbon_fill.paste(horiz.resize((horiz.width, SIZE)), (u(rx0), 0))
    ribbon_shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ribbon_shadow.putalpha(ribbon_shape.point(lambda a: int(a * 0.22)))
    ribbon_shadow = ribbon_shadow.transform(ribbon_shadow.size, Image.AFFINE, (1, 0, -u(5), 0, 1, -u(4)))
    ribbon_shadow = ribbon_shadow.filter(ImageFilter.GaussianBlur(u(5)))
    page.alpha_composite(ribbon_shadow)
    ribbon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ribbon.paste(ribbon_fill, (0, 0), ribbon_shape)
    page.alpha_composite(ribbon)

    # The fleur-de-lis, in old gold, where the reader ends a note. Drawn from
    # cubic curves (right half, mirrored) rather than taken from a font.
    glyph = fleur_de_lis_mask(centre=(512, 690), height=236)
    top, bottom = u(690 - 118), u(690 + 118)
    gold = vertical_gradient(GOLD_LIGHT, GOLD_DEEP, (0, top, SIZE, bottom)).convert("RGBA")
    gold_full = Image.new("RGBA", (SIZE, SIZE), GOLD_DEEP + (255,))
    gold_full.paste(gold, (0, top))
    emboss = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    emboss.putalpha(glyph.point(lambda a: int(a * 0.20)))
    emboss = emboss.transform(emboss.size, Image.AFFINE, (1, 0, 0, 0, 1, -u(3))).filter(ImageFilter.GaussianBlur(u(3)))
    page.alpha_composite(emboss)
    fleur = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    fleur.paste(gold_full, (0, 0), glyph)
    page.alpha_composite(fleur)

    # A hairline edge so the page holds its shape on a white Dock or desktop.
    edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(u(1.5) * 2 + 1)))
    edge_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    edge_layer.putalpha(edge.point(lambda a: int(a * 0.10)))
    page.alpha_composite(edge_layer)

    body = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    body.paste(page, (0, 0), mask)
    canvas.alpha_composite(body)

    master = canvas.resize((1024, 1024), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    images = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            master.resize((px, px), Image.LANCZOS).save(OUT / name, optimize=True)
            images.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
    (OUT / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    catalog = OUT.parent / "Contents.json"
    if not catalog.exists():
        catalog.write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    print(f"Wrote {len(images)} icon images to {OUT}")


if __name__ == "__main__":
    main()
