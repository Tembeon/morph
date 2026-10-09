#!/usr/bin/env python3
"""Compare navigation bench variants run in several launches.

usage: compare.py label=run1.json,run2.json [label=...]

Per case and variant, prints the range over launches of: build p95 and
raster p95 (each launch's median over its repeats), vsync slots missed
inside the window (gaps under 200 ms; median over repeats) and the worst
single frame (max of build and raster; median over repeats), in ms.
"""
import json
import statistics
import sys


def load(path):
    report = json.load(open(path))
    budget = report['budget_ms']
    out = {}
    for name, value in report.items():
        if not name.startswith('nav-'):
            continue
        runs = value['runs']
        missed, worst = [], []
        for run in runs:
            frames = run['frames']
            gaps = 0
            for a, b in zip(frames, frames[1:]):
                slots = (b[0] - a[0]) / 1000 / budget
                if slots < 200 / budget:
                    gaps += max(0, round(slots) - 1)
            missed.append(gaps)
            worst.append(max(max(f[1], f[2]) for f in frames) / 1000)
        case = name.split('-', 2)[2].rsplit('-', 1)[0]
        out[case] = {
            'build p95': statistics.median(r['build_p95'] for r in runs),
            'raster p95': statistics.median(r['raster_p95'] for r in runs),
            'missed': statistics.median(missed),
            'worst': statistics.median(worst),
        }
    return out


variants = []
for arg in sys.argv[1:]:
    label, paths = arg.split('=', 1)
    variants.append((label, [load(p) for p in paths.split(',')]))
cases = list(variants[0][1][0])
print(f"{'case':12s} {'metric':10s} " + ' '.join(f'{v[0]:>13s}' for v in variants))
for case in cases:
    for metric in ('build p95', 'raster p95', 'missed', 'worst'):
        cells = []
        for _, launches in variants:
            values = [launch[case][metric] for launch in launches if case in launch]
            cells.append(f'{min(values):5.1f}-{max(values):5.1f}' if values else '-')
        print(f'{case:12s} {metric:10s} ' + ' '.join(f'{c:>13s}' for c in cells))
