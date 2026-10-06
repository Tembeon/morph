#!/usr/bin/env python3
"""GPU active time per glass audit scene on Android.

    gpu_scenes.py <tier>.json [<tier>.json ...]

Each report comes from audit_android.sh with AUDIT_GPUWORK=1: the report's
`windows_us` (every timed run's CLOCK_MONOTONIC window) and the
<tier>.gpuwork.txt next to it (the kernel's power/gpu_work_period events of
the app's uid, read from <tier>.device.txt, and power/gpu_frequency). Per
scene: the GPU's active share of the windows, active ms per active frame
(the runs' `n`) and Mcycles per active frame (active time x the clock then;
cycles do not move with DVFS).
"""
import json
import re
import sys

PERIOD = re.compile(r'\s(\d+\.\d+): gpu_work_period: gpu_id=(\d+) uid=(\d+) start_time_ns=(\d+) '
                    r'end_time_ns=(\d+) total_active_duration_ns=(\d+)')
FREQ = re.compile(r'\s(\d+\.\d+): gpu_frequency: state=(\d+) gpu_id=0')


def load(report_path):
    base = report_path[:-len('.json')]
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
    return periods, freqs


def freq_at(freqs, t):
    f = freqs[0][1] if freqs else 0
    for when, hz in freqs:
        if when > t:
            break
        f = hz
    return f


def cost(periods, freqs, start, end):
    active = cycles = 0.0
    for s, e, a in periods:
        overlap = min(e, end) - max(s, start)
        if overlap <= 0 or e <= s:
            continue
        share = a * overlap / (e - s)
        active += share
        cycles += share * 1e-9 * freq_at(freqs, (s + e) // 2)
    return active, cycles


def main():
    print(f'{"report":34} {"scene":12} {"busy %":>7} {"ms/frame":>9} {"Mcyc/frame":>10} {"MHz":>5}')
    for path in sys.argv[1:]:
        report = json.load(open(path))
        periods, freqs = load(path)
        for scene, windows in report.get('windows_us', {}).items():
            runs = report.get(scene, {})
            frames = sum(r['n'] for r in runs.get('runs', [])) if isinstance(runs, dict) else 0
            active = cycles = span = 0.0
            for start, end in windows:
                if end <= start:
                    continue
                a, c = cost(periods, freqs, start * 1000, end * 1000)
                active += a
                cycles += c
                span += (end - start) * 1000
            if span <= 0 or frames <= 0:
                continue
            mhz = cycles / active * 1e3 if active else 0
            print(f'{path.split("/")[-1][:34]:34} {scene:12} {active / span * 100:7.1f} '
                  f'{active / frames / 1e6:9.3f} {cycles / frames / 1e6:10.3f} {mhz:5.0f}')


main()
