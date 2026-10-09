#!/usr/bin/env python3
"""Summarize nav bench reports: median over runs per case. usage: summ.py A.json [B.json]"""
import json, sys, statistics as st
def load(p):
    r = json.load(open(p)); out = {}
    for k, v in r.items():
        if k.startswith('nav-') and isinstance(v, dict) and 'runs' in v:
            runs = v['runs']
            out[k] = {m: st.median(x[m] for x in runs) for m in ('n','build_p50','build_p95','raster_p50','raster_p95','build_mean','raster_mean','over_budget')}
            # frames whose build+raster exceed budget or missed slots (vsync gaps)
            gaps = []
            for x in runs:
                ts = [f[0] for f in x['frames']]
                gaps.append(sum(max(0, round((b - a) / (1e6 / r['refresh_rate'])) - 1) for a, b in zip(ts, ts[1:]) if b - a < 200000))
            out[k]['slots_missed'] = st.median(gaps)
    return r, out
ra, a = load(sys.argv[1]); b = load(sys.argv[2])[1] if len(sys.argv) > 2 else None
print(f"refresh {ra['refresh_rate']:.1f} budget {ra['budget_ms']:.2f}")
cols = ['n','build_p50','build_p95','raster_p50','raster_p95','over_budget','slots_missed']
print(f"{'case':34}" + ''.join(f'{c:>16}' for c in cols))
for k in sorted(a):
    row = f'{k:34}'
    for c in cols:
        row += f'{a[k][c]:>16.2f}' if b is None else f"{a[k][c]:>7.2f}->{b[k][c]:<7.2f}"
    print(row)
