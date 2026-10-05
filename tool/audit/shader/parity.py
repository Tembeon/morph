#!/usr/bin/env python3
"""Reads the shader harness's results (example/integration_test/shader_parity_test.dart).

    parity.py show <dir>                    the run's own table: per case the
                                            difference from the frozen baseline,
                                            the repeat / remount noise (must be 0),
                                            or, for a bench run, ms per layer
    parity.py compare <a> <b> [--tol N] [--which candidate|baseline]
                                            the same case's PNG of two runs, e.g.
                                            Vulkan vs GLES on the Pixel, or a commit
                                            vs its parent: max channel difference,
                                            differing pixels, histogram; exit 1 when
                                            a case exceeds --tol (default 0)
"""
import json
import os
import sys

import numpy as np
from PIL import Image


def show(path):
    report = json.load(open(os.path.join(path, 'report.json')))
    cases = report['cases']
    first = next(iter(cases.values()))
    if 'layer_ms_candidate' in first:
        print(f'{"case":26} {"base ms/layer":>14} {"cand ms/layer":>14} {"gain %":>8}')
        for name, row in cases.items():
            print(f'{name:26} {row["layer_ms_baseline"]:14.3f} {row["layer_ms_candidate"]:14.3f} '
                  f'{row["layer_gain_percent"]:8.1f}')
        return 0
    print(f'{"case":26} {"max":>4} {"pixels":>8} {"repeat":>6} {"remount":>7}  channels  histogram')
    for name, row in cases.items():
        d = row['diff']
        print(f'{name:26} {d["max"]:4} {d["pixels"]:8} {row["repeat"]:6} {row["remount"]:7}  '
              f'{d["channels"]}  {d["histogram"]}')
    return 0


def compare(a, b, tol, which):
    status = 0
    suffix = f'.{which}.png'
    names = sorted(n[:-len(suffix)] for n in os.listdir(a) if n.endswith(suffix))
    print(f'{"case":26} {"max":>4} {"pixels":>8}  histogram')
    for name in names:
        other = os.path.join(b, name + suffix)
        if not os.path.exists(other):
            print(f'{name:26} missing in {b}')
            continue
        x = np.asarray(Image.open(os.path.join(a, name + suffix)).convert('RGBA'), dtype=np.int16)
        y = np.asarray(Image.open(other).convert('RGBA'), dtype=np.int16)
        if x.shape != y.shape:
            print(f'{name:26} size {x.shape} vs {y.shape}')
            status = 1
            continue
        d = np.abs(x - y).max(axis=2)
        hist = {int(k): int(v) for k, v in zip(*np.unique(d[d > 0], return_counts=True))}
        worst = int(d.max())
        if worst > tol:
            status = 1
        print(f'{name:26} {worst:4} {int((d > 0).sum()):8}  {hist}')
    return status


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == 'show':
        return show(sys.argv[2])
    if len(sys.argv) >= 4 and sys.argv[1] == 'compare':
        tol = int(sys.argv[sys.argv.index('--tol') + 1]) if '--tol' in sys.argv else 0
        which = sys.argv[sys.argv.index('--which') + 1] if '--which' in sys.argv else 'candidate'
        return compare(sys.argv[2], sys.argv[3], tol, which)
    print(__doc__)
    return 2


sys.exit(main())
