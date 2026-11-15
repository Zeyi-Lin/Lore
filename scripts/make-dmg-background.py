#!/usr/bin/env python3
"""Generate the guided DMG installer background (640x520 pt at 2x).

The three instruction cards mirror the reference install page: each one shows a
small macOS dialog mock with the action highlighted, followed by a numbered
title and a short explanation. Keep this file and `dmg-layout.applescript` in
sync if icon positions move.
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 1040

PAPER = (250, 248, 245)
PAPER_DEEP = (243, 239, 233)
INK = (23, 20, 18)
SECONDARY = (97, 92, 86)
TERTIARY = (152, 144, 135)
HAIRLINE = (233, 228, 220)
RED = (230, 0, 35)
WHITE = (255, 255, 255)

CARD_FILL = (255, 255, 255)
PANEL_FILL = (244, 244, 246)
WINDOW_FILL = (255, 255, 255)
SKELETON = (224, 224, 228)
SKELETON_DARK = (209, 209, 214)
BLUE = (10, 132, 255)
BUTTON_GRAY = (237, 237, 240)
MINI_INK = (28, 28, 30)
MINI_SECONDARY = (110, 110, 115)

FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def font(size, bold=False):
    return ImageFont.truetype(FONT, size, index=2 if bold else 0)


def text_center(draw, text, center_x, y, f, fill):
    box = draw.textbbox((0, 0), text, font=f)
    draw.text((center_x - (box[2] - box[0]) / 2, y), text, font=f, fill=fill)


def lore_icon(draw, center_x, top, size=32):
    """Small red app tile: enough to read as the Lore icon at this scale."""
    draw.rounded_rectangle(
        [center_x - size / 2, top, center_x + size / 2, top + size],
        radius=size * 0.26,
        fill=RED,
    )
    inner = size * 0.19
    draw.rounded_rectangle(
        [center_x - inner, top + size * 0.24, center_x + inner, top + size * 0.76],
        radius=3,
        fill=WHITE,
    )
    # Tiny heart on the tile.
    hx, hy = center_x, top + size * 0.50
    r = size * 0.075
    draw.ellipse([hx - 2 * r, hy - r, hx, hy + r], fill=RED)
    draw.ellipse([hx, hy - r, hx + 2 * r, hy + r], fill=RED)
    draw.polygon([(hx - 1.8 * r, hy + 0.3 * r), (hx + 1.8 * r, hy + 0.3 * r), (hx, hy + 2.2 * r)], fill=RED)


def mini_panel(draw, x0, y0, x1, y1):
    draw.rounded_rectangle([x0, y0, x1, y1], radius=14, fill=PANEL_FILL)


def mini_window(draw, x0, y0, x1, y1):
    draw.rounded_rectangle([x0, y0, x1, y1], radius=11, fill=WINDOW_FILL,
                           outline=(235, 235, 239), width=2)


def skeleton_line(draw, x, y, width, height=6, fill=SKELETON):
    draw.rounded_rectangle([x, y, x + width, y + height], radius=height / 2, fill=fill)


def card_one_mini(draw, x0, y0, x1, y1):
    """“Lore is not opened” alert with 完成 highlighted."""
    mini_panel(draw, x0 + 14, y0, x1 - 14, y1)
    mini_window(draw, x0 + 28, y0 + 10, x1 - 28, y1 - 10)
    cx = (x0 + x1) / 2
    lore_icon(draw, cx, y0 + 26, size=34)

    title = font(21, bold=True)
    text_center(draw, "未打开 Lore", cx, y0 + 70, title, MINI_INK)

    skeleton_line(draw, cx - 100, y0 + 102, 200, 7, SKELETON)
    skeleton_line(draw, cx - 74, y0 + 116, 148, 7, SKELETON)

    button_y = y1 - 48
    button_h = 26
    left_w, right_w = 96, 62
    total = left_w + 10 + right_w
    left_x = cx - total / 2
    right_x = left_x + left_w + 10

    draw.rounded_rectangle(
        [left_x, button_y, left_x + left_w, button_y + button_h],
        radius=13,
        fill=BUTTON_GRAY,
    )
    text_center(draw, "移到废纸篓", left_x + left_w / 2, button_y + 4, font(17), MINI_SECONDARY)

    draw.rounded_rectangle(
        [right_x, button_y, right_x + right_w, button_y + button_h],
        radius=13,
        fill=BLUE,
    )
    text_center(draw, "完成", right_x + right_w / 2, button_y + 4, font(17, bold=True), WHITE)

    draw.rounded_rectangle(
        [right_x - 4, button_y - 4, right_x + right_w + 4, button_y + button_h + 4],
        radius=17,
        outline=RED,
        width=4,
    )


def card_two_mini(draw, x0, y0, x1, y1):
    """System Settings sidebar with Privacy & Security highlighted."""
    mini_panel(draw, x0 + 14, y0, x1 - 14, y1)
    mini_window(draw, x0 + 28, y0 + 10, x1 - 28, y1 - 10)
    wx0, wy0 = x0 + 28, y0 + 10
    wx1 = x1 - 28

    sidebar_w = 132
    draw.rounded_rectangle(
        [wx0 + 8, wy0 + 8, wx0 + 8 + sidebar_w, y1 - 20],
        radius=8,
        fill=PANEL_FILL,
    )

    for index in range(3):
        row_y = wy0 + 30 + index * 30
        draw.ellipse([wx0 + 20, row_y, wx0 + 34, row_y + 14], fill=SKELETON)
        skeleton_line(draw, wx0 + 42, row_y + 4, 72, 6, SKELETON)

    row_y = y1 - 98
    row = [wx0 + 14, row_y, wx0 + 14 + sidebar_w - 4, row_y + 28]
    draw.rounded_rectangle(row, radius=9, fill=BLUE)
    text_center(draw, "隐私与安全性", (row[0] + row[2]) / 2, row_y + 5, font(15, bold=True), WHITE)
    draw.rounded_rectangle(
        [row[0] - 4, row[1] - 4, row[2] + 4, row[3] + 4],
        radius=13,
        outline=RED,
        width=4,
    )

    content_x = wx0 + sidebar_w + 26
    skeleton_line(draw, content_x, wy0 + 28, 92, 8, SKELETON)
    skeleton_line(draw, content_x, wy0 + 48, 76, 6, SKELETON)
    skeleton_line(draw, content_x, wy0 + 62, 96, 6, SKELETON)
    skeleton_line(draw, content_x, wy0 + 84, 84, 6, SKELETON)
    skeleton_line(draw, content_x, wy0 + 98, 104, 6, SKELETON)


def card_three_mini(draw, x0, y0, x1, y1):
    """Security panel with 仍要打开 highlighted."""
    mini_panel(draw, x0 + 14, y0, x1 - 14, y1)
    mini_window(draw, x0 + 28, y0 + 10, x1 - 28, y1 - 10)
    wx0, wy0 = x0 + 28, y0 + 10
    wx1 = x1 - 28

    draw.text((wx0 + 18, wy0 + 14), "安全性", font=font(19, bold=True), fill=MINI_INK)
    draw.line([(wx0 + 18, wy0 + 46), (wx1 - 18, wy0 + 46)], fill=HAIRLINE, width=2)
    draw.text((wx0 + 18, wy0 + 58), "已阻止 Lore 以保护 Mac", font=font(16), fill=MINI_SECONDARY)

    button = [wx0 + 18, wy0 + 88, wx0 + 18 + 92, wy0 + 88 + 27]
    draw.rounded_rectangle(button, radius=13, fill=BUTTON_GRAY)
    text_center(draw, "仍要打开", (button[0] + button[2]) / 2, button[1] + 4, font(16, bold=True), MINI_INK)
    draw.rounded_rectangle(
        [button[0] - 4, button[1] - 4, button[2] + 4, button[3] + 4],
        radius=17,
        outline=RED,
        width=4,
    )


def main():
    image = Image.new("RGB", (W, H), PAPER)
    draw = ImageDraw.Draw(image)

    bold = font(46, bold=True)
    title = font(28, bold=True)
    subtitle = font(24)
    small = font(21)
    step_title = font(25, bold=True)
    step_body = font(20)
    number = font(23, bold=True)

    # Headline
    text_center(draw, "把 Lore 拖进「应用程序」", W / 2, 58, bold, INK)
    text_center(draw, "然后在应用程序或启动台里打开它", W / 2, 126, subtitle, SECONDARY)

    # Dotted guide. Leave breathing room on both sides of the app and folder
    # icons, which Finder draws over this background.
    y = 330
    x = 430
    while x < 790:
        draw.ellipse((x - 5, y - 5, x + 5, y + 5), fill=RED)
        x += 26
    draw.line([(800, y - 18), (838, y), (800, y + 18)], fill=RED, width=6, joint="curve")

    # First-launch guidance.
    text_center(draw, "第一次打开被 macOS 拦下，别担心", W / 2, 566, title, INK)
    text_center(draw, "开发者证书尚未公证，按下面三步放行一次即可。", W / 2, 610, small, SECONDARY)

    cards = [
        ("1", "点「完成」", "不要点「移到废纸篓」", card_one_mini),
        ("2", "打开「系统设置」", "左边选「隐私与安全性」", card_two_mini),
        ("3", "点「仍要打开」", "在安全性一栏，按提示确认", card_three_mini),
    ]
    card_top = 662
    card_height = 320
    card_gap = 28
    card_width = 360
    left = (W - (card_width * 3 + card_gap * 2)) / 2

    for index, (number_text, heading, body, mini) in enumerate(cards):
        x0 = left + index * (card_width + card_gap)
        x1 = x0 + card_width
        draw.rounded_rectangle(
            [x0, card_top, x1, card_top + card_height],
            radius=22,
            fill=CARD_FILL,
            outline=HAIRLINE,
            width=2,
        )

        mini(draw, x0, card_top + 12, x1, card_top + 230)

        badge_x = x0 + 26
        badge_y = card_top + 238
        draw.ellipse([badge_x, badge_y, badge_x + 40, badge_y + 40], fill=RED)
        box = draw.textbbox((0, 0), number_text, font=number)
        draw.text(
            (badge_x + (40 - (box[2] - box[0])) / 2, badge_y + 7),
            number_text,
            font=number,
            fill=WHITE,
        )
        draw.text((badge_x + 56, badge_y + 6), heading, font=step_title, fill=INK)
        draw.text((x0 + 26, card_top + 284), body, font=step_body, fill=SECONDARY)

    text_center(draw, "只需放行一次 · 之后可以直接打开", W / 2, 1000, small, TERTIARY)

    image.save(
        "scripts/dmg-background.png",
        format="PNG",
        dpi=(144, 144),
        optimize=True,
    )
    print("wrote scripts/dmg-background.png", image.size)


if __name__ == "__main__":
    main()
