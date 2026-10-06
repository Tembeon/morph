#!/usr/bin/env python3
"""Menu frames with and without the fusion worker, side by side.

    fusion_ab.py <dir> [<dir> ...]

Each <dir> holds menu_frames_test reports (<tier>.json) from audit.sh /
audit_android.sh. Prints per report the median over its runs of the
active frames' build p50 / p95 / worst and raster p50 / p95, the frames
over budget, and how many fused outlines were served from the worker
(fusion_served_ahead) against fused in the frame (fusion_fused_here).
"""
import json
import os
import sys


def pick(values, q):
    v = sorted(values)
    return v[min(len(v) - 1, int(len(v) * q))] if v else 0.0


def runs(report):
    rate = report.get('refresh_rate') or 60
    budget = 1000 / rate
    out = []
    for run in report['runs']:
        rows = []
        for vs, bs, bf, rs, rf, n in run['timings']:
            b = (bf - bs) / 1000
            r = (rf - rs) / 1000
            if b <= 0.3 and r <= 0.3:
                continue
            rows.append((b, r))
        build = [b for b, _ in rows]
        raster = [r for _, r in rows]
        over = sum(1 for b, r in rows if b > budget or r > budget)
        out.append((pick(build, .5), pick(build, .95), max(build or [0]),
                    pick(raster, .5), pick(raster, .95), over))
    return out


for d in sys.argv[1:]:
    for name in sorted(os.listdir(d)):
        if not name.endswith('.json'):
            continue
        report = json.load(open(os.path.join(d, name)))
        if 'runs' not in report:
            continue
        rs = runs(report)
        med = [pick([r[k] for r in rs], .5) for k in range(6)]
        print(f"{os.path.basename(d):34s} {name[:-5]:8s} build {med[0]:.2f} {med[1]:.2f} {med[2]:.1f} | "
              f"raster {med[3]:.2f} {med[4]:.2f} | over {med[5]:.0f} | ahead "
              f"{report.get('fusion_served_ahead')} here {report.get('fusion_fused_here')}")
