#!/usr/bin/env python3
"""Reduce standalone stage reports and optional existing GPU-work traces."""

import argparse
import bisect
import csv
import gzip
import json
import re
import statistics
from pathlib import Path

PERIOD = re.compile(
    r'\s(\d+\.\d+): gpu_work_period: gpu_id=(\d+) uid=(\d+) '
    r'start_time_ns=(\d+) end_time_ns=(\d+) total_active_duration_ns=(\d+)')
FREQ = re.compile(r'\s(\d+\.\d+): gpu_frequency: state=(\d+) gpu_id=0')


def load_gpu(base):
    device = Path(str(base) + '.device.txt')
    trace = Path(str(base) + '.gpuwork.txt')
    if not trace.exists():
        trace = Path(str(trace) + '.gz')
        if not trace.exists():
            return None
    if not device.exists():
        raise ValueError('GPU trace requires device notes with the app UID')
    match = re.search(r'package:dev\.tembeon\.morph_example\s+uid:(\d+)', device.read_text())
    if not match:
        raise ValueError('Cannot attribute GPU trace without the exact app UID')
    uid = int(match[1])
    periods, freqs = [], []
    contents = gzip.decompress(trace.read_bytes()).decode(errors='replace') if trace.suffix == '.gz' else trace.read_text(errors='replace')
    for line in contents.splitlines():
        if 'LOST' in line or 'entries-in-buffer/entries-written' in line:
            raise ValueError('GPU trace reports lost events or was not streamed')
        p = PERIOD.search(line)
        if p and int(p[2]) == 0 and int(p[3]) == uid:
            start, end, active = map(int, p.group(4, 5, 6))
            if end <= start or active < 0 or active > end - start:
                raise ValueError('Invalid GPU work period')
            periods.append((start, end, active))
        f = FREQ.search(line)
        if f:
            freqs.append((round(float(f[1]) * 1e9), int(f[2]) * 1000))
    if not periods:
        raise ValueError('No GPU work periods attributed to the app')
    return periods, sorted(freqs)


def gpu_cost(periods, freqs, start, end):
    """Prorate work-period activity; integrate every frequency transition."""
    active = cycles = unknown = 0.0
    event_count = 0
    times = [t for t, _ in freqs]
    for a, b, work in periods:
        lo, hi = max(a, start), min(b, end)
        if hi <= lo:
            continue
        event_count += 1
        density = work / (b - a)
        active += (hi - lo) * density
        index = bisect.bisect_right(times, lo) - 1
        cursor = lo
        while cursor < hi:
            boundary = min(hi, times[index + 1] if index + 1 < len(times) else hi)
            portion = (boundary - cursor) * density
            if index < 0:
                unknown += portion
            else:
                cycles += portion / 1e9 * freqs[index][1]
            cursor = boundary
            index += 1
    return active, None if unknown else cycles, event_count


