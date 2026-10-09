#!/usr/bin/env python3
"""Attribute sampled raster CPU stacks using symbols from the exact engine."""

import argparse
import bisect
import collections
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess

PKG = 'dev.tembeon.morph_example'


def walk_stack(site, sites, frames):
    """Return leaf-to-root frames, rejecting corrupt or cyclic callsites."""
    result = []
    seen = set()
    while site is not None:
        if site in seen:
            raise ValueError('Cyclic native callstack')
        seen.add(site)
        current = sites[site]
        result.append(frames[current['frame_id']])
        site = current['parent_id']
    return result


def in_phases(samples, intervals):
    """Select a sample once from non-overlapping half-open frame phases."""
    intervals = sorted(intervals)
    for index, (start, end) in enumerate(intervals):
        if end <= start or (index and start < intervals[index - 1][1]):
            raise ValueError('Invalid or overlapping raster intervals')
    starts = [start for start, _ in intervals]
    selected = []
    for sample in samples:
        index = bisect.bisect_right(starts, sample['ts']) - 1
        if index >= 0 and sample['ts'] < intervals[index][1]:
            selected.append(sample)
    return selected


def summarize(samples, sites, frames, mappings, engine_id):
    """Keep leaf and inclusive counts separate; neither measures GPU time."""
    leaf = collections.Counter()
    inclusive = collections.Counter()
    modules = collections.Counter()
    nearest_engine = collections.Counter()
    for sample in samples:
        stack = walk_stack(sample['callsite_id'], sites, frames)
        if not stack:
            modules['no stack'] += 1
            continue
        modules[mappings[stack[0]['mapping']]['name']] += 1
        leaf[stack[0]['resolved_name']] += 1
        for name in {frame['resolved_name'] for frame in stack}:
            inclusive[name] += 1
        parent = next((frame['resolved_name'] for frame in stack
                       if frame['mapping'] == engine_id), 'no engine caller')
        nearest_engine[parent] += 1
    return {
        'samples': len(samples),
        'unwind_errors': dict(collections.Counter(
            sample['unwind_error'] or 'none' for sample in samples)),
        'leaf_functions': leaf.most_common(),
        'inclusive_functions': inclusive.most_common(),
        'nearest_engine_functions': nearest_engine.most_common(),
        'leaf_modules': modules.most_common(),
    }


def analyze(trace, report, symbols, llvm_bin):
    from perfetto.trace_processor import TraceProcessor

    with TraceProcessor(trace=str(trace)) as processor:
        query = lambda sql: [vars(row) for row in processor.query(sql)]
        errors = query("SELECT name,value FROM stats WHERE severity IN ('error','data_loss') AND value>0")
        if errors:
            raise ValueError(f'Trace errors/data loss: {errors}')
        process = query(f"SELECT upid,pid FROM process WHERE name='{PKG}'")
        if len(process) != 1:
            raise ValueError('Cannot identify exactly one benchmark process')
        threads = query(f"SELECT utid,tid FROM thread WHERE upid={process[0]['upid']} AND name='1.raster'")
        if len(threads) != 1:
            raise ValueError('Ambiguous application raster thread')
        utid = threads[0]['utid']
        samples = query(f'SELECT * FROM perf_sample WHERE utid={utid} ORDER BY ts')
        if not samples or not any(s['callsite_id'] is not None for s in samples):
            raise ValueError('No raster callstacks: use a profileable release APK')
        mappings = {row['id']: row for row in query('SELECT * FROM stack_profile_mapping')}
        frames = {row['id']: row for row in query('SELECT * FROM stack_profile_frame')}
        sites = {row['id']: row for row in query('SELECT * FROM stack_profile_callsite')}
        used = {frame['mapping'] for sample in samples
                for frame in walk_stack(sample['callsite_id'], sites, frames)}
        engines = [mapping for key, mapping in mappings.items()
                   if key in used and mapping['name'].endswith('!libflutter.so')]
        if len(engines) != 1:
            raise ValueError('Ambiguous sampled Flutter engine mapping')
        engine = engines[0]
        note = subprocess.check_output([str(llvm_bin / 'llvm-readelf'), '-n', str(symbols)], text=True)
        match = re.search(r'Build ID: ([0-9a-f]+)', note)
        if not match or match[1] != engine['build_id']:
            raise ValueError('Engine symbols build id mismatch')
        engine_frames = [frame for frame in frames.values() if frame['mapping'] == engine['id']]
        pcs = sorted({frame['rel_pc'] for frame in engine_frames})
        decoded = subprocess.run(
            [str(llvm_bin / 'llvm-symbolizer'), '--obj=' + str(symbols),
             '--output-style=JSON', '--inlining=false'],
            input='\n'.join(hex(pc) for pc in pcs) + '\n', text=True,
            capture_output=True, check=True)
        decoded = [json.loads(line) for line in decoded.stdout.splitlines()]
        if len(decoded) != len(pcs):
            raise ValueError('Incomplete engine symbol resolution')
        names = {pc: row['Symbol'][0]['FunctionName'] for pc, row in zip(pcs, decoded)}
        for frame in frames.values():
            name = names[frame['rel_pc']] if frame['mapping'] == engine['id'] else frame['name']
            frame['resolved_name'] = name or '0x' + format(frame['rel_pc'], 'x')
        snapshots = {}
        for row in query('SELECT snapshot_id,clock_id,clock_value FROM clock_snapshot'):
            snapshots.setdefault(row['snapshot_id'], {})[row['clock_id']] = row['clock_value']
        offsets = [snapshot[6] - snapshot[3] for snapshot in snapshots.values()
                   if 6 in snapshot and 3 in snapshot]
        if not offsets or max(offsets) - min(offsets) > 1_000_000:
            raise ValueError('Missing/unstable MONOTONIC-to-BOOTTIME clock mapping')
        offset = round(statistics.median(offsets))
        columns = report.get('frame_columns', [])
        start = columns.index('raster_start_us')
        end = columns.index('raster_finish_us')
        windows = {}
        for name in report['windows_us']:
            intervals = [(frame[start] * 1000 + offset, frame[end] * 1000 + offset)
                         for run in report[name]['runs'] for frame in run['frames']]
            selected = in_phases(samples, intervals)
            windows[name] = summarize(selected, sites, frames, mappings, engine['id'])
        return {
            'trace_sha256': hashlib.sha256(trace.read_bytes()).hexdigest(),
            'symbols_sha256': hashlib.sha256(symbols.read_bytes()).hexdigest(),
            'engine_build_id': engine['build_id'],
            'raster_thread': threads[0],
            'mono_to_trace_ns': offset,
            'all_raster': summarize(samples, sites, frames, mappings, engine['id']),
            'windows': windows,
            'limitations': [
                '100 Hz SW_CPU_CLOCK samples locate executing CPU stacks; they are not exact durations or GPU measurements.',
                'Inclusive counts overlap and must not be summed; nearest engine caller includes libc/driver work beneath it.',
                'Unwind errors are retained; missing deeper callers can bias attribution.',
                'Only the exact benchmark process and raster thread are included, not similarly named threads.',
                'Sampling and engine tracing add overhead; use separate minimal presentation runs for performance claims.',
            ],
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('report', type=Path)
    parser.add_argument('--symbols', required=True, type=Path)
    parser.add_argument('--llvm-bin', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    result = analyze(args.trace, json.loads(args.report.read_text()), args.symbols, args.llvm_bin)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    for name, window in result['windows'].items():
        print(name, window['samples'], window['unwind_errors'])
        for function, count in window['nearest_engine_functions'][:3]:
            print(f'  {count}: {function}')


if __name__ == '__main__':
    main()
