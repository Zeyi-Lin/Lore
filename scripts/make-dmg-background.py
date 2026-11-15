#!/usr/bin/env python3
"""Generate the guided DMG installer background (640x560 pt at 2x).

Layout grid: 46 px side margins, 24 px gutters, 20 px card padding, consistent
8 px steps. The three cards mirror the reference install page: a macOS dialog
mock with the action ringed in red, followed by a numbered title and a short
explanation. Keep the icon positions in `dmg-layout.applescript` in sync.
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 1120

PAPER = (250, 248, 245)
INK = (23, 20, 18)
SECONDARY = (97, 92, 86)
TERTIARY = (152, 144, 135)
HAIRLINE = (233, 228, 220)
RED = (230, 0, 35)
WHITE = (255, 255, 255)

CARD_FILL = (255, 255, 255)
CARD_BORDER = (234, 229, 221)
PANEL_FILL = (244, 244, 246)
WINDOW_BORDER = (234, 234, 239)
SKELETON = (224, 224, 228)
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


def lore_icon(draw, center_x, top, size=36):
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
    hx, hy = center_x, top + size * 0.50
    r = size * 0.075
    draw.ellipse([hx - 2 * r, hy - r, hx, hy + r], fill=RED)
    draw.ellipse([hx, hy - r, hx + 2 * r, hy + r], fill=RED)
    draw.polygon([(hx - 1.8 * r, hy + 0.3 * r), (hx + 1.8 * r, hy + 0.3 * r), (hx, hy + 2.2 * r)], fill=RED)


def skeleton_line(draw, x, y, width, height=7, fill=SKELETON):
    draw.rounded_rectangle([x, y, x + width, y + height], radius=height / 2, fill=fill)


def mini_panel(draw, x0, y0, x1, y1):
    draw.rounded_rectangle([x0, y0, x1, y1], radius=16, fill=PANEL_FILL)


def mini_window(draw, x0, y0, x1, y1):
    draw.rounded_rectangle(
        [x0, y0, x1, y1], radius=12, fill=WHITE, outline=WINDOW_BORDER, width=2
    )


def card_one_mini(draw, x0, y0, x1, y1):
    """“Lore is not opened” alert with 完成 highlighted."""
    mini_panel(draw, x0 + 20, y0, x1 - 20, y1)
    wx0, wy0, wx1, wy1 = x0 + 30, y0 + 10, x1 - 30, y1 - 10
    mini_window(draw, wx0, wy0, wx1, wy1)

    cx = (wx0 + wx1) / 2
    lore_icon(draw, cx, wy0 + 16, size=38)
    text_center(draw, "未打开 Lore", cx, wy0 + 64, font(22, bold=True), MINI_INK)
    skeleton_line(draw, cx - 104, wy0 + 102, 208, 8, SKELETON)
    skeleton_line(draw, cx - 78, wy0 + 118, 156, 8, SKELETON)

    button_y = wy1 - 54
    button_h = 28
    left_w, right_w = 108, 68
    total = left_w + 10 + right_w
    left_x = cx - total / 2
    right_x = left_x + left_w + 10

    draw.rounded_rectangle(
        [left_x, button_y, left_x + left_w, button_y + button_h],
        radius=14,
        fill=BUTTON_GRAY,
    )
    text_center(draw, "移到废纸篓", left_x + left_w / 2, button_y + 4, font(17), MINI_SECONDARY)

    draw.rounded_rectangle(
        [right_x, button_y, right_x + right_w, button_y + button_h],
        radius=14,
        fill=BLUE,
    )
    text_center(draw, "完成", right_x + right_w / 2, button_y + 4, font(17, bold=True), WHITE)
    draw.rounded_rectangle(
        [right_x - 5, button_y - 5, right_x + right_w + 5, button_y + button_h + 5],
        radius=19,
        outline=RED,
        width=4,
    )


def card_two_mini(draw, x0, y0, x1, y1):
    """System Settings sidebar with Privacy & Security highlighted."""
    mini_panel(draw, x0 + 20, y0, x1 - 20, y1)
    wx0, wy0, wx1, wy1 = x0 + 30, y0 + 10, x1 - 30, y1 - 10
    mini_window(draw, wx0, wy0, wx1, wy1)

    sidebar_w = 150
    draw.rounded_rectangle(
        [wx0 + 10, wy0 + 10, wx0 + 10 + sidebar_w, wy1 - 10],
        radius=10,
        fill=PANEL_FILL,
    )

    for index in range(3):
        row_y = wy0 + 28 + index * 28
        draw.ellipse([wx0 + 24, row_y, wx0 + 38, row_y + 14], fill=SKELETON)
        skeleton_line(draw, wx0 + 46, row_y + 4, 74, 7, SKELETON)

    row = [wx0 + 14, wy1 - 56, wx0 + 14 + sidebar_w - 4, wy1 - 26]
    draw.rounded_rectangle(row, radius=10, fill=BLUE)
    text_center(draw, "隐私与安全性", (row[0] + row[2]) / 2, row[1] + 6, font(16, bold=True), WHITE)
    draw.rounded_rectangle(
        [row[0] - 5, row[1] - 5, row[2] + 5, row[3] + 5],
        radius=15,
        outline=RED,
        width=4,
    )

    content_x = wx0 + sidebar_w + 34
    skeleton_line(draw, content_x, wy0 + 28, 106, 9, SKELETON)
    skeleton_line(draw, content_x, wy0 + 52, 86, 7, SKELETON)
    skeleton_line(draw, content_x, wy0 + 68, 108, 7, SKELETON)
    skeleton_line(draw, content_x, wy0 + 92, 94, 7, SKELETON)
    skeleton_line(draw, content_x, wy0 + 108, 114, 7, SKELETON)


def card_three_mini(draw, x0, y0, x1, y1):
    """Security panel with 仍要打开 highlighted."""
    mini_panel(draw, x0 + 20, y0, x1 - 20, y1)
    wx0, wy0, wx1, wy1 = x0 + 30, y0 + 10, x1 - 30, y1 - 10
    mini_window(draw, wx0, wy0, wx1, wy1)

    draw.text((wx0 + 20, wy0 + 14), "安全性", font=font(20, bold=True), fill=MINI_INK)
    draw.line([(wx0 + 20, wy0 + 48), (wx1 - 20, wy0 + 48)], fill=HAIRLINE, width=2)
    draw.text((wx0 + 20, wy0 + 60), "已阻止 Lore 以保护 Mac", font=font(17), fill=MINI_SECONDARY)

    button = [wx0 + 20, wy0 + 94, wx0 + 20 + 100, wy0 + 94 + 30]
    draw.rounded_rectangle(button, radius=15, fill=BUTTON_GRAY)
    text_center(draw, "仍要打开", (button[0] + button[2]) / 2, button[1] + 5, font(17, bold=True), MINI_INK)
    draw.rounded_rectangle(
        [button[0] - 5, button[1] - 5, button[2] + 5, button[3] + 5],
        radius=20,
        outline=RED,
        width=4,
    )


def main():
    image = Image.new("RGB", (W, H), PAPER)
    draw = ImageDraw.Draw(image)

    # Hero
    text_center(draw, "把 Lore 拖进「应用程序」", W / 2, 52, font(56, bold=True), INK)
    text_center(draw, "然后在应用程序或启动台里打开它", W / 2, 132, font(26), SECONDARY)

    # Dotted path. Leave a clear 16 pt-ish gap on both sides of the icons.
    y = 340
    x = 430
    while x < 790:
        draw.ellipse((x - 4, y - 4, x + 4, y + 4), fill=RED)
        x += 24
    draw.line([(800, y - 16), (838, y), (800, y + 16)], fill=RED, width=5, joint="curve")

    # First-launch guidance
    text_center(draw, "第一次打开被 macOS 拦下，别担心", W / 2, 560, font(32, bold=True), INK)
    text_center(draw, "开发者证书尚未公证，按下面三步放行一次即可。", W / 2, 604, font(22), SECONDARY)

    cards = [
        ("1", "点「完成」", "不要点「移到废纸篓」", card_one_mini),
        ("2", "打开「系统设置」", "左边选「隐私与安全性」", card_two_mini),
        ("3", "点「仍要打开」", "在安全性一栏，按提示确认", card_three_mini),
    ]
    card_top = 660
    card_height = 340
    card_gap = 24
    card_width = 384
    left = (W - (card_width * 3 + card_gap * 2)) / 2

    for index, (number_text, heading, body, mini) in enumerate(cards):
        x0 = left + index * (card_width + card_gap)
        x1 = x0 + card_width
        draw.rounded_rectangle(
            [x0, card_top, x1, card_top + card_height],
            radius=24,
            fill=CARD_FILL,
            outline=CARD_BORDER,
            width=2,
        )

        mini(draw, x0, card_top + 22, x1, card_top + 222)

        badge_x = x0 + 24
        badge_y = card_top + 240
        draw.ellipse([badge_x, badge_y, badge_x + 40, badge_y + 40], fill=RED)
        box = draw.textbbox((0, 0), number_text, font=font(23, bold=True))
        draw.text(
            (badge_x + (40 - (box[2] - box[0])) / 2, badge_y + 7),
            number_text,
            font=font(23, bold=True),
            fill=WHITE,
        )
        draw.text((badge_x + 56, badge_y + 6), heading, font=font(26, bold=True), fill=INK)
        draw.text((x0 + 24, card_top + 296), body, font=font(20), fill=SECONDARY)

    text_center(draw, "只需放行一次 · 之后可以直接打开", W / 2, 1068, font(19), TERTIARY)

    image.save(
        "scripts/dmg-background.png",
        format="PNG",
        dpi=(144, 144),
        optimize=True,
    )
    print("wrote scripts/dmg-background.png", image.size)


if __name__ == "__main__":
    main()
