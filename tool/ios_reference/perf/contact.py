#!/usr/bin/env python3
"""Side-by-side contact sheets of the glass audit screenshots of several tiers.

    contact.py <out dir> <label>=<shots dir> [<label>=<shots dir> ...]

Writes one JPEG per shot name found in the first directory, the tiers in the
order given, each labelled, at 0.4 of the shots' resolution.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def font(size):
    for path in ('/System/Library/Fonts/Helvetica.ttc', '/System/Library/Fonts/SFNS.ttf'):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def sheet(images, labels, scale):
    w, h = images[0].size
    w, h = int(w * scale), int(h * scale)
    gap, head = 12, 56
    out = Image.new('RGB', (len(images) * (w + gap) - gap, h + head), (40, 40, 40))
    draw = ImageDraw.Draw(out)
    f = font(36)
    for i, (img, label) in enumerate(zip(images, labels)):
        out.paste(img.convert('RGB').resize((w, h), Image.LANCZOS), (i * (w + gap), head))
        draw.text((i * (w + gap) + 8, 8), label, fill=(255, 255, 255), font=f)
    return out


def main():
    out_dir = sys.argv[1]
    tiers = [arg.split('=', 1) for arg in sys.argv[2:]]
    os.makedirs(out_dir, exist_ok=True)
    first = tiers[0][1]
    for name in sorted(os.listdir(first)):
        if not name.endswith('.png'):
            continue
        paths = [os.path.join(d, name) for _, d in tiers]
        if not all(os.path.exists(p) for p in paths):
            continue
        images = [Image.open(p) for p in paths]
        labels = [label for label, _ in tiers]
        stem = name[:-4]
        sheet(images, labels, 0.4).save(os.path.join(out_dir, stem + '.jpg'), quality=85)


main()
