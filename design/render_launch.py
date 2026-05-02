"""Render the HarmonIQ launch screen image at iPhone 17 Pro Max @3x (1290x2796).

Sun-Bleached Grooves, quieter cousin: same gradient + vinyl disc as the app icon,
but no tonearm — the disc waits, the moment hasn't arrived yet. Outputs @1x/@2x/@3x
PNGs into HarmonIQ/Resources/Assets.xcassets/LaunchImage.imageset/.

Constants are deliberately duplicated from render_icon.py rather than imported, so the
two renderers stay independently runnable and edits to one don't silently shift the
other. Gradient stops, groove pitch, halo radii, grain weight match the icon by intent.
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

# iPhone 17 Pro Max @3x — design-target resolution.
W = 1290
H = 2796

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "HarmonIQ", "Resources", "Assets.xcassets", "LaunchImage.imageset",
)


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_color(c1, c2, t):
    return tuple(int(round(lerp(c1[i], c2[i], t))) for i in range(3))


# --- Sunset gradient (same stops as the icon) ----------------------------

GRADIENT_STOPS = [
    (0.00, (54, 18, 48)),    # deep mulberry
    (0.18, (94, 28, 60)),    # plum-maroon
    (0.42, (176, 58, 70)),   # warm wine red
    (0.62, (224, 110, 78)),  # coral
    (0.82, (240, 174, 132)), # peach
    (1.00, (250, 226, 196)), # dusty cream
]


def build_background():
    img = Image.new("RGB", (W, H))
    px = img.load()
    # Precompute per-row colors — much faster than computing inside the inner loop.
    row_colors = []
    for y in range(H):
        t = y / (H - 1)
        for i in range(len(GRADIENT_STOPS) - 1):
            t0, c0 = GRADIENT_STOPS[i]
            t1, c1 = GRADIENT_STOPS[i + 1]
            if t <= t1:
                local = (t - t0) / (t1 - t0) if t1 > t0 else 0
                row_colors.append(lerp_color(c0, c1, local))
                break
        else:
            row_colors.append(GRADIENT_STOPS[-1][1])
    for y in range(H):
        rc = row_colors[y]
        for x in range(W):
            shift = (x - W / 2) / W
            r = max(0, min(255, rc[0] + int(6 * shift)))
            g = max(0, min(255, rc[1] + int(2 * shift)))
            b = max(0, min(255, rc[2] - int(4 * shift)))
            px[x, y] = (r, g, b)
    return img


# --- Halo behind the disc ------------------------------------------------

def add_halo(img, center, disc_R):
    halo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(halo)
    cx, cy = center
    for radius_mul, alpha, color in [
        (1.45, 70, (255, 210, 150)),
        (1.25, 95, (255, 180, 120)),
        (1.05, 120, (255, 150, 100)),
    ]:
        r = int(disc_R * radius_mul)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color + (alpha,))
    halo = halo.filter(ImageFilter.GaussianBlur(radius=disc_R * 0.15))
    return Image.alpha_composite(img.convert("RGBA"), halo)


# --- Vinyl disc (no tonearm) ---------------------------------------------

def draw_vinyl(img, center, disc_R):
    cx, cy = center
    R = disc_R
    label_R = int(R * 0.35)        # cream center label
    spindle_R = max(2, int(R * 0.020))

    record = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rdraw = ImageDraw.Draw(record)

    rdraw.ellipse((cx - R, cy - R, cx + R, cy + R), fill=(14, 10, 14, 255))

    # subtle radial sheen
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
    sheen = sheen.filter(ImageFilter.GaussianBlur(radius=R * 0.030))
    record = Image.alpha_composite(record, sheen)

    # concentric grooves — fine rings between label and outer edge
    grooves = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(grooves)
    pitch = 2  # match the icon's base-resolution groove pitch
    radius = R - max(2, int(R * 0.012))
    inner_limit = label_R + int(R * 0.030)
    i = 0
    while radius > inner_limit:
        is_emphasis = (i % 6 == 0)
        color = (62, 48, 62, 235) if is_emphasis else (38, 30, 38, 175)
        width = 2 if is_emphasis else 1
        gdraw.ellipse(
            (cx - radius, cy - radius, cx + radius, cy + radius),
            outline=color,
            width=width,
        )
        radius -= pitch
        i += 1
    grooves = grooves.filter(ImageFilter.GaussianBlur(radius=0.6))
    record = Image.alpha_composite(record, grooves)

    # cream center label — radial gradient, no text/wordmark per spec
    label = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ldraw = ImageDraw.Draw(label)
    for i in range(label_R, 0, -1):
        t = 1 - (i / label_R)
        c = lerp_color((232, 178, 120), (250, 224, 188), t)
        ldraw.ellipse((cx - i, cy - i, cx + i, cy + i), fill=c + (255,))
    # paper-rim ring
    ldraw.ellipse(
        (cx - label_R + 6, cy - label_R + 6, cx + label_R - 6, cy + label_R - 6),
        outline=(180, 110, 70, 90),
        width=2,
    )
    record = Image.alpha_composite(record, label)

    # spindle hole
    sphole = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    spdraw = ImageDraw.Draw(sphole)
    spdraw.ellipse(
        (cx - spindle_R, cy - spindle_R, cx + spindle_R, cy + spindle_R),
        fill=(0, 0, 0, 255),
    )
    record = Image.alpha_composite(record, sphole)

    # specular crescent on upper-right edge — sun *inside* the record
    spec = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    spdraw = ImageDraw.Draw(spec)
    spdraw.arc(
        (cx - R + 4, cy - R + 4, cx + R - 4, cy + R - 4),
        start=-60,
        end=20,
        fill=(255, 220, 200, 130),
        width=max(2, int(R * 0.015)),
    )
    spec = spec.filter(ImageFilter.GaussianBlur(radius=R * 0.010))
    record = Image.alpha_composite(record, spec)

    # cast shadow under the disc
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shdraw = ImageDraw.Draw(shadow)
    shdraw.ellipse(
        (cx - R - 10, cy - R + 30, cx + R + 10, cy + R + 50),
        fill=(40, 12, 30, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=R * 0.06))
    img = Image.alpha_composite(img, shadow)
    return Image.alpha_composite(img, record)


# --- Vignette + grain ----------------------------------------------------

def add_vignette(img):
    v = Image.new("L", (W, H), 0)
    vd = ImageDraw.Draw(v)
    cx, cy = W // 2, H // 2
    max_r = int(math.hypot(cx, cy))
    for r in range(max_r, 0, -8):
        t = r / max_r
        intensity = int(70 * (t ** 2.2))
        vd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=intensity)
    v = v.filter(ImageFilter.GaussianBlur(radius=W * 0.04))
    vignette = Image.merge(
        "RGBA",
        (Image.new("L", (W, H), 0), Image.new("L", (W, H), 0), Image.new("L", (W, H), 0), v),
    )
    return Image.alpha_composite(img, vignette)


def add_grain(img, intensity=0.08):
    random.seed(7)
    noise = Image.new("L", (W, H))
    npx = noise.load()
    for y in range(H):
        for x in range(W):
            npx[x, y] = random.randint(110, 145)
    noise = noise.filter(ImageFilter.GaussianBlur(radius=0.4))
    grain_rgba = Image.merge(
        "RGBA",
        (noise, noise, noise, Image.new("L", (W, H), int(255 * intensity))),
    )
    return Image.alpha_composite(img, grain_rgba)


# --- Compose -------------------------------------------------------------

def compose():
    cx, cy = W // 2, H // 2
    # Disc diameter ≈ 60% of the shorter edge (W). Radius is half of that.
    disc_R = int(W * 0.30)
    img = build_background().convert("RGBA")
    img = add_halo(img, (cx, cy), disc_R)
    img = draw_vinyl(img, (cx, cy), disc_R)
    img = add_vignette(img)
    img = add_grain(img, intensity=0.08)
    return img.convert("RGB")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    full = compose()  # 1290x2796 — this is the @3x asset.
    sizes = [
        ("LaunchImage@3x.png", (W, H)),
        ("LaunchImage@2x.png", (W * 2 // 3, H * 2 // 3)),  # 860x1864
        ("LaunchImage.png",    (W * 1 // 3, H * 1 // 3)),  # 430x932
    ]
    for name, size in sizes:
        out = full.resize(size, Image.LANCZOS) if size != (W, H) else full
        path = os.path.join(OUT_DIR, name)
        out.save(path, "PNG", optimize=True)
        print(f"Wrote {path} ({os.path.getsize(path)} bytes, {out.size})")


if __name__ == "__main__":
    main()
