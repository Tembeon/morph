#!/usr/bin/env python3
"""Median-of-runs table of the comparison bench, with ratios to Material.

    summarize_bench.py <report.json> [<report.json> ...]

Several reports (launches of the same APK) are pooled: the value per cell is
the median over every run of every launch. With a <name>.gpuwork.txt next to
a report (run_pixel.sh), adds the GPU's active ms and Mcycles per active frame
(the kernel's gpu_work_period of the app's uid, as perf/gpu_scenes.py).
"""
import bisect
import json
import os
import re
import statistics
import sys

KEYS = ['n', 'build_p50', 'build_p95', 'raster_p50', 'raster_p95', 'raster_mean', 'over_budget']
PERIOD = re.compile(r'\s(\d+\.\d+): gpu_work_period: gpu_id=(\d+) uid=(\d+) start_time_ns=(\d+) '
                    r'end_time_ns=(\d+) total_active_duration_ns=(\d+)')
FREQ = re.compile(r'\s(\d+\.\d+): gpu_frequency: state=(\d+) gpu_id=0')


def gpu(path, report):
    base = path[:-len('.json')]
    if not os.path.exists(base + '.gpuwork.txt'):
        return {}
    device = open(base + '.device.txt', errors='replace').read()
    m = re.search(r'uid:(\d+)', device)
    uid = m.group(1) if m else None
    periods, freqs = [], []
    for line in open(base + '.gpuwork.txt', errors='replace'):
        a = PERIOD.search(line)
        if a and a.group(2) == '0' and (uid is None or a.group(3) == uid):
            periods.append((int(a.group(4)), int(a.group(5)), int(a.group(6))))
            continue
        b = FREQ.search(line)
        if b:
            freqs.append((int(float(b.group(1)) * 1e9), int(b.group(2)) * 1000))
    freqs.sort()

    times = [t for t, _ in freqs]

    def freq_at(t):
        i = bisect.bisect_right(times, t) - 1
        return freqs[max(i, 0)][1] if freqs else 0

    periods.sort()
    starts = [p[0] for p in periods]
    longest = max((e - s for s, e, _ in periods), default=0)
    out = {}
    for scene, windows in report.get('windows_us', {}).items():
        runs = report[scene]['runs'] if isinstance(report.get(scene), dict) else []
        per_run = []
        for (start, end), r in zip(windows, runs):
            a_ns, b_ns = start * 1000, end * 1000
            active = cycles = 0.0
            lo = bisect.bisect_left(starts, a_ns - longest)
            hi = bisect.bisect_right(starts, b_ns)
            for s, e, a in periods[lo:hi]:
                overlap = min(e, b_ns) - max(s, a_ns)
                if overlap <= 0 or e <= s:
                    continue
                share = a * overlap / (e - s)
                active += share
                cycles += share * 1e-9 * freq_at((s + e) // 2)
            span = b_ns - a_ns
            per_run.append((active / r['n'] / 1e6, cycles / r['n'] / 1e6, active / span * 100))
        out[scene] = per_run
    return out


def main():
    cells, gpus, caps = {}, {}, {}
    for path in sys.argv[1:]:
        report = json.load(open(path))
        for scene, value in report.items():
            if isinstance(value, dict) and 'runs' in value:
                cells.setdefault(scene, []).extend(value['runs'])
        for scene, runs in gpu(path, report).items():
            gpus.setdefault(scene, []).extend(runs)
        for scene, runs in report.get('g1455_captures', {}).items():
            caps.setdefault(scene, []).extend(runs)
    head = f'{"scene.variant":24}' + ''.join(k.rjust(12) for k in KEYS)
    head += ''.join(k.rjust(11) for k in ['gpu_ms/f', 'Mcyc/f', 'gpu_busy%', 'r50/mat', 'r95/mat', 'cyc/mat', 'caps/f'])
    print(head)
    med = {s: {k: statistics.median(r[k] for r in runs) for k in KEYS} for s, runs in cells.items()}
    gmed = {s: [statistics.median(x[i] for x in runs) for i in range(3)] for s, runs in gpus.items() if runs}
    for scene in sorted(med):
        m = med[scene]
        line = f'{scene:24}' + ''.join(f'{m[k]:12.2f}' for k in KEYS)
        g = gmed.get(scene)
        line += ''.join(f'{v:11.3f}' for v in g) if g else ' ' * 33
        mat = med.get(scene.split('.')[0] + '.material')
        gm = gmed.get(scene.split('.')[0] + '.material')
        line += f'{m["raster_p50"] / mat["raster_p50"]:11.2f}{m["raster_p95"] / mat["raster_p95"]:11.2f}' if mat else ' ' * 22
        line += f'{g[1] / gm[1]:11.2f}' if g and gm else ' ' * 11
        c = caps.get(scene)
        line += f'{statistics.median(c) / m["n"]:11.2f}' if c else ''
        print(line)


main()
