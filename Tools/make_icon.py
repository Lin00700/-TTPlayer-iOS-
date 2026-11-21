#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""画出 TTPlayer 的 1024×1024 AppIcon（RGB，无 alpha）。

构图：银灰金属外框 + 深海军蓝 LCD 屏 + 20 根青色频谱柱 + 发光的八分音符，
右下角压一枚朱红「千」印，兼顾经典千千静听的银灰与水墨两套皮肤。
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SCALE = 2
W = 1024 * SCALE
OUT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "TTPlayer", "Assets.xcassets",
                 "AppIcon.appiconset", "AppIcon-1024.png")
)

METAL_TOP = (243, 245, 249)
METAL_BOTTOM = (150, 158, 172)
METAL_EDGE = (86, 94, 108)

LCD_TOP = (10, 28, 45)
LCD_BOTTOM = (3, 9, 16)
LCD_EDGE = (6, 12, 20)

BAR_LOW = (26, 96, 196)
BAR_HIGH = (110, 231, 255)
NOTE = (196, 245, 255)
ACCENT = (163, 214, 246)
SEAL = (168, 54, 47)
SEAL_INK = (244, 233, 208)

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    "/usr/share/fonts/pickle-hwp/NotoSansCJKkr-Regular.otf",
    "/usr/share/fonts/truetype/freefont/FreeSerif.ttf",
]


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def vertical_gradient(size, top, bottom):
    width, height = size
    img = Image.new("RGB", (1, height))
    px = img.load()
    for y in range(height):
        px[0, y] = lerp(top, bottom, y / max(1, height - 1))
    return img.resize((width, height), Image.BICUBIC)


def rounded_mask(size, radius, inset=0):
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        [inset, inset, size[0] - 1 - inset, size[1] - 1 - inset],
        radius=radius, fill=255
    )
    return mask


