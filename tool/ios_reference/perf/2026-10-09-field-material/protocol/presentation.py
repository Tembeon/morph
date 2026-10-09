#!/usr/bin/env python3
"""Inspect actual Impeller buffer presentation, independently of FrameTiming."""

import argparse
import collections
import json
from pathlib import Path
import statistics

PKG = 'dev.tembeon.morph_example'


def cadence(frames, period_ns):
    """Count unique display presentations; preserve merged/dropped buffers."""
    presented = sorted({f['present_ns'] for f in frames if f['present_ns'] is not None})
    gaps = [b - a for a, b in zip(presented, presented[1:])]
    return {
        'buffers': len(frames),
        'unique_presentations': len(presented),
        'present_type': dict(collections.Counter(f['present_type'] for f in frames)),
        'jank_type': dict(collections.Counter(f['jank_type'] for f in frames)),
        'unmapped_display_buffers': sum(f['present_ns'] is None for f in frames),
        'presentation_gaps_ms': [x / 1e6 for x in gaps],
        'missed_presentation_slots': sum(max(0, round(x / period_ns) - 1) for x in gaps),
        'longest_presentation_gap_ms': max(gaps, default=0) / 1e6,
    }


def analyze(trace, report):
    from perfetto.trace_processor import TraceProcessor

    with TraceProcessor(trace=str(trace)) as processor:
        query = lambda sql: list(processor.query(sql))
        snapshots = {}
        for row in query('select snapshot_id, clock_id, clock_value from clock_snapshot'):
            snapshots.setdefault(row.snapshot_id, {})[row.clock_id] = row.clock_value
        offsets = [s[6] - s[3] for s in snapshots.values() if 6 in s and 3 in s]
        if not offsets or max(offsets) - min(offsets) > 1_000_000:
            raise ValueError('Missing or unstable MONOTONIC-to-BOOTTIME clock mapping')
        offset = round(statistics.median(offsets))
        candidates = query(f"""select distinct upid from actual_frame_timeline_slice
                               where layer_name like 'TX - VRI-{PKG}/{PKG}.MainActivity%'
                               and upid in (select upid from actual_frame_timeline_slice
                                            where layer_name like 'TX - ImpellerSurface%')""")
        if len(candidates) != 1:
            raise ValueError('Cannot identify exactly one application Impeller surface owner')
        upid = candidates[0].upid
        layers = query(f"""select distinct layer_name from actual_frame_timeline_slice
                           where upid={upid} and layer_name like 'TX - ImpellerSurface%'""")
        if len(layers) != 1:
            raise ValueError('Multiple Impeller surfaces require explicit disambiguation')
        rows = query(f"""select a.ts, a.dur, a.display_frame_token, a.surface_frame_token,
                          a.present_type, a.jank_type, a.prediction_type,
                          d.ts + d.dur as present_ns
                          from actual_frame_timeline_slice a
                          left join actual_frame_timeline_slice d
                            on d.display_frame_token=a.display_frame_token
                            and d.layer_name is null and d.dur>=0
                          where a.upid={upid} and a.layer_name like 'TX - ImpellerSurface%'
                            and a.dur>=0
                            and extract_arg(a.arg_set_id, 'Is Buffer?')='Yes'
                          order by a.ts""")
        frames = [{k: getattr(row, k) for k in ('ts', 'dur', 'display_frame_token',
                   'surface_frame_token', 'present_type', 'jank_type', 'prediction_type',
                   'present_ns')} for row in rows]
        if not frames:
            raise ValueError('No actual buffer frames: transactions alone cannot establish presentation')
        if len({f['surface_frame_token'] for f in frames}) != len(frames):
            raise ValueError('Ambiguous display mapping or duplicate buffer tokens')
        windows = {}
        for name, bounds in report['windows_us'].items():
            runs = []
            for index, (a, b) in enumerate(bounds):
                a, b = a * 1000 + offset, b * 1000 + offset
                selected = [f for f in frames if a <= f['ts'] < b]
                if len(selected) < 4:
                    raise ValueError(f'Insufficient buffer coverage: {name}/{index}')
                runs.append({
                    'flutter_frames': report[name]['runs'][index]['n'],
                    **cadence(selected, report['budget_ms'] * 1e6),
                    'frames': selected,
                })
            windows[name] = runs
        return {
            'surface': layers[0].layer_name,
            'mono_to_trace_ns': offset,
            'windows': windows,
            'limitations': [
                'Select buffers by their traced start inside the action window; boundary frames differ from Flutter vsync selection.',
                'Cadence excludes gaps before the first and after the last mapped presentation.',
                'SurfaceFlinger jank flags and measured buffer cadence are separate observations.',
                'A faster raster stage alone does not establish improved presentation or input latency.',
            ],
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('report', type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    result = analyze(args.trace, report)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    for name, runs in result['windows'].items():
        print(name, [(r['buffers'], r['missed_presentation_slots'],
                      round(r['longest_presentation_gap_ms'], 2)) for r in runs])


if __name__ == '__main__':
    main()
