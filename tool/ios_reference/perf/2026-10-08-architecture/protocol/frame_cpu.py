#!/usr/bin/env python3
"""Match exact Flutter build/raster intervals to Android thread scheduling."""

import argparse
import bisect
import collections
import json
import math
from pathlib import Path
import re
import statistics

PKG = 'dev.tembeon.morph_example'


def intersect(a, b, start, end):
    return max(0, min(b, end) - max(a, start))


def phase_cost(rows, starts, start, end):
    """Partition a phase using traced states, never classify missing coverage."""
    if end <= start:
        raise ValueError('Nonpositive frame phase')
    states = collections.defaultdict(int)
    index = max(0, bisect.bisect_right(starts, start) - 1)
    for row in rows[index:]:
        if row['ts'] >= end:
            break
        states[row['state']] += intersect(row['ts'], row['ts'] + row['dur'], start, end)
    wall = end - start
    covered = sum(states.values())
    if covered > wall:
        raise ValueError('Overlapping thread states')
    return {
        'wall_ms': wall / 1e6,
        'running_ms': states.pop('Running', 0) / 1e6,
        'runnable_ms': (states.pop('R', 0) + states.pop('R+', 0)) / 1e6,
        'not_runnable_ms': sum(states.values()) / 1e6,
        'uncovered_ms': (wall - covered) / 1e6,
        'other_states_ms': {k: v / 1e6 for k, v in states.items() if v},
    }


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]


def audit_allocator_counters(markers, pid, errors):
    """Allow exactly the beta AllocatorVK float counters rejected by Perfetto.

    Perfetto expects an int64 C value. These counters do not open/close native
    scopes or change scheduling. Require all parse failures to be accounted
    for; any other malformed record keeps strict analysis unavailable.
    """
    count = 0
    for marker in markers:
        fields = marker.rstrip('\n\0').split('|')
        if len(fields) != 4 or fields[:3] != ['C', str(pid), 'AllocatorVK']:
            raise ValueError('Unexpected allocator marker format')
        if re.fullmatch(r'[+-]?\d+', fields[3]):
            continue
        if not re.fullmatch(r'[+-]?\d+\.\d+', fields[3]):
            raise ValueError('Unexpected allocator counter value')
        count += 1
    if count != errors:
        raise ValueError('Not every systrace parse failure is an audited float counter')
    return {'counter': 'AllocatorVK', 'ignored_float_counters': count,
            'sync_slice_parse_failures': 0}


