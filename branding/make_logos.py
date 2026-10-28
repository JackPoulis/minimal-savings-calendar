"""Generate the Savings logo concepts and every platform asset from one geometry source.

Glyphs are drawn in a 100x100 "glyph box"; tiles place that box at a size
fraction that depends on the target (app tile, Android adaptive safe zone,
small icon sizes).
"""
import io
import shutil
import sys
from pathlib import Path

import resvg_py
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image

OUT = Path(sys.argv[1])

# App palette (flutter_app/lib/theme.dart)
BG = "#1e1e1e"
PANEL = "#252526"
INPUT = "#3c3c3c"
TEXT = "#d4d4d4"
MUTED = "#858585"
ACCENT = "#007acc"
GREEN = "#89d185"
BARGRAY = "#6e6e6e"
WHITE = "#ffffff"

TILE_RADIUS = 0.2237  # iOS-like continuous-corner approximation


# ---------------------------------------------------------------- glyphs
# Each returns SVG markup in glyph-box units. mono=<color> draws it in one
# color (opacity is allowed: Android themed icons use alpha only).

def g_ascent(mono=None, small=False):
    line = mono or ACCENT
    dot = mono or GREEN
    goal = mono or MUTED
    sw, r = (13, 11) if small else (10, 9)
    pts = "10,80 36,52 54,64 86,24"
    out = ""
    if not small:
        out += (f'<line x1="8" y1="24" x2="92" y2="24" stroke="{goal}" stroke-width="3.5" '
                f'stroke-dasharray="7 5" stroke-linecap="butt" opacity="{0.55 if mono else 1}"/>')
    out += (f'<polyline points="{pts}" fill="none" stroke="{line}" stroke-width="{sw}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')
    out += f'<circle cx="86" cy="24" r="{r}" fill="{dot}"/>'
    return out


def g_ring(mono=None, small=False):
    track = mono or INPUT
    arc = mono or GREEN
    chev = mono or ACCENT
    rr, sw, csw = (36, 15, 13) if small else (38, 12, 10)
    top = 50 - rr
    left = 50 - rr
    return (
        f'<circle cx="50" cy="50" r="{rr}" fill="none" stroke="{track}" stroke-width="{sw}" '
        f'opacity="{0.35 if mono else 1}"/>'
        f'<path d="M50 {top} A{rr} {rr} 0 1 1 {left} 50" fill="none" stroke="{arc}" '
        f'stroke-width="{sw}" stroke-linecap="round"/>'
        f'<polyline points="36,58 50,44 64,58" fill="none" stroke="{chev}" stroke-width="{csw}" '
        f'stroke-linecap="round" stroke-linejoin="round"/>'
    )


def g_columns(mono=None, small=False):
    have = mono or GREEN
    upcoming = mono or BARGRAY
    goal = mono or MUTED
    ow = 6 if small else 4
    h = ow / 2
    return (
        f'<rect x="8" y="56" width="22" height="32" rx="3" fill="{have}"/>'
        f'<rect x="39" y="36" width="22" height="52" rx="3" fill="{upcoming}" '
        f'opacity="{0.55 if mono else 1}"/>'
        f'<rect x="{70 + h}" y="{12 + h}" width="{22 - ow}" height="{76 - ow}" rx="{3 - h / 2}" '
        f'fill="none" stroke="{goal}" stroke-width="{ow}"/>'
    )


def g_monogram(mono=None, small=False):
    c = mono or WHITE
    sw = 14 if small else 12
    return (
        f'<path d="M63.86 26 A16 16 0 1 0 50 50 A16 16 0 1 1 36.14 74" fill="none" '
        f'stroke="{c}" stroke-width="{sw}" stroke-linecap="butt"/>'
    )


CONCEPTS = {
    "a-ascent": dict(name="Ascent", glyph=g_ascent, tile=BG,
                     blurb="The balance line climbing to the dashed goal line, ending on a green dot — the app's own chart, reduced to one stroke."),
    "b-goal-ring": dict(name="Goal Ring", glyph=g_ring, tile=BG,
                        blurb="A progress ring three-quarters full in green around an upward chevron in the accent blue."),
    "c-goal-columns": dict(name="Goal Columns", glyph=g_columns, tile=BG,
                           blurb="Three rising columns in the goal bar's language: saved (green), upcoming (gray), still to go (outline)."),
    "d-monogram": dict(name="Monogram", glyph=g_monogram, tile=ACCENT,
                       blurb="A geometric S, also readable as a winding road, in white on the accent blue."),
}


