#!/usr/bin/env python3
"""Read sustained Navigation windows with the existing ODPM/sched reducer."""

import argparse
import importlib.util
import json
from pathlib import Path
import statistics

from perfetto.trace_processor import TraceProcessor


def analyze(trace, report_path):
    report = json.loads(report_path.read_text())
    if report.get('schema') != 'morph-stage-bench-v1':
        raise ValueError('Expected native stage report')
    if not report.get('liquid_available'):
        raise ValueError('Liquid renderer unavailable')
    processor = TraceProcessor(trace=str(trace))
    try:
        snapshots = {}
        for row in processor.query('SELECT snapshot_id, clock_id, clock_value FROM clock_snapshot'):
            snapshots.setdefault(row.snapshot_id, {})[row.clock_id] = row.clock_value
        offsets = [s[6] - s[3] for s in snapshots.values() if 6 in s and 3 in s]
        if not offsets or max(offsets) - min(offsets) > 1_000_000:
            raise ValueError('Missing or unstable action/trace clock mapping')
        mapping = statistics.median(offsets)
        rails = list(processor.query("""
            SELECT t.name, MIN(c.ts) AS first, MAX(c.ts) AS last, COUNT(*) AS n
            FROM counter c JOIN counter_track t ON c.track_id = t.id
            WHERE t.name LIKE 'power.%rails%' GROUP BY t.id
        """))
        if not rails:
            raise ValueError('No ODPM rail samples')
        for name, windows in report['windows_us'].items():
            if len(windows) != report['runs']:
                raise ValueError(f'Incomplete windows: {name}')
            for a, b in windows:
                if b - a < 10_000_000:
                    raise ValueError('Use sustained windows, not short transitions')
                if any(r.n < 2 or r.first > a * 1000 + mapping or
                       r.last < b * 1000 + mapping for r in rails):
                    raise ValueError(f'Rail samples do not bracket {name}')
        lost = list(processor.query("""
            SELECT name, value FROM stats
            WHERE severity IN ('error', 'data_loss') AND value > 0
        """))
        if lost:
            raise ValueError(f'Trace reports errors/data loss: {lost}')
    finally:
        processor.close()
    path = Path(__file__).resolve().parent.parent / 'energy.py'
    spec = importlib.util.spec_from_file_location('morph_existing_energy', path)
    reducer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reducer)
    rows, metadata = reducer.analyze(str(trace), report)
    if not metadata['threads'].get('ui') or not metadata['threads'].get('raster'):
        raise ValueError('Missing exact app UI/raster thread attribution')
    output = {}
    for name, windows in rows.items():
        if len(windows) != report['runs']:
            raise ValueError(f'Missing energy repeats: {name}')
        for index, window in enumerate(windows):
            window['power_mw'] = window['total_mj'] / window['s']
            window['energy_mj_per_cycle'] = window['total_mj'] / report['workflow_cycles']
            timing = report[name]['runs'][index]
            window['frames'] = timing['n']
            window['build_p95'] = timing['build_p95']
            window['raster_p95'] = timing['raster_p95']
            window['over_budget'] = timing['over_budget']
        output[name] = {
            'median': {key: statistics.median(w[key] for w in windows) for key in
                       ['power_mw', 'energy_mj_per_cycle', 'build_p95', 'raster_p95', 'over_budget']},
            'windows': windows,
        }
    return {
        'report': str(report_path), 'metadata': metadata, 'cases': output,
        'limitations': [
            'Power rails measure the whole phone, not app-attributed energy.',
            'Rail counter endpoints are linearly interpolated inside measured coverage.',
            'FrameTiming over-budget counts are not actual presentation misses.',
            'Callback-driven interactions omit physical-touch input boosts.',
        ],
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('report', type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    result = analyze(args.trace, args.report)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    for name, values in result['cases'].items():
        print(name, values['median'])
