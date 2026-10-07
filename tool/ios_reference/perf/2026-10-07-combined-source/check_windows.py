"""Validate cache counters and source freshness from native windows."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('reports', nargs='+', type=Path)
args = parser.parse_args()
for path in args.reports:
    r = json.loads(path.read_text())
    for name, windows in r['owned_source_windows'].items():
        meta = r['case_metadata'][name]
        for run, counter in zip(r[name]['runs'], windows):
            mode = meta['mode']
            if mode in ('mix-native','mix-bare'):
                assert counter['roi_captures'] == counter['blur_passes'] == counter['cache_hits'] == 0, name
                continue
            assert counter['source_version'] == counter['blur_version'], name
            assert counter['unavailable_immediate_gpu_textures'] == 0, name
            if meta['motion'] == 'background':
                assert counter['roi_captures'] == counter['recordings'] == counter['blur_passes'] == 0, name
                assert abs(counter['cache_hits'] - run['n']) <= 2, name
            elif meta['motion'] == 'dynamic':
                assert counter['cache_hits'] == 0, name
                assert abs(counter['roi_captures'] - run['n']) <= 2, name
            else:
                assert counter['roi_captures'] > 0 and counter['cache_hits'] > 0, name
            assert abs(counter['roi_captures'] + counter['cache_hits'] - run['n']) <= 2, name
    print(path.name, 'source freshness and cache windows verified')
