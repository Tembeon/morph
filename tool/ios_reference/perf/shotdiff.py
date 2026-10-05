#!/usr/bin/env python3
"""Compares the glass audit screenshots of two runs, shot by shot.

    shotdiff.py <before dir> <after dir>

Prints per shot the largest channel difference and the share of pixels
whose largest channel difference exceeds 15 (the protocol of
spec/glass-renderer.md: run-to-run noise sits at <= 19 and ~0.001 percent).
"""
import os
import sys

import numpy as np
from PIL import Image


def main():
    a_dir, b_dir = sys.argv[1], sys.argv[2]
    worst = 0
    for name in sorted(os.listdir(a_dir)):
        if not name.endswith('.png'):
            continue
        b_path = os.path.join(b_dir, name)
        if not os.path.exists(b_path):
            print(f'{name:40} missing')
            continue
        a = np.asarray(Image.open(os.path.join(a_dir, name)).convert('RGBA'), dtype=np.int16)
        b = np.asarray(Image.open(b_path).convert('RGBA'), dtype=np.int16)
        if a.shape != b.shape:
            print(f'{name:40} size {a.shape} vs {b.shape}')
            continue
        d = np.abs(a - b).max(axis=2)
        over = (d > 15).mean() * 100
        worst = max(worst, int(d.max()))
        print(f'{name:40} max {int(d.max()):4d}  over15 {over:.4f}%')
    print(f'worst {worst}')


main()
