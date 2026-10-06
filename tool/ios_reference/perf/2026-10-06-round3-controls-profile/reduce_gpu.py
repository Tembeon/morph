#!/usr/bin/env python3
"""Reduce temporary GPU-work traces into retained per-window audit evidence.

Usage: reduce_gpu.py <report.json> [<report.json> ...]
Matches perf/gpu_scenes.py weighting with a binary frequency lookup.
"""
import bisect
import hashlib
import json
import re
import statistics
import sys
from pathlib import Path

PERIOD = re.compile(
    r'\s(\d+\.\d+): gpu_work_period: gpu_id=(\d+) uid=(\d+) '
    r'start_time_ns=(\d+) end_time_ns=(\d+) total_active_duration_ns=(\d+)'
)
FREQ = re.compile(r'\s(\d+\.\d+): gpu_frequency: state=(\d+) gpu_id=0')


def reduce(path):
    report = json.loads(path.read_text())
    trace = path.with_suffix('.gpuwork.txt')
    device = path.with_suffix('.device.txt').read_text()
    uid = re.search(r'uid:(\d+)', device).group(1)
    periods, freqs = [], []
    for line in trace.open():
        a = PERIOD.search(line)
        if a and a[2] == '0' and a[3] == uid:
            periods.append(tuple(int(a[i]) for i in [4, 5, 6]))
            continue
        b = FREQ.search(line)
        if b:
            freqs.append((int(float(b[1]) * 1e9), int(b[2]) * 1000))
    periods.sort()
    freqs.sort()
    starts = [s for s, e, a in periods]
    frequency_times = [t for t, hz in freqs]
    longest = max((e - s for s, e, a in periods), default=0)
    out = {
        'trace_sha256': hashlib.sha256(trace.read_bytes()).hexdigest(),
        'gpu_work_periods': len(periods),
        'gpu_frequency_samples': len(freqs),
        'scenes': {},
    }
    for scene, windows in report.get('windows_us', {}).items():
        rows = []
        total_active = total_cycles = total_span = total_frames = 0
        for (start, end), run in zip(windows, report[scene]['runs']):
            a_ns, b_ns = start * 1000, end * 1000
            active = cycles = 0
            lo = bisect.bisect_left(starts, a_ns - longest)
            hi = bisect.bisect_right(starts, b_ns)
            for s, e, a in periods[lo:hi]:
                overlap = min(e, b_ns) - max(s, a_ns)
                if overlap <= 0 or e <= s:
                    continue
                share = a * overlap / (e - s)
                active += share
                i = max(0, bisect.bisect_right(frequency_times, (s + e) // 2) - 1)
                hz = freqs[i][1] if freqs else 0
                cycles += share * 1e-9 * hz
            span, frames = b_ns - a_ns, run['n']
            total_active += active
            total_cycles += cycles
            total_span += span
            total_frames += frames
            rows.append({
                'gpu_ms_per_frame': active / frames / 1e6,
                'Mcycles_per_frame': cycles / frames / 1e6,
                'busy_percent': active / span * 100,
            })
        weighted = {
            'gpu_ms_per_frame': total_active / total_frames / 1e6,
            'Mcycles_per_frame': total_cycles / total_frames / 1e6,
            'busy_percent': total_active / total_span * 100,
        }
        out['scenes'][scene] = {
            'runs': rows,
            'weighted': weighted,
            'median': {k: statistics.median(row[k] for row in rows) for k in rows[0]},
        }
        print(path.name, scene, ' '.join(f'{k}={v:.3f}' for k, v in weighted.items()))
    path.with_suffix('.gpu-summary.json').write_text(json.dumps(out, indent=2) + '\n')


for arg in sys.argv[1:]:
    reduce(Path(arg))
