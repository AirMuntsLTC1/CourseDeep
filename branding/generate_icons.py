#!/usr/bin/env python3
"""Draws the CourseDeep logo in code and writes every Android launcher/splash asset.
Run:  python3 branding/generate_icons.py      (needs: pip install pillow)
The same geometry is used by app/lib/widgets/logo.dart (CourseDeepLogo)."""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "android-res")
STOPS = [(0.0, (124, 92, 255)), (0.55, (79, 140, 255)), (1.0, (34, 211, 238))]  # violet, blue, cyan

def grad(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2.0 * (size - 1))
            for i in range(len(STOPS) - 1):
                (a, ca), (b, cb) = STOPS[i], STOPS[i + 1]
                if t <= b:
                    k = (t - a) / (b - a)
                    px[x, y] = tuple(int(ca[j] + (cb[j] - ca[j]) * k) for j in range(3))
                    break
    return img

def star(c, r, inner=0.28):
    cx, cy = c
    pts = []
    import math
    for i in range(8):
        ang = -math.pi / 2 + i * math.pi / 4
        rr = r if i % 2 == 0 else r * inner
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    return pts

def glyph(size, scale=1.0, ss=4):
    """White graduation cap + AI sparkle on transparent background."""
    S = size * ss
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    def P(x, y):
        x = 0.5 + (x - 0.5) * scale
        y = 0.5 + (y - 0.5) * scale
        return (x * S, y * S)
    W = (255, 255, 255, 255)
    d.polygon([P(.50, .30), P(.86, .46), P(.50, .62), P(.14, .46)], fill=W)           # board
    d.polygon([P(.28, .55), P(.50, .65), P(.72, .55), P(.72, .68), P(.50, .79), P(.28, .68)], fill=(255, 255, 255, 235))  # cap
    d.line([P(.86, .46), P(.86, .66)], fill=W, width=max(2, int(S * 0.02 * scale)))   # tassel
    r = S * 0.028 * scale
    cx, cy = P(.86, .69)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=W)
    def sp(c, rad):
        pts = star((0, 0), rad)
        cxp, cyp = P(*c)
        return [(cxp + x * S * scale, cyp + y * S * scale) for x, y in pts]
    d.polygon(sp((.76, .22), .115), fill=W)
    d.polygon(sp((.22, .24), .055), fill=(255, 255, 255, 220))
    return im.resize((size, size), Image.LANCZOS)

def rounded_mask(size, radius):
    ss = 4
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size * ss - 1, size * ss - 1], radius=radius * ss, fill=255)
    return m.resize((size, size), Image.LANCZOS)

def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)

def legacy(size, round_=False):
    bg = grad(size).convert("RGBA")
    bg.alpha_composite(glyph(size, 1.0))
    mask = rounded_mask(size, size // 2 if round_ else int(size * 0.22))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)
    return out

DENS = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
for name, k in DENS.items():
    s = int(48 * k)
    save(legacy(s), f"{OUT}/mipmap-{name}/ic_launcher.png")
    save(legacy(s, True), f"{OUT}/mipmap-{name}/ic_launcher_round.png")
    a = int(108 * k)
    fg = Image.new("RGBA", (a, a), (0, 0, 0, 0))
    fg.alpha_composite(glyph(a, 0.62))          # keep inside the 66dp safe zone
    save(fg, f"{OUT}/mipmap-{name}/ic_launcher_foreground.png")
    save(grad(a).convert("RGBA"), f"{OUT}/mipmap-{name}/ic_launcher_background.png")

os.makedirs(f"{OUT}/mipmap-anydpi-v26", exist_ok=True)
xml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
'''
for n in ("ic_launcher.xml", "ic_launcher_round.xml"):
    open(f"{OUT}/mipmap-anydpi-v26/{n}", "w").write(xml)

# splash + Play-store style preview
save(glyph(288, 0.8).convert("RGBA"), f"{OUT}/drawable-nodpi/splash_logo.png")
save(legacy(512), os.path.join(os.path.dirname(__file__), "logo_512.png"))

os.makedirs(f"{OUT}/drawable", exist_ok=True)
open(f"{OUT}/drawable/launch_background.xml", "w").write('''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item><color android:color="#0B0B12"/></item>
    <item><bitmap android:gravity="center" android:src="@drawable/splash_logo"/></item>
</layer-list>
''')
os.makedirs(f"{OUT}/values-v31", exist_ok=True)
open(f"{OUT}/values-v31/styles.xml", "w").write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowSplashScreenBackground">#0B0B12</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_logo</item>
        <item name="android:windowFullscreen">false</item>
        <item name="android:windowDrawsSystemBarBackgrounds">false</item>
    </style>
</resources>
''')
print("done")
