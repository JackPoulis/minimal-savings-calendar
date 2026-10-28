# Logo concepts

Open [`preview.html`](preview.html) to compare them side by side. It is self-contained, so it opens on its own from anywhere.

| Folder | Concept |
|---|---|
| `a-ascent/` | The balance line climbing to a dashed goal line, ending on a green dot |
| `b-goal-ring/` | A green progress ring around an upward chevron in the accent blue |
| `c-goal-columns/` | Three rising columns: saved (green), upcoming (gray), still to go (outline) |
| `d-monogram/` | A geometric S on the accent blue tile |

All four use the app palette from `flutter_app/lib/theme.dart`: `#1E1E1E` tile, `#007ACC` accent, `#89D185` green, `#6E6E6E` / `#858585` grays, `#D4D4D4` text. The wordmark is Segoe UI Semibold, the app's heading font, converted to outlines so the SVGs need no font installed.

## What each folder holds

| Path | Use |
|---|---|
| `svg/icon.svg` | Master app icon, rounded tile, 1024×1024 |
| `svg/icon-square.svg` | Full-bleed square, for stores and platforms that apply their own mask |
| `svg/icon-small.svg` | Bigger, bolder glyph tuned for 16–32 px |
| `svg/glyph.svg` | The mark alone on transparent, full color |
| `svg/glyph-black.svg`, `svg/glyph-white.svg` | One-color marks for print, stamps and reversed use |
| `svg/lockup-on-light.svg`, `svg/lockup-on-dark.svg` | Icon + “Savings” wordmark, horizontal |
| `png/` | Icon at 16–1024 px and lockups at 4× |
| `windows/app_icon.ico` | 16, 20, 24, 32, 40, 48, 64, 96, 128, 256 px — small sizes use the bolder glyph |
| `android/res/` | Legacy `ic_launcher` / `ic_launcher_round` (mdpi–xxxhdpi), adaptive `ic_launcher_foreground` + `ic_launcher_monochrome` (108 dp, art inside the 66 dp safe zone), `mipmap-anydpi-v26/*.xml`, `values/ic_launcher_background.xml` |
| `android/play-store-512.png` | Google Play listing icon (512×512, full bleed) |

## Installing a concept

Replace `<concept>` with the folder you picked.

- **Windows**: copy `<concept>/windows/app_icon.ico` over `flutter_app/windows/runner/resources/app_icon.ico`.
- **Android**: copy the contents of `<concept>/android/res/` into `flutter_app/android/app/src/main/res/`, and add `android:roundIcon="@mipmap/ic_launcher_round"` next to `android:icon` in `AndroidManifest.xml`.

## Regenerating

Everything comes from `make_logos.py`; change the geometry or colors there and rerun it. It needs `resvg-py`, `fonttools` and `pillow`.

```bash
python make_logos.py branding
```
