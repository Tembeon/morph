"""Attribute VM CPU samples only to the report's measured action windows."""
import argparse
import collections
import gzip
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('samples', type=Path)
parser.add_argument('report', type=Path)
parser.add_argument('--out', required=True, type=Path)
args = parser.parse_args()
raw = args.samples.read_bytes()
profile = json.loads(gzip.decompress(raw) if args.samples.suffix == '.gz' else raw)
report = json.loads(args.report.read_text())
functions = profile['functions']
result = {}
for case, windows in report['windows_us'].items():
    selected = [sample for sample in profile['samples']
                if any(a <= sample['timestamp'] < b for a, b in windows)]
    inclusive = collections.Counter()
    leaf = collections.Counter()
    for sample in selected:
        inclusive.update(set(sample['stack']))
        if sample['stack']:
            leaf[sample['stack'][0]] += 1
    def describe(index, count):
        function = functions[index]['function']
        return {'name': function['name'],
                'owner': function.get('owner', {}).get('name'),
                'url': functions[index].get('resolvedUrl'),
                'samples': count,
                'percent': round(count / max(1, len(selected)) * 100, 1)}
    result[case] = {'samples': len(selected),
                    'inclusive': [describe(i, n) for i, n in inclusive.most_common()],
                    'leaf': [describe(i, n) for i, n in leaf.most_common()]}
args.out.write_text(json.dumps(result, indent=2) + '\n')
