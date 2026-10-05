#!/usr/bin/env python3
"""GPU time and cycles per glass layer from a shader bench run on Android.

    gpu_work.py <report.json> <gpuwork.txt> [<uid>]

The bench (example/integration_test/shader_parity_test.dart with
SHADER_BENCH) stores each sample's CLOCK_MONOTONIC window; audit_android.sh
with AUDIT_GPUWORK=1 records the kernel's power/gpu_work_period events (the
app's GPU active time in ~8 ms periods, same clock) and power/gpu_frequency.
Per sample: active ns (periods overlapping the window, prorated) and cycles
(active ns x the GPU clock then); per block a layer's cost is (copies - 1)
layers' worth of the difference, per frame. Cycles do not move with DVFS;
the paired gain per block is (baseline - candidate) / baseline.
"""
import json
import re
import statistics
import sys

PERIOD = re.compile(r'\s(\d+\.\d+): gpu_work_period: gpu_id=(\d+) uid=(\d+) start_time_ns=(\d+) '
                    r'end_time_ns=(\d+) total_active_duration_ns=(\d+)')
FREQ = re.compile(r'\s(\d+\.\d+): gpu_frequency: state=(\d+) gpu_id=0')


def load_trace(path, uid):
    periods, freqs = [], []
    for line in open(path, errors='replace'):
        m = PERIOD.search(line)
        if m and m.group(2) == '0' and (uid is None or m.group(3) == uid):
            periods.append((int(m.group(4)), int(m.group(5)), int(m.group(6)), m.group(3)))
            continue
        m = FREQ.search(line)
        if m:
            freqs.append((int(float(m.group(1)) * 1e9), int(m.group(2)) * 1000))
    freqs.sort()
    return periods, freqs


def freq_at(freqs, t):
    f = freqs[0][1] if freqs else 0
    for when, hz in freqs:
        if when > t:
            break
        f = hz
    return f


def window_cost(periods, freqs, start, end):
    active = cycles = 0.0
    for s, e, a, _ in periods:
        overlap = min(e, end) - max(s, start)
        if overlap <= 0 or e <= s:
            continue
        share = a * overlap / (e - s)
        active += share
        cycles += share * 1e-9 * freq_at(freqs, (s + e) // 2)
    return active, cycles


def main():
    report = json.load(open(sys.argv[1]))
    uid = sys.argv[3] if len(sys.argv) > 3 else None
    periods, freqs = load_trace(sys.argv[2], uid)
    if uid is None and periods:
        counts = {}
        for p in periods:
            counts[p[3]] = counts.get(p[3], 0) + 1
        uid = max(counts, key=counts.get)
        periods = [p for p in periods if p[3] == uid]
    copies = report['copies']
    print(f'uid {uid}, {len(periods)} work periods, {len(freqs)} clock changes')
    print(f'{"case":20} {"base us/layer":>13} {"cand us/layer":>13} {"gain %":>7} '
          f'{"base Mcyc":>9} {"cand Mcyc":>9} {"gain %":>7}  block cycle gains %')
    for name, row in report['cases'].items():
        layer = {}
        for w in row.get('windows', []):
            a, c = window_cost(periods, freqs, w['start_us'] * 1000, w['end_us'] * 1000)
            layer.setdefault((w['block'], w['variant']), {})[w['copies']] = (
                a / w['frames'], c / w['frames'])
        per = {'baseline': ([], []), 'candidate': ([], [])}
        gains_t, gains_c = [], []
        blocks = sorted({b for b, _ in layer})
        for b in blocks:
            got = {}
            for v in ('baseline', 'candidate'):
                pair = layer.get((b, v), {})
                if 1 not in pair or copies not in pair:
                    continue
                t = (pair[copies][0] - pair[1][0]) / (copies - 1)
                c = (pair[copies][1] - pair[1][1]) / (copies - 1)
                per[v][0].append(t)
                per[v][1].append(c)
                got[v] = (t, c)
            if len(got) == 2 and got['baseline'][0] > 0 and got['baseline'][1] > 0:
                gains_t.append((got['baseline'][0] - got['candidate'][0]) / got['baseline'][0] * 100)
                gains_c.append((got['baseline'][1] - got['candidate'][1]) / got['baseline'][1] * 100)
        if not gains_t:
            print(f'{name:20} no windows')
            continue
        med = statistics.median
        print(f'{name:20} {med(per["baseline"][0]) / 1e3:13.1f} {med(per["candidate"][0]) / 1e3:13.1f} '
              f'{med(gains_t):7.1f} {med(per["baseline"][1]) / 1e6:9.3f} '
              f'{med(per["candidate"][1]) / 1e6:9.3f} {med(gains_c):7.1f}  '
              + ' '.join(f'{g:.0f}' for g in gains_c))


main()