def analyze(trace, report, scheduling_only=False, audit_float_counters=False):
    from perfetto.trace_processor import TraceProcessor, TraceProcessorConfig

    required = ['build_start_us', 'build_finish_us', 'raster_start_us', 'raster_finish_us']
    columns = report.get('frame_columns', [])
    if any(key not in columns for key in required):
        raise ValueError('Build with NAV_THREAD_PHASES=true')
    offsets = {key: columns.index(key) for key in required}
    with TraceProcessor(trace=str(trace), config=TraceProcessorConfig(
            ingest_ftrace_in_raw=audit_float_counters)) as processor:
        query = lambda sql: list(processor.query(sql))
        errors = query("SELECT name, value FROM stats WHERE severity IN ('error', 'data_loss') AND value>0")
        marker_errors = [{'name': r.name, 'value': r.value} for r in errors
                         if r.name == 'systrace_parse_failure']
        if errors and (not (scheduling_only or audit_float_counters) or len(marker_errors) != len(errors)):
            raise ValueError(f'Trace errors/data loss: {errors}')
        snapshots = {}
        for row in query('SELECT snapshot_id, clock_id, clock_value FROM clock_snapshot'):
            snapshots.setdefault(row.snapshot_id, {})[row.clock_id] = row.clock_value
        mappings = [s[6] - s[3] for s in snapshots.values() if 6 in s and 3 in s]
        if not mappings or max(mappings) - min(mappings) > 1_000_000:
            raise ValueError('Missing/unstable action clock mapping')
        mapping = round(statistics.median(mappings))
        processes = query(f"SELECT upid,pid FROM process WHERE name='{PKG}'")
        if len(processes) != 1:
            raise ValueError('Cannot identify exactly one benchmark process')
        process = processes[0]
        audit = None
        if audit_float_counters:
            markers = query(f'''SELECT a.string_value FROM ftrace_event f
                JOIN args a ON f.arg_set_id=a.arg_set_id
                WHERE f.name='print' AND a.key='buf'
                  AND a.string_value LIKE 'C|{process.pid}|AllocatorVK|%' ''')
            audit = audit_allocator_counters(
                [r.string_value for r in markers], process.pid,
                sum(r['value'] for r in marker_errors))
        threads = query(f'SELECT utid,tid,name FROM thread WHERE upid={process.upid}')
        roles = {
            'build': [t for t in threads if t.tid == process.pid],
            'raster': [t for t in threads if t.name == '1.raster'],
        }
        if any(len(ts) != 1 for ts in roles.values()):
            raise ValueError('Ambiguous UI or raster thread')
        data = {}
        for role, ts in roles.items():
            utid = ts[0].utid
            rows = [{'ts': r.ts, 'dur': r.dur, 'state': r.state}
                    for r in query(f'SELECT ts,dur,state FROM thread_state WHERE utid={utid} AND dur>0 ORDER BY ts')]
            if not rows:
                raise ValueError(f'Missing scheduling states for {role}')
            slices = [] if scheduling_only else [{'ts': r.ts, 'dur': r.dur, 'name': r.name, 'depth': r.depth}
                      for r in query(f'''SELECT s.ts,s.dur,s.name,s.depth FROM slice s
                          JOIN thread_track t ON s.track_id=t.id
                          WHERE t.utid={utid} AND s.dur>0 ORDER BY s.ts''')]
            data[role] = (rows, [r['ts'] for r in rows], slices)
        cases = {}
        for name in report['windows_us']:
            runs = []
            for run in report[name]['runs']:
                stages = {}
                for role in roles:
                    rows, starts, slices = data[role]
                    frames = []
                    for index, frame in enumerate(run['frames']):
                        a = frame[offsets[role + '_start_us']] * 1000 + mapping
                        b = frame[offsets[role + '_finish_us']] * 1000 + mapping
                        cost = phase_cost(rows, starts, a, b)
                        if cost['uncovered_ms'] > 0.1:
                            raise ValueError(f'Incomplete phase coverage: {name}/{role}/{index}')
                        expected = frame[1 if role == 'build' else 2] / 1000
                        if abs(cost['wall_ms'] - expected) > 0.002:
                            raise ValueError('Phase timestamp/duration mismatch')
                        cost.update({'frame': index, 'start_ns': a, 'end_ns': b})
                        frames.append(cost)
                    slowest = sorted(frames, key=lambda f: f['wall_ms'], reverse=True)[:5]
                    for frame in slowest:
                        a, b = frame['start_ns'], frame['end_ns']
                        inside = [s for s in slices if a <= s['ts'] and s['ts'] + s['dur'] <= b]
                        frame['largest_slices'] = [
                            {'name': s['name'], 'depth': s['depth'],
                             **phase_cost(rows, starts, s['ts'], s['ts'] + s['dur'])}
                            for s in sorted(inside, key=lambda s: s['dur'], reverse=True)[:15]
                        ]
                    stages[role] = {
                        'p95': {key: percentile([f[key] for f in frames], .95) for key in
                                ['wall_ms', 'running_ms', 'runnable_ms', 'not_runnable_ms']},
                        'total': {key: sum(f[key] for f in frames) for key in
                                  ['wall_ms', 'running_ms', 'runnable_ms', 'not_runnable_ms']},
                        'slowest': slowest,
                        'frames': frames,
                    }
                runs.append(stages)
            cases[name] = runs
        return {
            'mono_to_trace_ns': mapping,
            'threads': {role: {'utid': ts[0].utid, 'tid': ts[0].tid, 'name': ts[0].name}
                        for role, ts in roles.items()},
            'slice_counts': {role: len(values[2]) for role, values in data.items()},
            'scheduling_only': scheduling_only,
            'excluded_marker_parse_errors': marker_errors,
            'marker_audit': audit,
            'cases': cases,
            'limitations': [
                'Running measures scheduled CPU wall time, not CPU cycles or GPU execution.',
                'Runnable measures ready-to-run scheduler delay, including preemption.',
                'Not-runnable states do not identify a specific GPU fence or driver cause.',
                'Slice durations are inclusive and overlap; never sum parent and child costs.',
                'Independent marginal p95 values do not sum to a p95 frame.',
                'This diagnostic trace has more instrumentation than clean timing runs.',
                'Scheduling-only mode excludes all engine slices; marker errors are reported, never silently treated as complete engine coverage.',
                'An explicit float-counter audit permits native slices only if every parse failure is the known non-scope AllocatorVK counter format.',
            ],
        }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('report', type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--scheduling-only', action='store_true',
                        help='Exclude every marker slice; tolerate only reported systrace marker parse errors')
    parser.add_argument('--audit-float-counters', action='store_true',
                        help='Require every marker parse failure to match the beta AllocatorVK float-counter bug')
    args = parser.parse_args()
    result = analyze(args.trace, json.loads(args.report.read_text()), args.scheduling_only, args.audit_float_counters)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    for name, runs in result['cases'].items():
        print(name, {role: {key: round(statistics.median(r[role]['p95'][key] for r in runs), 3)
                           for key in runs[0][role]['p95']} for role in ['build', 'raster']})