# ---------------------------------------------------------------- composition

def svg_doc(w, h, body, title=None):
    t = f"<title>{title}</title>" if title else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}">{t}{body}</svg>\n')


def place(glyph_svg, size, frac):
    """Center the 100-unit glyph box at `frac` of a `size` canvas."""
    s = size * frac / 100
    off = size * (1 - frac) / 2
    return f'<g transform="translate({off:g} {off:g}) scale({s:g})">{glyph_svg}</g>'


def tile(c, size=1024, frac=0.58, shape="rounded", inset=0.0, small=False, mono=None, tile_fill=None):
    fill = tile_fill or c["tile"]
    i = size * inset
    s = size - 2 * i
    if shape == "rounded":
        bg = f'<rect x="{i:g}" y="{i:g}" width="{s:g}" height="{s:g}" rx="{s * (0.18 if small else TILE_RADIUS):g}" fill="{fill}"/>'
    elif shape == "circle":
        bg = f'<circle cx="{size / 2:g}" cy="{size / 2:g}" r="{s / 2:g}" fill="{fill}"/>'
    elif shape == "square":
        bg = f'<rect width="{size}" height="{size}" fill="{fill}"/>'
    else:
        bg = ""
    g = c["glyph"](mono=mono, small=small)
    return svg_doc(size, size, bg + place(g, size, frac))


def render(svg, px, path=None):
    png = resvg_py.svg_to_bytes(svg_string=svg, width=px, height=px)
    img = Image.open(io.BytesIO(bytes(png))).convert("RGBA")
    if path:
        path.parent.mkdir(parents=True, exist_ok=True)
        img.save(path, optimize=True)
    return img


def render_wh(svg, w, h, path):
    png = resvg_py.svg_to_bytes(svg_string=svg, width=w, height=h)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(png))


def save_ico(c, sizes, path):
    imgs = [render(icon_for_px(c, px), px) for px in sizes]
    path.parent.mkdir(parents=True, exist_ok=True)
    big = imgs[-1]
    big.save(path, format="ICO", sizes=[(i.width, i.height) for i in imgs], append_images=imgs[:-1])


def icon_for_px(c, px):
    """App tile tuned per pixel size: tiny sizes get a bigger, bolder glyph."""
    if px <= 32:
        return tile(c, 1024, frac=0.74, small=True)
    if px <= 64:
        return tile(c, 1024, frac=0.66, small=True)
    return tile(c, 1024, frac=0.58)


# ---------------------------------------------------------------- wordmark

FONT = TTFont(r"C:\Windows\Fonts\seguisb.ttf")
GLYPHSET = FONT.getGlyphSet()
CMAP = FONT.getBestCmap()
UPM = FONT["head"].unitsPerEm
CAP = FONT["OS/2"].sCapHeight


def wordmark(text, font_px, x, baseline, color):
    """Text as outlined paths (no font dependency for whoever opens the SVG)."""
    s = font_px / UPM
    pen = SVGPathPen(GLYPHSET)
    cursor = 0
    for ch in text:
        gname = CMAP[ord(ch)]
        tp = TransformPen(pen, (s, 0, 0, -s, x + cursor * s, baseline))
        GLYPHSET[gname].draw(tp)
        cursor += FONT["hmtx"][gname][0]
    return f'<path d="{pen.getCommands()}" fill="{color}"/>', cursor * s


def lockup(c, text_color, page=None, on_dark=False):
    """Horizontal lockup: icon tile + 'Savings', text cap-height centered on the tile.

    A dark tile vanishes on a dark page, so there the bare glyph stands in for it.
    """
    h = 120
    font_px = 76
    gap = 30
    pad = 0
    if on_dark and c["tile"] == BG:
        icon = tile(c, h, frac=0.84, shape=None)
    else:
        icon = tile(c, h, frac=0.58)
    inner = icon[icon.index(">", icon.index("<svg")) + 1: icon.rindex("</svg>")]
    inner = inner.replace("<title>", "<!--").replace("</title>", "-->")
    baseline = h / 2 + (CAP * font_px / UPM) / 2
    word, wlen = wordmark("Savings", font_px, h + gap, baseline, text_color)
    w = round(h + gap + wlen + pad)
    bg = f'<rect width="{w}" height="{h}" fill="{page}"/>' if page else ""
    return svg_doc(w, h, bg + inner + word), w, h


