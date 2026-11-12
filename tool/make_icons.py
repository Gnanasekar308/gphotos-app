"""Generates the Gphotos launcher icons from tool/icon/gphotos_icon_source.png.

  python tool/make_icons.py

Writes:
  android/app/src/main/res/mipmap-*/ic_launcher.png, ic_launcher_round.png (legacy, API < 26)
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png (adaptive foreground, 108dp)
  android/app/src/main/res/mipmap-anydpi-v26/ic_launcher(.xml|_round.xml)
  assets/icon/gphotos_icon.png (in-app logo, 512 px)
Needs Pillow (pip install pillow).
"""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'tool', 'icon', 'gphotos_icon_source.png')
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
DENS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def tile():
    """The rounded-square artwork with the black outer corners made transparent."""
    im = Image.open(SRC).convert('RGB')
    grey = im.convert('L')
    box = grey.point(lambda v: 255 if v > 40 else 0).getbbox()  # glowing frame
    im = im.crop(box)
    side = max(im.size)
    sq = Image.new('RGB', (side, side), (0, 0, 0))
    sq.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    mask = Image.new('L', (side * 4, side * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, side * 4 - 1, side * 4 - 1], radius=int(side * 4 * 0.22), fill=255)
    mask = mask.resize((side, side), Image.LANCZOS)
    out = sq.convert('RGBA')
    out.putalpha(mask)
    return out


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)


def main():
    art = tile()
    for name, k in DENS.items():
        d = os.path.join(RES, 'mipmap-' + name)
        legacy = int(48 * k)
        # legacy square icon: artwork fills the icon
        save(art.resize((legacy, legacy), Image.LANCZOS), os.path.join(d, 'ic_launcher.png'))
        # legacy round icon: circular crop of the artwork centre
        rnd = art.resize((legacy, legacy), Image.LANCZOS)
        m = Image.new('L', (legacy * 4, legacy * 4), 0)
        ImageDraw.Draw(m).ellipse([0, 0, legacy * 4 - 1, legacy * 4 - 1], fill=255)
        rnd.putalpha(Image.composite(rnd.getchannel('A'), Image.new('L', rnd.size, 0), m.resize(rnd.size, Image.LANCZOS)))
        save(rnd, os.path.join(d, 'ic_launcher_round.png'))
        # adaptive foreground: 108dp canvas, artwork inside the 72dp visible area (safe zone 66dp)
        fg = int(108 * k)
        inner = int(70 * k)
        canvas = Image.new('RGBA', (fg, fg), (0, 0, 0, 0))
        a = art.resize((inner, inner), Image.LANCZOS)
        canvas.alpha_composite(a, ((fg - inner) // 2, (fg - inner) // 2))
        save(canvas, os.path.join(d, 'ic_launcher_foreground.png'))
    anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@color/ic_launcher_background"/>\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
           '</adaptive-icon>\n')
    for n in ('ic_launcher.xml', 'ic_launcher_round.xml'):
        with open(os.path.join(anydpi, n), 'w', encoding='utf8', newline='\n') as f:
            f.write(xml)
    save(art.resize((512, 512), Image.LANCZOS), os.path.join(ROOT, 'assets', 'icon', 'gphotos_icon.png'))
    print('icons written')


if __name__ == '__main__':
    main()
