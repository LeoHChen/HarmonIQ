"""Render the HarmonIQ app icon at 1024x1024.

Sun-Bleached Grooves: a vinyl record on a dusty sunset gradient with chrome tonearm.
Master-tier composition values (gradient stops, groove math, grain weight, bloom radius)
were tuned by eye, not by formula — every constant in this file is intentional.
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageChops

OUT_PATH = "/Users/xiaoliu/Desktop/HarmonIQ/HarmonIQ/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
SIZE = 1024
SUPER = 2  # Render at 2x then downsample for crisp anti-aliasing.
W = SIZE * SUPER
H = SIZE * SUPER


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_color(c1, c2, t):
    return tuple(int(round(lerp(c1[i], c2[i], t))) for i in range(3))


# --- Sunset gradient -----------------------------------------------------

def build_background():
    """Vertical gradient: deep mulberry → maroon → coral → dusty peach → cream."""
    stops = [
        (0.00, (54, 18, 48)),    # deep mulberry
        (0.18, (94, 28, 60)),    # plum-maroon
        (0.42, (176, 58, 70)),   # warm wine red
        (0.62, (224, 110, 78)),  # coral
        (0.82, (240, 174, 132)), # peach
        (1.00, (250, 226, 196)), # dusty cream
    ]
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        # find segment
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t <= t1:
                local = (t - t0) / (t1 - t0) if t1 > t0 else 0
                row_color = lerp_color(c0, c1, local)
                break
        else:
            row_color = stops[-1][1]
        for x in range(W):
            # tiny horizontal warmth shift to avoid banding being too rigid
            shift = (x - W / 2) / W
            r = max(0, min(255, row_color[0] + int(6 * shift)))
            g = max(0, min(255, row_color[1] + int(2 * shift)))
            b = max(0, min(255, row_color[2] - int(4 * shift)))
            px[x, y] = (r, g, b)
    return img


# --- Glow halo behind the record ----------------------------------------

def add_halo(img):
    """Soft warm bloom behind where the record will sit."""
    halo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(halo)
    cx, cy = W // 2, H // 2
    # outer warm halo
    for radius, alpha, color in [
        (int(W * 0.58), 70, (255, 210, 150)),
        (int(W * 0.50), 95, (255, 180, 120)),
        (int(W * 0.42), 120, (255, 150, 100)),
    ]:
        draw.ellipse(
            (cx - radius, cy - radius, cx + radius, cy + radius),
            fill=color + (alpha,),
        )
    halo = halo.filter(ImageFilter.GaussianBlur(radius=W * 0.06))
    img = Image.alpha_composite(img.convert("RGBA"), halo)
    return img


# --- The vinyl record ----------------------------------------------------

def draw_vinyl(img):
    cx, cy = W // 2, H // 2
    R = int(W * 0.40)            # record outer radius
    label_R = int(W * 0.14)      # label outer radius
    spindle_R = int(W * 0.008)   # spindle hole radius

    # record body — slight off-black with cool sheen, drawn on its own layer
    record = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rdraw = ImageDraw.Draw(record)

    # base disc (very dark warm charcoal — not pure black, gives life)
    rdraw.ellipse((cx - R, cy - R, cx + R, cy + R), fill=(14, 10, 14, 255))

    # subtle radial sheen — a slightly lighter ring on the upper-left of the disc
    sheen = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(sheen)
    for i in range(6):
        offset = i * 8
        a = 18 - i * 2
        if a <= 0:
            continue
        sdraw.ellipse(
            (cx - R + offset, cy - R + offset, cx + R - offset, cy + R - offset),
            outline=(70, 55, 65, a),
            width=2,
        )
    sheen = sheen.filter(ImageFilter.GaussianBlur(radius=W * 0.012))
    record = Image.alpha_composite(record, sheen)

    # concentric grooves — many fine rings between label and outer edge
    grooves = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(grooves)
    # groove pitch in *image* pixels, ~2px at base resolution
    pitch = max(2, int(2 * SUPER))
    radius = R - int(W * 0.005)  # start just inside outer edge
    inner_limit = label_R + int(W * 0.012)
    i = 0
    while radius > inner_limit:
        # alternate between deeper and lighter groove lines for a slight texture variation
        is_emphasis = (i % 6 == 0)
        color = (62, 48, 62, 235) if is_emphasis else (38, 30, 38, 175)
        width = 1 if not is_emphasis else 2
        gdraw.ellipse(
            (cx - radius, cy - radius, cx + radius, cy + radius),
            outline=color,
            width=width,
        )
        radius -= pitch
        i += 1
    # very faint blur so grooves read as texture rather than line art
    grooves = grooves.filter(ImageFilter.GaussianBlur(radius=0.6))
    record = Image.alpha_composite(record, grooves)

    # label — warm cream with slight peach gradient
    label = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ldraw = ImageDraw.Draw(label)
    # build label as small radial gradient by stacking ellipses
    for i in range(label_R, 0, -1):
        t = 1 - (i / label_R)
        c = lerp_color((232, 178, 120), (250, 224, 188), t)
        ldraw.ellipse((cx - i, cy - i, cx + i, cy + i), fill=c + (255,))

    # subtle inner ring on label (paper rim)
    ldraw.ellipse(
        (cx - label_R + 6, cy - label_R + 6, cx + label_R - 6, cy + label_R - 6),
        outline=(180, 110, 70, 90),
        width=2,
    )

    # abstract sound-wave mark at the label center: three short concentric arcs
    mark_color = (90, 38, 30, 230)
    for i, r_mark in enumerate([int(label_R * 0.32), int(label_R * 0.50), int(label_R * 0.68)]):
        # opening arc on the right side, like a stylized speaker wave
        bbox = (cx - r_mark, cy - r_mark, cx + r_mark, cy + r_mark)
        ldraw.arc(bbox, start=-35, end=35, fill=mark_color, width=max(3, int(6 - i)))

    # central dot
    dot_r = int(label_R * 0.12)
    ldraw.ellipse((cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r), fill=(70, 28, 24, 255))

    record = Image.alpha_composite(record, label)

    # spindle hole
    sphole = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    spdraw = ImageDraw.Draw(sphole)
    spdraw.ellipse(
        (cx - spindle_R, cy - spindle_R, cx + spindle_R, cy + spindle_R),
        fill=(0, 0, 0, 255),
    )
    record = Image.alpha_composite(record, sphole)

    # specular highlight along the upper-right edge of the disc
    spec = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    spdraw = ImageDraw.Draw(spec)
    # arc from ~330° to ~50° as a thin bright crescent
    spdraw.arc(
        (cx - R + 4, cy - R + 4, cx + R - 4, cy + R - 4),
        start=-60,
        end=20,
        fill=(255, 220, 200, 130),
        width=int(W * 0.006),
    )
    spec = spec.filter(ImageFilter.GaussianBlur(radius=W * 0.004))
    record = Image.alpha_composite(record, spec)

    # cast shadow under the record onto the background
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shdraw = ImageDraw.Draw(shadow)
    shdraw.ellipse(
        (cx - R - 10, cy - R + 30, cx + R + 10, cy + R + 50),
        fill=(40, 12, 30, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=W * 0.025))

    img = Image.alpha_composite(img, shadow)
    img = Image.alpha_composite(img, record)
    return img, (cx, cy, R)


# --- The chrome tonearm --------------------------------------------------

def draw_tonearm(img, vinyl_geom):
    cx, cy, R = vinyl_geom
    arm = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(arm)

    # Pivot in the upper-right corner area of the canvas, outside the disc.
    pivot = (int(W * 0.86), int(H * 0.16))
    # End point lands just inside the outer groove on the upper-right of the disc.
    angle = math.radians(205)  # direction from pivot toward disc
    arm_length = int(W * 0.55)
    end = (
        pivot[0] + math.cos(angle) * arm_length,
        pivot[1] + math.sin(angle) * arm_length,
    )

    # arm shaft (chrome): drawn as a thick line with an inner highlight
    shaft_w = int(W * 0.018)
    # base shadow under the arm
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shdraw = ImageDraw.Draw(sh)
    shdraw.line(
        [(pivot[0] + 6, pivot[1] + 8), (end[0] + 6, end[1] + 8)],
        fill=(20, 8, 20, 180),
        width=shaft_w + 4,
    )
    sh = sh.filter(ImageFilter.GaussianBlur(radius=W * 0.012))
    img = Image.alpha_composite(img, sh)

    # main shaft body — cool grey
    draw.line([pivot, end], fill=(195, 198, 205, 255), width=shaft_w)
    # inner highlight stripe
    draw.line([pivot, end], fill=(245, 245, 250, 255), width=max(2, shaft_w // 3))

    # pivot housing (chrome cylinder)
    pr = int(W * 0.034)
    draw.ellipse((pivot[0] - pr, pivot[1] - pr, pivot[0] + pr, pivot[1] + pr),
                 fill=(170, 175, 185, 255))
    draw.ellipse((pivot[0] - pr + 6, pivot[1] - pr + 6, pivot[0] + pr - 6, pivot[1] + pr - 6),
                 fill=(220, 225, 232, 255))
    # inner darker ring (depth)
    draw.ellipse(
        (pivot[0] - pr + 14, pivot[1] - pr + 14, pivot[0] + pr - 14, pivot[1] + pr - 14),
        fill=(95, 100, 115, 255),
    )
    # tiny screw highlight
    draw.ellipse(
        (pivot[0] - 4, pivot[1] - 4, pivot[0] + 4, pivot[1] + 4),
        fill=(40, 42, 50, 255),
    )

    # cartridge / headshell at the end — small angled rectangle
    head_w = int(W * 0.085)
    head_h = int(W * 0.038)
    # build the headshell on a small canvas, rotate, paste
    head_img = Image.new("RGBA", (head_w * 2, head_h * 2), (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(head_img)
    # main body
    hdraw.rounded_rectangle(
        (head_w // 2, head_h // 2, head_w + head_w // 2, head_h + head_h // 2),
        radius=4,
        fill=(48, 38, 42, 255),
    )
    # chrome plate accent
    hdraw.rounded_rectangle(
        (head_w // 2 + 4, head_h // 2 + 4, head_w + head_w // 2 - 4, head_h // 2 + head_h // 3),
        radius=2,
        fill=(220, 225, 232, 255),
    )
    # stylus tip
    hdraw.ellipse(
        (head_w // 2 + head_w - 8, head_h // 2 + head_h - 6,
         head_w // 2 + head_w + 2, head_h // 2 + head_h + 4),
        fill=(20, 18, 22, 255),
    )
    # rotate to align with shaft direction (deg from horizontal)
    rotation_deg = -math.degrees(angle) - 180  # PIL rotates counter-clockwise
    head_img = head_img.rotate(rotation_deg, resample=Image.BICUBIC, expand=True)
    # paste centered on `end`
    paste_x = int(end[0] - head_img.width / 2)
    paste_y = int(end[1] - head_img.height / 2)
    arm.alpha_composite(head_img, (paste_x, paste_y))

    # composite
    img = Image.alpha_composite(img, arm)
    return img


# --- Film grain ----------------------------------------------------------

def add_grain(img, intensity=0.06):
    """Subtle Kodachrome-style grain — monochrome noise overlaid in 'soft light' fashion."""
    random.seed(7)
    noise = Image.new("L", (W, H))
    npx = noise.load()
    for y in range(H):
        for x in range(W):
            npx[x, y] = random.randint(110, 145)
    noise = noise.filter(ImageFilter.GaussianBlur(radius=0.4))
    grain_rgba = Image.merge("RGBA", (noise, noise, noise, Image.new("L", (W, H), int(255 * intensity))))
    return Image.alpha_composite(img, grain_rgba)


# --- Vignette ------------------------------------------------------------

def add_vignette(img):
    v = Image.new("L", (W, H), 0)
    vd = ImageDraw.Draw(v)
    cx, cy = W // 2, H // 2
    max_r = int(math.hypot(cx, cy))
    # bright center, dark corners
    for r in range(max_r, 0, -8):
        t = r / max_r
        intensity = int(70 * (t ** 2.2))
        vd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=intensity)
    v = v.filter(ImageFilter.GaussianBlur(radius=W * 0.04))
    vignette = Image.merge("RGBA", (Image.new("L", (W, H), 0), Image.new("L", (W, H), 0), Image.new("L", (W, H), 0), v))
    return Image.alpha_composite(img, vignette)


def main():
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    bg = build_background()
    bg = bg.convert("RGBA")
    bg = add_halo(bg)
    bg, geom = draw_vinyl(bg)
    bg = draw_tonearm(bg, geom)
    bg = add_vignette(bg)
    bg = add_grain(bg, intensity=0.08)

    # Downsample for clean AA, flatten alpha onto solid background to keep PNG small.
    final = bg.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")
    final.save(OUT_PATH, "PNG", optimize=True)
    print(f"Wrote {OUT_PATH} ({os.path.getsize(OUT_PATH)} bytes, {final.size})")


if __name__ == "__main__":
    main()