# ---------------------------------------------------------------- build

def build(key, c):
    root = OUT / key
    if root.exists():
        shutil.rmtree(root)

    # --- master vectors
    sv = root / "svg"
    sv.mkdir(parents=True)
    (sv / "icon.svg").write_text(tile(c, 1024, 0.58))
    (sv / "icon-square.svg").write_text(tile(c, 1024, 0.58, shape="square"))
    (sv / "icon-small.svg").write_text(tile(c, 1024, 0.74, small=True))
    (sv / "glyph.svg").write_text(tile(c, 1024, 1.0, shape=None))
    (sv / "glyph-black.svg").write_text(tile(c, 1024, 1.0, shape=None, mono="#000000"))
    (sv / "glyph-white.svg").write_text(tile(c, 1024, 1.0, shape=None, mono=WHITE))
    dark, w, h = lockup(c, TEXT, on_dark=True)
    light, _, _ = lockup(c, BG)
    (sv / "lockup-on-dark.svg").write_text(dark)
    (sv / "lockup-on-light.svg").write_text(light)

    # --- PNG previews of the lockups (2x and 4x)
    for name, svg in (("lockup-on-dark", dark), ("lockup-on-light", light)):
        render_wh(svg, w * 4, h * 4, root / "png" / f"{name}@4x.png")
    for px in (1024, 512, 256):
        render(tile(c, 1024, 0.58), px, root / "png" / f"icon-{px}.png")

    # --- Windows (drop-in for flutter_app/windows/runner/resources/app_icon.ico)
    save_ico(c, [16, 20, 24, 32, 40, 48, 64, 96, 128, 256], root / "windows" / "app_icon.ico")

    # --- Android (drop-in for flutter_app/android/app/src/main/res/)
    res = root / "android" / "res"
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for d, k in dens.items():
        m = res / f"mipmap-{d}"
        legacy = 48 * k
        fg = int(108 * k)
        # Legacy (API < 26): shape inset 2dp in the 48dp square, like Android Studio's Image Asset.
        render(tile(c, 1024, 0.58 * 44 / 48, inset=2 / 48), int(legacy), m / "ic_launcher.png")
        render(tile(c, 1024, 0.58 * 44 / 48, shape="circle", inset=2 / 48), int(legacy), m / "ic_launcher_round.png")
        # Adaptive layers: 108dp canvas, art inside the 66dp safe circle.
        render(tile(c, 1024, 0.50, shape=None), fg, m / "ic_launcher_foreground.png")
        render(tile(c, 1024, 0.50, shape=None, mono=WHITE), fg, m / "ic_launcher_monochrome.png")
    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n'
    )
    (anydpi / "ic_launcher.xml").write_text(adaptive)
    (anydpi / "ic_launcher_round.xml").write_text(adaptive)
    (res / "values").mkdir(exist_ok=True)
    (res / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{c["tile"].upper()}</color>\n</resources>\n'
    )
    render(tile(c, 1024, 0.58, shape="square"), 512, root / "android" / "play-store-512.png")


for key, c in CONCEPTS.items():
    build(key, c)
    print("built", key)


# ---------------------------------------------------------------- preview page

for key, c in CONCEPTS.items():
    for px in (16, 24, 32, 48, 64, 128):
        render(icon_for_px(c, px), px, OUT / key / "png" / f"icon-{px}.png")


def concept_section(key, c):
    sizes = "".join(
        f'<figure><img src="{key}/png/icon-{px}.png" width="{px}" height="{px}" alt=""><figcaption>{px}</figcaption></figure>'
        for px in (16, 24, 32, 48, 64, 128))
    masks = "".join(
        f'<figure><div class="adaptive {m}" style="background:{c["tile"]}">'
        f'<img src="{key}/android/res/mipmap-xxxhdpi/ic_launcher_foreground.png" alt=""></div>'
        f'<figcaption>{m}</figcaption></figure>' for m in ("circle", "squircle", "rounded"))
    themed = (f'<figure><div class="adaptive circle themed">'
              f'<img src="{key}/android/res/mipmap-xxxhdpi/ic_launcher_monochrome.png" alt=""></div>'
              f'<figcaption>themed (Android 13+)</figcaption></figure>')
    return f'''
<section>
  <header><h2>{c["name"]}</h2><code>branding/{key}/</code></header>
  <p>{c["blurb"]}</p>
  <div class="hero">
    <img src="{key}/svg/icon.svg" width="200" height="200" alt="{c["name"]} app icon">
    <div class="stack">
      <div class="sizes light">{sizes}</div>
      <div class="sizes dark">{sizes}</div>
    </div>
  </div>
  <h3>Android adaptive</h3>
  <div class="row">{masks}{themed}</div>
  <h3>Lockups and one-color marks</h3>
  <div class="row">
    <div class="lock light"><img src="{key}/svg/lockup-on-light.svg" height="56" alt=""></div>
    <div class="lock dark"><img src="{key}/svg/lockup-on-dark.svg" height="56" alt=""></div>
    <div class="lock light"><img src="{key}/svg/glyph-black.svg" height="56" alt=""></div>
    <div class="lock dark"><img src="{key}/svg/glyph-white.svg" height="56" alt=""></div>
  </div>
</section>'''


html = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Savings Logo Concepts</title>
<style>
  :root {{ --bg:{BG}; --panel:{PANEL}; --border:{INPUT}; --text:{TEXT}; --muted:{MUTED}; }}
  * {{ box-sizing: border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--text); font:14px/1.5 'Segoe UI', system-ui, sans-serif; }}
  main {{ max-width:1000px; margin:0 auto; padding:24px 16px 64px; }}
  h1 {{ font-size:20px; font-weight:600; margin:0 0 4px; }}
  .lede {{ color:var(--muted); margin:0 0 24px; }}
  section {{ background:var(--panel); border:1px solid var(--border); border-radius:6px; padding:20px; margin-bottom:20px; }}
  section header {{ display:flex; justify-content:space-between; align-items:baseline; gap:12px; flex-wrap:wrap; }}
  h2 {{ font-size:17px; font-weight:600; margin:0; }}
  h3 {{ font-size:12px; font-weight:600; text-transform:uppercase; letter-spacing:.04em; color:var(--muted); margin:20px 0 8px; }}
  code {{ color:var(--muted); font:12px Consolas, monospace; }}
  p {{ margin:6px 0 16px; color:var(--muted); max-width:70ch; }}
  .hero {{ display:flex; gap:24px; align-items:center; flex-wrap:wrap; }}
  .stack {{ display:flex; flex-direction:column; gap:8px; flex:1; min-width:0; }}
  .sizes {{ display:flex; gap:16px; align-items:flex-end; padding:12px 16px; border-radius:4px; flex-wrap:wrap; }}
  .light {{ background:#f3f3f3; color:#555; }}
  .dark {{ background:#111; color:var(--muted); }}
  figure {{ margin:0; display:flex; flex-direction:column; align-items:center; gap:4px; }}
  figcaption {{ font-size:11px; }}
  .row {{ display:flex; gap:16px; flex-wrap:wrap; align-items:flex-start; }}
  .row figcaption {{ color:var(--muted); }}
  .adaptive {{ width:96px; height:96px; overflow:hidden; position:relative; }}
  .adaptive img {{ position:absolute; left:-24px; top:-24px; width:144px; height:144px; max-width:none; }}  /* 108dp layer, 72dp visible */
  .circle {{ border-radius:50%; }}
  .squircle {{ border-radius:38%; }}
  .rounded {{ border-radius:18%; }}
  .themed {{ background:#d9e6f2; }}
  .themed img {{ filter: brightness(0) saturate(100%) invert(19%) sepia(39%) saturate(1500%) hue-rotate(185deg); }}
  .lock {{ padding:14px 18px; border-radius:4px; }}
  img {{ display:block; max-width:100%; height:auto; }}
  .lock img {{ height:56px; width:auto; }}
</style>
</head>
<body>
<main>
  <h1>Savings logo concepts</h1>
  <p class="lede">Four directions in the app's own palette. Each folder holds the master SVGs plus ready-to-drop-in Windows and Android assets.</p>
  {"".join(concept_section(k, c) for k, c in CONCEPTS.items())}
</main>
</body>
</html>
'''
import base64
import re


def inline(m):
    f = OUT / m.group(1)
    mime = "image/svg+xml" if f.suffix == ".svg" else "image/png"
    return f'src="data:{mime};base64,{base64.b64encode(f.read_bytes()).decode()}"'


# Self-contained, so it opens anywhere (and can be shared) without the folder next to it.
html = re.sub(r'src="([^"]+)"', inline, html)
(OUT / "preview.html").write_text(html, encoding="utf-8")
print("preview written")