def reduce_report(path):
    report = json.loads(path.read_text())
    if report.get('schema') != 'morph-stage-bench-v1' or not report.get('liquid_available'):
        raise ValueError('Expected a successful native liquid stage benchmark')
    gpu = load_gpu(path.with_suffix(''))
    rows = []
    for name, metadata in report['case_metadata'].items():
        runs = report[name]['runs']
        windows = report['windows_us'][name]
        if len(runs) != report['runs'] or len(runs) != len(windows):
            raise ValueError(f'Incomplete repeats: {name}')
        per_run = []
        for run, (start, end) in zip(runs, windows):
            frames = run['frames']
            if end <= start or len(frames) != run['n'] or run['n'] < 4:
                raise ValueError(f'Invalid frame/window coverage: {name}')
            if any(not start <= f[0] < end for f in frames):
                raise ValueError(f'Timing outside measured window: {name}')
            if any(b[0] <= a[0] for a, b in zip(frames, frames[1:])):
                raise ValueError(f'Unordered or duplicate frame timestamps: {name}')
            gaps = [max(0, round((b[0] - a[0]) / (report['budget_ms'] * 1000)) - 1)
                    for a, b in zip(frames, frames[1:])]
            row = {k: run[k] for k in ('n', 'build_mean', 'raster_mean', 'build_p50', 'raster_p50', 'build_p95',
                                      'raster_p95', 'build_p99', 'raster_p99', 'over_budget')}
            row['vsync_gap_slots'] = sum(gaps)
            row['gpu_ms'] = row['gpu_mcycles'] = None
            if gpu:
                active, cycles, events = gpu_cost(*gpu, start * 1000, end * 1000)
                if not events or active <= 0:
                    raise ValueError(f'No GPU coverage for {name}; reject trace')
                row['gpu_ms'] = active / run['n'] / 1e6
                row['gpu_mcycles'] = None if cycles is None else cycles / run['n'] / 1e6
            per_run.append(row)
        median = {k: (statistics.median([r[k] for r in per_run])
                      if all(r[k] is not None for r in per_run) else None)
                  for k in per_run[0]}
        rects = metadata.get('visible_rects_logical', [])
        area = sum(r[2] * r[3] for r in rects)
        union = ((max(r[0] + r[2] for r in rects) - min(r[0] for r in rects)) *
                 (max(r[1] + r[3] for r in rects) - min(r[1] for r in rects))) if rects else 0
        dpr = report.get('device_pixel_ratio', 1)
        rows.append({'case': name, **metadata, **median, 'runs': per_run,
                     'visible_mpix': area * dpr * dpr / 1e6,
                     'union_to_visible_area': union / area if area else None,
                     'liquid_filter_output_mpix': sum(r[2] * r[3] for r in metadata.get(
                         'liquid_filter_rects_logical', [])) * dpr * dpr / 1e6})
    deltas = []
    for row in rows:
        source_mode = {'capture': 'bare', 'blur': 'capture', 'optics': 'capture', 'glass': 'optics'}.get(row['mode'])
        if not source_mode:
            continue
        source = next((r for r in rows if r['layout'] == row['layout'] and
                       r['motion'] == row['motion'] and r['plan'] == row['plan'] and
                       r['mode'] == source_mode), None)
        if source is None:
            continue
        metrics = ('build_mean', 'raster_mean', 'gpu_ms', 'gpu_mcycles')
        differences = [{f'delta_{k}': None if a[k] is None or b[k] is None else a[k] - b[k]
                        for k in metrics} for a, b in zip(row['runs'], source['runs'])]
        deltas.append({
            'case': row['case'], 'minus': source['case'],
            'interpretation': {
                'capture': 'capture/composition proxy',
                'blur': 'Gaussian/filter topology proxy',
                'optics': 'matte + optics + production composition proxy',
                'glass': 'blur added to production optics proxy',
            }[row['mode']],
            'paired_run_differences': differences,
            **{k: statistics.median([d[k] for d in differences])
               if all(d[k] is not None for d in differences) else None for k in differences[0]},
        })
    return {
        'report': str(path), 'rows': rows, 'deltas': deltas,
        'limitations': [
            'Stage differences change topology and are not exact engine attribution.',
            'Raster duration is not GPU time; GPU work periods are active work, not presentation latency.',
            'GPU activity is prorated uniformly within each kernel work-period event.',
            'Missing frequency coverage produces null cycles, never an extrapolated frequency.',
            'Vsync gaps are inferred scheduling slots, not measured Android presentation jank.',
            'Layer bounds/counts do not measure transient GPU memory or native pass count.',
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reports', nargs='+', type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    results = [reduce_report(path) for path in args.reports]
    (args.out / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
    columns = ['report', 'case', 'layout', 'motion', 'content', 'mode', 'plan', 'requested_sigma_logical', 'n',
               'build_p50', 'raster_p50', 'build_mean', 'raster_mean',
               'build_p95', 'raster_p95', 'build_p99', 'raster_p99', 'over_budget',
               'vsync_gap_slots', 'gpu_ms', 'gpu_mcycles', 'backdrop_layers', 'distinct_capture_keys',
               'visible_mpix', 'union_to_visible_area', 'liquid_filter_output_mpix']
    with (args.out / 'cases.csv').open('w', newline='') as out:
        writer = csv.DictWriter(out, fieldnames=columns)
        writer.writeheader()
        for result in results:
            for row in result['rows']:
                writer.writerow({k: result['report'] if k == 'report' else row.get(k) for k in columns})
                gpu = 'unavailable' if row['gpu_ms'] is None else f"{row['gpu_ms']:.3f} ms"
                print(f"{row['case']}: UI p95 {row['build_p95']:.2f}, raster p95 {row['raster_p95']:.2f}, GPU {gpu}")


if __name__ == '__main__':
    main()
