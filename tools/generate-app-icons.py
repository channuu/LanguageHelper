"""Render every app icon size from design 6a (dark) - a stack of flashcards.

Regenerates the Chrome extension icons, the iOS AppIcon set and the Android
launcher icons from one spec. Run from anywhere: python3 tools/generate-app-icons.py
"""
from PIL import Image, ImageDraw
import json, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def oklch_to_srgb(L, C, h_deg):
    h = math.radians(h_deg)
    a, b = C * math.cos(h), C * math.sin(h)
    l_, m_, s_ = (L + 0.3963377774*a + 0.2158037573*b,
                  L - 0.1055613458*a - 0.0638541728*b,
                  L - 0.0894841775*a - 1.2914855480*b)
    l, m, s = l_**3, m_**3, s_**3
    rgb = (+4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
           -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
           -0.0041960863*l - 0.7034186147*m + 1.7076147010*s)
    out = []
    for v in rgb:
        v = 12.92*v if v <= 0.0031308 else 1.055*v**(1/2.4) - 0.055
        out.append(max(0, min(255, round(v*255))))
    return tuple(out)

AMBER = oklch_to_srgb(0.74, 0.16, 45)
INK, CARD3, CARD2 = (0x14, 0x16, 0x1f), (0x34, 0x3a, 0x4c), (0x4a, 0x52, 0x66)

# Master artboard is 200x200 (design 6a); coords are left, top, w, h, radius.
MASTER = 200.0
FULL = [
    (49, 31, 102, 38, 10, CARD3, 255),
    (40, 62, 120, 38, 11, CARD2, 255),
    (31, 93, 138, 76, 15, AMBER, 255),
    (49, 116, 73, 9, 5, INK, 255),
    (49, 138, 44, 9, 5, INK, 115),   # opacity .45
]
MID = FULL[:-1]           # design's 32px tier drops the fainter second line
SMALL_BOARD = 16.0        # design's 16px tier keeps one card and the amber face
SMALL = [
    (3.5, 3, 9, 3.5, 1, CARD2, 255),
    (2.5, 7.5, 11, 6, 2, AMBER, 255),
]

def layers_for(size):
    if size >= 48:  return FULL, MASTER
    if size >= 24:  return MID, MASTER
    return SMALL, SMALL_BOARD

SS = 8  # supersampling factor

def render(size, rounded=True, opaque=False):
    layers, board = layers_for(size)
    px = size * SS
    scale = px / board
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if rounded:
        d.rounded_rectangle([0, 0, px-1, px-1], radius=px*0.24, fill=INK + (255,))
    else:
        d.rectangle([0, 0, px-1, px-1], fill=INK + (255,))
    for left, top, w, h, r, color, alpha in layers:
        layer = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        x0, y0 = left*scale, top*scale
        ImageDraw.Draw(layer).rounded_rectangle(
            [x0, y0, x0 + w*scale - 1, y0 + h*scale - 1],
            radius=r*scale, fill=color + (alpha,))
        img = Image.alpha_composite(img, layer)
    if rounded:
        # design 6a: an inset 1px highlight so the ink square keeps an edge
        # on a dark home screen. Skipped on iOS, where the system mask would
        # clip a ring drawn at our own corner radius.
        ring = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        ImageDraw.Draw(ring).rounded_rectangle(
            [SS/2, SS/2, px-1-SS/2, px-1-SS/2], radius=px*0.24 - SS/2,
            outline=(255, 255, 255, 18), width=SS)
        img = Image.alpha_composite(img, ring)
    img = img.resize((size, size), Image.LANCZOS)
    return img.convert("RGB") if opaque else img

written = []

# Chrome extension
for size in (128, 48, 16):
    p = f"{ROOT}/icons/icon{size}.png"
    render(size).save(p); written.append(p)

# iOS: square and fully opaque - iOS applies its own mask, alpha is rejected.
ios = f"{ROOT}/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset"
meta = json.load(open(f"{ios}/Contents.json"))
for entry in meta["images"]:
    pt = float(entry["size"].split("x")[0])
    px = round(pt * float(entry["scale"].rstrip("x")))
    p = f"{ios}/{entry['filename']}"
    render(px, rounded=False, opaque=True).save(p)
    if p not in written: written.append(p)

# Android legacy launcher icons keep the design's own rounded silhouette.
for d, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
              ("xxhdpi", 144), ("xxxhdpi", 192)):
    p = f"{ROOT}/mobile/android/app/src/main/res/mipmap-{d}/ic_launcher.png"
    render(px).save(p); written.append(p)

print(f"{len(written)} files written")
