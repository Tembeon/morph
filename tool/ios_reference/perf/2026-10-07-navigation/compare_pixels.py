"""Compare every requested action phase, including repeated stock references."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
parser.add_argument('--candidate', required=True)
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
rows = []
for motion in ['enter', 'nested-push', 'nested-pop', 'toolbar']:
    for frame in [0, 1, 4, 10, 20, 34, 48]:
        stock = args.directory / f'nav-navigation-{motion}-liquid-f{frame}.png'
        for mode in [args.candidate, 'liquid-ref']:
            candidate = args.directory / f'nav-navigation-{motion}-{mode}-f{frame}.png'
            if mode == 'liquid-ref' and not candidate.exists():
                continue
            a = np.array(Image.open(stock)).astype(np.int16)
            b = np.array(Image.open(candidate)).astype(np.int16)
            if a.shape != b.shape:
                raise ValueError(f'Different image dimensions: {candidate}')
            delta = np.abs(a - b)
            pixels = delta.max(axis=2)
            y, x = np.where(pixels > 0)
            rows.append({
                'motion': motion, 'frame': frame, 'mode': mode,
                'max_channel': int(delta.max()),
                'mean_channel': float(delta.mean()),
                'changed_pixels': int(np.count_nonzero(pixels)),
                'over6_pixels': int(np.count_nonzero(pixels > 6)),
                'changed_coordinates': [[int(px), int(py)] for px, py in zip(x, y)]
                    if len(x) <= 100 else None,
                'stock_sha256': hashlib.sha256(stock.read_bytes()).hexdigest(),
                'candidate_sha256': hashlib.sha256(candidate.read_bytes()).hexdigest(),
            })
args.out.parent.mkdir(parents=True, exist_ok=True)
args.out.write_text(json.dumps(rows, indent=2) + '\n')
for mode in {r['mode'] for r in rows}:
    selected = [r for r in rows if r['mode'] == mode]
    print(mode, 'pairs', len(selected), 'max', max(r['max_channel'] for r in selected),
          'changed_pixels', sum(r['changed_pixels'] for r in selected))