def metal_frame():
    base = vertical_gradient((W, W), METAL_TOP, METAL_BOTTOM)
    draw = ImageDraw.Draw(base)
    # 拉丝
    rnd = random.Random(20261121)
    brush = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(brush)
    for _ in range(1400):
        y = rnd.randint(0, W - 1)
        alpha = rnd.randint(3, 14)
        bdraw.line([(0, y), (W, y)], fill=(255, 255, 255, alpha))
    base = Image.alpha_composite(base.convert("RGBA"), brush)

    # 顶部高光
    glow = Image.new("L", (W, W), 0)
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse([-W * 0.3, -W * 0.55, W * 1.3, W * 0.45], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(W * 0.06))
    base = Image.composite(Image.new("RGBA", (W, W), (255, 255, 255, 255)), base, glow)

    # 外缘：一圈均匀的深金属边 + 内侧亮边，做成真正的机身边框
    edge = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    edraw = ImageDraw.Draw(edge)
    band = int(W * 0.018)
    edraw.rounded_rectangle([band // 2, band // 2, W - 1 - band // 2, W - 1 - band // 2],
                            radius=int(W * 0.21), outline=METAL_EDGE + (150,), width=band)
    inner = int(W * 0.058)
    edraw.rounded_rectangle([inner, inner, W - 1 - inner, W - 1 - inner],
                            radius=int(W * 0.175), outline=(255, 255, 255, 130), width=max(2, int(W * 0.003)))
    edraw.rounded_rectangle([0, 0, W - 1, W - 1], radius=int(W * 0.215),
                            outline=(60, 66, 78, 90), width=max(2, int(W * 0.004)))
    return Image.alpha_composite(base, edge)


def lcd_panel():
    inset = int(W * 0.075)
    radius = int(W * 0.16)
    size = (W - inset * 2, W - inset * 2)

    screen = vertical_gradient(size, LCD_TOP, LCD_BOTTOM)

    # 屏幕上的蓝色辉光
    halo = Image.new("RGBA", size, (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(halo)
    hdraw.ellipse([size[0] * 0.08, -size[1] * 0.15, size[0] * 0.92, size[1] * 0.62],
                  fill=(38, 150, 220, 60))
    halo = halo.filter(ImageFilter.GaussianBlur(size[0] * 0.09))
    screen = Image.alpha_composite(screen.convert("RGBA"), halo)

    # 频谱柱（先做遮罩再贴渐变，柱子在屏幕下半部）
    bars = Image.new("L", size, 0)
    bdraw = ImageDraw.Draw(bars)
    count = 20
    left = size[0] * 0.075
    right = size[0] * 0.925
    gap = size[0] * 0.012
    bar_w = (right - left - gap * (count - 1)) / count
    baseline = size[1] * 0.885
    heights = [0.30, 0.46, 0.60, 0.42, 0.68, 0.84, 0.64, 0.50, 0.76, 0.92,
               0.70, 0.56, 0.80, 0.60, 0.44, 0.66, 0.52, 0.38, 0.50, 0.32]
    for index, factor in enumerate(heights):
        x0 = left + index * (bar_w + gap)
        x1 = x0 + bar_w
        y0 = baseline - size[1] * 0.60 * factor
        bdraw.rounded_rectangle([x0, y0, x1, baseline], radius=bar_w * 0.28, fill=255)

    bar_paint = vertical_gradient((int(size[0]), int(size[1])), BAR_HIGH, BAR_LOW)
    screen = Image.composite(bar_paint.convert("RGBA"), screen, bars)

    # 基线
    line = Image.new("RGBA", size, (0, 0, 0, 0))
    ldraw = ImageDraw.Draw(line)
    ldraw.rectangle([left, baseline + size[1] * 0.012, right, baseline + size[1] * 0.012 + 3],
                    fill=BAR_HIGH + (120,))
    screen = Image.alpha_composite(screen, line)

    # 音符：辉光 + 实心
    font_path = next((path for path in FONT_CANDIDATES if os.path.exists(path)), None)
    note_layer = Image.new("RGBA", size, (0, 0, 0, 0))
    glyph = "♪"
    nfont = None
    if font_path:
        try:
            nfont = ImageFont.truetype(font_path, int(size[1] * 0.46))
        except OSError:
            nfont = None
    ndraw = ImageDraw.Draw(note_layer)
    if nfont is not None:
        bbox = ndraw.textbbox((0, 0), glyph, font=nfont)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        pos = (size[0] * 0.5 - tw / 2 - bbox[0], size[1] * 0.40 - th / 2 - bbox[1])
        ndraw.text(pos, glyph, font=nfont, fill=NOTE + (255,))
    else:
        cx, cy = size[0] * 0.5, size[1] * 0.36
        r = size[0] * 0.075
        ndraw.ellipse([cx - r * 1.5, cy + r * 1.4, cx + r * 0.4, cy + r * 2.6], fill=NOTE + (255,))
        ndraw.rectangle([cx + r * 0.1, cy - r * 2.2, cx + r * 0.4, cy + r * 2.0], fill=NOTE + (255,))

    glow = note_layer.filter(ImageFilter.GaussianBlur(size[0] * 0.045))
    glow = Image.eval(glow, lambda v: min(255, int(v * 1.35)))
    screen = Image.alpha_composite(screen, glow)
    screen = Image.alpha_composite(screen, note_layer)

    # 扫描线
    scan = Image.new("RGBA", size, (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(scan)
    for y in range(0, int(size[1]), 4):
        sdraw.line([(0, y), (size[0], y)], fill=(255, 255, 255, 8))
    screen = Image.alpha_composite(screen, scan)

    # 屏幕高光
    sheen = Image.new("L", size, 0)
    shdraw = ImageDraw.Draw(sheen)
    shdraw.polygon([(0, 0), (size[0], 0), (size[0], size[1] * 0.30), (0, size[1] * 0.16)], fill=52)
    sheen = sheen.filter(ImageFilter.GaussianBlur(size[0] * 0.02))
    screen = Image.composite(Image.new("RGBA", size, (255, 255, 255, 255)), screen, sheen)

    # 屏幕边框
    bezel = Image.new("RGBA", size, (0, 0, 0, 0))
    bezeldraw = ImageDraw.Draw(bezel)
    bezeldraw.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius,
                                outline=LCD_EDGE + (255,), width=int(W * 0.006))
    bezeldraw.rounded_rectangle([int(W * 0.004), int(W * 0.004), size[0] - 1 - int(W * 0.004), size[1] - 1 - int(W * 0.004)],
                                radius=radius - int(W * 0.003),
                                outline=(255, 255, 255, 40), width=max(2, int(W * 0.0015)))
    screen = Image.alpha_composite(screen, bezel)

    screen.putalpha(rounded_mask(size, radius))
    return screen, inset


def seal_badge(size):
    """朱红「千」印"""
    stamp = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(stamp)
    draw.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=int(size[0] * 0.10),
                           fill=SEAL + (238,))
    draw.rounded_rectangle([int(size[0] * 0.07), int(size[1] * 0.07), size[0] - 1 - int(size[0] * 0.07), size[1] - 1 - int(size[1] * 0.07)],
                           radius=int(size[0] * 0.07), outline=SEAL_INK + (150,), width=max(2, int(size[0] * 0.018)))
    font_path = next((path for path in FONT_CANDIDATES if os.path.exists(path)), None)
    if font_path:
        try:
            font = ImageFont.truetype(font_path, int(size[1] * 0.62))
            bbox = draw.textbbox((0, 0), "千", font=font)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            draw.text((size[0] * 0.5 - tw / 2 - bbox[0], size[1] * 0.5 - th / 2 - bbox[1]),
                      "千", font=font, fill=SEAL_INK + (255,))
        except OSError:
            pass
    return stamp


def main():
    canvas = metal_frame()
    screen, inset = lcd_panel()
    canvas.alpha_composite(screen, (inset, inset))

    badge_size = int(W * 0.175)
    badge = seal_badge((badge_size, badge_size)).rotate(-7, expand=True, resample=Image.BICUBIC)
    shadow = Image.new("RGBA", badge.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 120), (0, 0), badge.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(W * 0.012))

    bx = int(W * 0.695)
    by = int(W * 0.125)
    canvas.alpha_composite(shadow, (bx + int(W * 0.006), by + int(W * 0.010)))
    canvas.alpha_composite(badge, (bx, by))

    final = canvas.convert("RGB").resize((1024, 1024), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    final.save(OUT, "PNG")
    print("wrote", OUT, final.size)


if __name__ == "__main__":
    main()
