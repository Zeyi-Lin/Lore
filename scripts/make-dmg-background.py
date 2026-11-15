#!/usr/bin/env python3
"""Generate the DMG installer background.

The Finder window is 640x520 points; this draws at 2x (1280x1040) with a 144 DPI
header so Finder shows it at the same point size on Retina displays.
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 1040
SCALE = 2

PAPER = (250, 248, 245)
PAPER_DEEP = (243, 239, 233)
INK = (23, 20, 18)
SECONDARY = (97, 92, 86)
TERTIARY = (152, 144, 135)
HAIRLINE = (233, 228, 220)
RED = (230, 0, 35)
RED_DEEP = (184, 0, 28)
WHITE = (255, 255, 255)

FONT_BOLD = "/System/Library/Fonts/Hiragino Sans GB.ttc"
FONT_REGULAR = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def font(path, size, index=0):
    return ImageFont.truetype(path, size, index=index)


def center_text(draw, text, y, f, fill):
    box = draw.textbbox((0, 0), text, font=f)
    x = (W - (box[2] - box[0])) / 2
    draw.text((x, y), text, font=f, fill=fill)


def main():
    image = Image.new("RGB", (W, H), PAPER)
    draw = ImageDraw.Draw(image)

    bold = font(FONT_BOLD, 46, index=2)
    title = font(FONT_BOLD, 28, index=2)
    subtitle = font(FONT_REGULAR, 24, index=0)
    small = font(FONT_REGULAR, 21, index=0)
    step_title = font(FONT_BOLD, 25, index=2)
    step_body = font(FONT_REGULAR, 20, index=0)
    number = font(FONT_BOLD, 23, index=2)

    # Headline
    center_text(draw, "把 Lore 拖进「应用程序」", 58, bold, INK)
    center_text(draw, "然后在应用程序或启动台里打开它", 126, subtitle, SECONDARY)

    # Dotted guide between the app and the Applications folder. The real Finder
    # icons sit on top of this line at (160, 300) and (480, 300).
    y = 330
    x = 400
    while x < 830:
        draw.ellipse((x - 5, y - 5, x + 5, y + 5), fill=RED)
        x += 26
    draw.line([(842, y - 18), (870, y), (842, y + 18)], fill=RED, width=6, joint="curve")

    # First-launch guidance. The app is ad-hoc signed, so the reference steps
    # mirror what macOS actually shows.
    center_text(draw, "第一次打开被 macOS 拦下，别担心", 566, title, INK)
    center_text(draw, "开发者证书尚未公证，按下面三步放行一次即可。", 610, small, SECONDARY)

    cards = [
        ("1", "点「完成」", "不要点「移到废纸篓」"),
        ("2", "打开「系统设置」", "进入「隐私与安全性」"),
        ("3", "点「仍要打开」", "按提示确认即可"),
    ]
    card_top = 672
    card_height = 300
    card_gap = 24
    card_width = 360
    left = 60
    for index, (number_text, heading, body) in enumerate(cards):
        x0 = left + index * (card_width + card_gap)
        x1 = x0 + card_width
        draw.rounded_rectangle(
            [x0, card_top, x1, card_top + card_height],
            radius=22,
            fill=WHITE,
            outline=HAIRLINE,
            width=2,
        )
        # Number badge
        badge_x = x0 + 26
        badge_y = card_top + 28
        draw.ellipse([badge_x, badge_y, badge_x + 42, badge_y + 42], fill=RED)
        box = draw.textbbox((0, 0), number_text, font=number)
        draw.text(
            (badge_x + (42 - (box[2] - box[0])) / 2, badge_y + 7),
            number_text,
            font=number,
            fill=WHITE,
        )
        draw.text((badge_x + 58, badge_y + 6), heading, font=step_title, fill=INK)

        # A small step illustration: three horizontal rows, with the action row
        # in red, echoing the system dialogs.
        row_y = card_top + 104
        for row in range(3):
            rx0 = x0 + 26
            rx1 = x1 - 26
            rh = 24
            color = (246, 241, 237) if row != 1 else (252, 233, 236)
            draw.rounded_rectangle([rx0, row_y, rx1, row_y + rh], radius=8, fill=color)
            if row == 1:
                draw.rounded_rectangle(
                    [rx0 + 16, row_y + 4, rx0 + 136, row_y + rh - 4],
                    radius=6,
                    fill=RED,
                )
            else:
                draw.rounded_rectangle(
                    [rx0 + 16, row_y + 7, rx0 + 116, row_y + 14],
                    radius=3,
                    fill=(226, 220, 213),
                )
            row_y += rh + 10

        # Body copy, wrapped to the card width.
        draw.text((x0 + 26, card_top + 222), body, font=step_body, fill=SECONDARY)

    # Footer note
    center_text(draw, "只需放行一次 · 之后可以直接打开", 1000, small, TERTIARY)

    image.save(
        "scripts/dmg-background.png",
        format="PNG",
        dpi=(144, 144),
        optimize=True,
    )
    print("wrote scripts/dmg-background.png", image.size)


if __name__ == "__main__":
    main()
