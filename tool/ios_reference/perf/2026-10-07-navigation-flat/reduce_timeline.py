"""Reduce complete named timeline slices inside exact benchmark windows."""
import argparse
from collections import defaultdict
import gzip
import json
import statistics
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('timeline', type=Path)
parser.add_argument('report', type=Path)
parser.add_argument('--out', required=True, type=Path)
args = parser.parse_args()
raw = args.timeline.read_bytes()
data = json.loads(gzip.decompress(raw) if args.timeline.suffix == '.gz' else raw)
report = json.loads(args.report.read_text())
stacks = defaultdict(list)
slices = []
mismatches = 0
for event in data['traceEvents']:
    if event.get('ph') == 'B':
        stacks[(event['pid'], event['tid'])].append(event)
    elif event.get('ph') == 'E':
        stack = stacks[(event['pid'], event['tid'])]
        if not stack:
            continue
        begin = stack.pop()
        if begin['name'] != event.get('name'):
            mismatches += 1
            stack.clear()
            continue
        slices.append((begin['ts'], event['ts'], begin['name']))
    elif event.get('ph') == 'X':
        slices.append((event['ts'], event['ts'] + event['dur'], event['name']))

result = {'stack_mismatches': mismatches, 'cases': {}}
for case, windows in report['windows_us'].items():
    selected = defaultdict(list)
    coverage = []
    for start, end in windows:
        count = 0
        for begin, finish, name in slices:
            if start <= begin <= finish <= end:
                selected[name].append((finish - begin) / 1000)
                if name == 'GPURasterizer::Draw':
                    count += 1
        coverage.append(count)
    result['cases'][case] = {
        'complete_raster_slices_per_window': coverage,
        'events': {
            name: {
                'count': len(values),
                'total_ms': sum(values),
                'mean_ms': statistics.mean(values),
                'max_ms': max(values),
            }
            for name, values in sorted(selected.items())
        },
    }
args.out.write_text(json.dumps(result, indent=2) + '\n')
