#!/usr/bin/env python3
"""Prints the median-of-runs table of one or two glass audit result directories.

    summarize.py <dir>            one table
    summarize.py <before> <after> the after table with deltas against before
"""
import json
import os
import sys

KEYS = ['build_p50', 'build_p95', 'raster_p50', 'raster_p95', 'raster_p99', 'raster_worst', 'span_p95', 'over_budget']


def load(path):
    out = {}
    for name in sorted(os.listdir(path)):
        if not name.endswith('.json'):
            continue
        with open(os.path.join(path, name)) as f:
            report = json.load(f)
        tier = name[:-5]
        for scene, value in report.items():
            if isinstance(value, dict) and 'median' in value:
                out[(tier, scene)] = value['median']
    return out


def main():
    a = load(sys.argv[1])
    b = load(sys.argv[2]) if len(sys.argv) > 2 else None
    rows = b if b is not None else a
    print('tier     scene        ' + ' '.join(k.rjust(12) for k in KEYS))
    for (tier, scene), m in sorted(rows.items()):
        cells = []
        for k in KEYS:
            v = m.get(k)
            if v is None:
                cells.append('-'.rjust(12))
            elif b is not None and (tier, scene) in a:
                cells.append(f'{v:.2f}({v - a[(tier, scene)][k]:+.2f})'.rjust(12))
            else:
                cells.append(f'{v:.2f}'.rjust(12))
        print(f'{tier:8} {scene:12} ' + ' '.join(cells))


main()
