#!/usr/bin/env python3
"""Render the Canta app icon master from the in-app brand mark.

The Dock/Finder icon is generated from the same design as ``CantaMark`` in
``Sources/Canta/Design/Components.swift``: a signature-red squircle carrying two
tilted photo cards, the front one holding the red heart. Keeping the master
generated here means the app icon and the in-app mark stay one artwork.

Usage:  python3 scripts/make-app-icon.py [output.png]
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# Geometry, mirroring CantaMark (values are fractions of the mark size).
CANVAS = 1024
SUPERSAMPLE = 4
PLATE_FRACTION = 0.875          # macOS-style padding around the squircle
PLATE_RADIUS = 0.29             # plate corner radius / plate size
CARD_W, CARD_H = 0.42, 0.54
CARD_RADIUS = 0.09
CARD_ANGLE_BACK, CARD_ANGLE_FRONT = 14.0, -9.0   # PIL: positive = counter-clockwise
CARD_OFFSET_BACK = (-0.075, 0.015)
CARD_OFFSET_FRONT = (0.075, -0.005)
CARD_FILL_ALPHA = 0.42
HEART_SIZE = 0.15
HEART_OFFSET_Y = -0.015
SHADOW_ALPHA = 0.12
SHADOW_BLUR = 0.057             # blur radius / mark size (CantaMark: radius 2 @ 35)
SHADOW_OFFSET_Y = 0.029         # (CantaMark: y 1 @ 35)

RED = (230, 0, 35, 255)         # Theme.red, #E60023
WHITE = (255, 255, 255, 255)


def srgb_profile() -> bytes | None:
    """The system sRGB profile, so repeated renders are byte-identical."""

    for candidate in (
        "/System/Library/ColorSync/Profiles/sRGB Profile.icc",
        "/Library/ColorSync/Profiles/sRGB Profile.icc",
    ):
        path = Path(candidate)
        if path.is_file():
            return path.read_bytes()
    return None


def heart_polygon(size: int) -> list[tuple[float, float]]:
    """A rounded two-lobe heart inscribed in ``size`` x ``size``."""

    # Normalised outline (x, y in 0...1, y down): bottom tip at (0.5, 1).
    segments = [
        ((0.50, 1.00), (0.36, 0.855), (0.12, 0.700), (0.045, 0.520)),
        ((0.045, 0.520), (0.000, 0.330), (0.030, 0.045), (0.225, 0.045)),
        ((0.225, 0.045), (0.320, 0.045), (0.405, 0.070), (0.500, 0.180)),
        ((0.500, 0.180), (0.595, 0.070), (0.680, 0.045), (0.775, 0.045)),
        ((0.775, 0.045), (0.970, 0.045), (1.000, 0.330), (0.955, 0.520)),
        ((0.955, 0.520), (0.880, 0.700), (0.640, 0.855), (0.500, 1.000)),
    ]

    points: list[tuple[float, float]] = []
    steps = 64
    for start, c1, c2, end in segments:
        for i in range(steps):
            t = i / steps
            mt = 1 - t
            x = (mt ** 3) * start[0] + 3 * (mt ** 2) * t * c1[0] + 3 * mt * (t ** 2) * c2[0] + (t ** 3) * end[0]
            y = (mt ** 3) * start[1] + 3 * (mt ** 2) * t * c1[1] + 3 * mt * (t ** 2) * c2[1] + (t ** 3) * end[1]
            points.append((x * size, y * size))
    # Tighten the outline into the 0...1 box (the curves breathe outside it).
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    dx, dy = min(xs), min(ys)
    sx = size / (max(xs) - dx)
    sy = size / (max(ys) - dy)
    return [((x - dx) * sx, (y - dy) * sy) for x, y in points]


def rounded_card(size: tuple[int, int], radius: int, fill: tuple[int, int, int, int]) -> Image.Image:
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        (0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=fill
    )
    return layer


def place(image: Image.Image, layer: Image.Image, center: tuple[float, float]) -> None:
    x = round(center[0] - layer.width / 2)
    y = round(center[1] - layer.height / 2)
    image.alpha_composite(layer, (x, y))


def render(size: int) -> Image.Image:
    scale = size / CANVAS
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    plate_size = round(CANVAS * PLATE_FRACTION * scale)
    plate_center = (size / 2, size / 2)
    plate = rounded_card(
        (plate_size, plate_size), round(plate_size * PLATE_RADIUS), RED
    )
    # Compose inside a plate-sized scratch canvas so card offsets stay relative
    # to the mark, then drop the whole plate onto the transparent canvas.
    mark = Image.new("RGBA", (plate_size, plate_size), (0, 0, 0, 0))
    mark.alpha_composite(plate)

    mark_center = plate_size / 2
    card_w = round(plate_size * CARD_W)
    card_h = round(plate_size * CARD_H)
    card_radius = round(plate_size * CARD_RADIUS)

    def compose_card(front: bool) -> Image.Image:
        card = rounded_card(
            (card_w, card_h),
            card_radius,
            (255, 255, 255, round(255 * CARD_FILL_ALPHA)) if not front else WHITE,
        )
        if front:
            heart_size = round(plate_size * HEART_SIZE)
            heart = Image.new("RGBA", (heart_size, heart_size), (0, 0, 0, 0))
            ImageDraw.Draw(heart).polygon(heart_polygon(heart_size), fill=RED)
            heart_center = (card_w / 2, card_h / 2 + plate_size * HEART_OFFSET_Y)
            place(card, heart, heart_center)
        return card

    back_card = compose_card(front=False)
    rotated_back = back_card.rotate(CARD_ANGLE_BACK, resample=Image.BICUBIC, expand=True)
    back_center = (
        mark_center + plate_size * CARD_OFFSET_BACK[0],
        mark_center + plate_size * CARD_OFFSET_BACK[1],
    )
    place(mark, rotated_back, back_center)

    front_card = compose_card(front=True)
    rotated_front = front_card.rotate(CARD_ANGLE_FRONT, resample=Image.BICUBIC, expand=True)

    # CantaMark blurs the front card itself, so its shadow falls across the
    # translucent back card as well: paint it once the back card is in place.
    shadow = Image.new("RGBA", rotated_front.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, round(255 * SHADOW_ALPHA)), (0, 0), rotated_front.getchannel("A"))
    shadow = shadow.filter(ImageFilter.GaussianBlur(plate_size * SHADOW_BLUR))
    front_center = (
        mark_center + plate_size * CARD_OFFSET_FRONT[0],
        mark_center + plate_size * CARD_OFFSET_FRONT[1],
    )
    place(
        mark,
        shadow,
        (front_center[0], front_center[1] + plate_size * SHADOW_OFFSET_Y),
    )
    place(mark, rotated_front, front_center)

    canvas.alpha_composite(
        mark,
        (
            round(plate_center[0] - plate_size / 2),
            round(plate_center[1] - plate_size / 2),
        ),
    )
    return canvas


def main() -> int:
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "Sources/Canta/Resources/AppIcon/icon_1024.png"
    )
    target.parent.mkdir(parents=True, exist_ok=True)

    big = render(CANVAS * SUPERSAMPLE)
    icon = big.resize((CANVAS, CANVAS), Image.LANCZOS)

    icon.save(target, format="PNG", icc_profile=srgb_profile(), optimize=True)
    print(f"Wrote {target} ({icon.width}x{icon.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
