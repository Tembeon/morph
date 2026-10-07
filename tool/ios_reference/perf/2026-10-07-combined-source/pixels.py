#!/usr/bin/env python3
"""Compare only declared combined-source cases and current-frame phases."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('report', type=Path)
parser.add_argument('artifacts', type=Path)
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
report = json.loads(args.report.read_text())
results = []
hashes = {}
dpr = report['device_pixel_ratio']
for name, metadata in report['case_metadata'].items():
    if metadata['mode'] not in ('mix-gaussian', 'mix-dual'):
        continue
    baseline = name.replace(metadata['mode'], 'mix-native')
    if baseline not in report['case_metadata']:
        raise ValueError('Missing baseline ' + baseline)
    for phase in report['shot_phases']:
        paths = [args.artifacts / f'{case}-p{phase}.png' for case in (baseline, name)]
        for p in paths:
            hashes[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
        a, b = [np.array(Image.open(p).convert('RGBA')).astype(np.int16) for p in paths]
        if a.shape != b.shape:
            raise ValueError('Different image sizes')
        error = np.abs(a - b)
        y, x = np.mgrid[:a.shape[0], :a.shape[1]]
        inside = np.zeros(a.shape[:2], dtype=bool)
        face = np.zeros_like(inside)
        for left, top, width, height in metadata['visible_rects_logical']:
            cx, cy = (left + width / 2) * dpr, (top + height / 2) * dpr
            radius = 18 * dpr
            qx = np.abs(x + .5 - cx) - (width * dpr / 2 - radius)
            qy = np.abs(y + .5 - cy) - (height * dpr / 2 - radius)
            distance = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - radius
            inside |= distance <= 0
            face |= distance <= -10 * dpr
        peak = error.max(axis=2)
        row = {'case': name, 'phase': phase, 'max_channel_error': int(error.max()),
               'mean_channel_error': float(error.mean()), 'changed_pixels': int(np.count_nonzero(peak)),
               'pixels_above_4': int(np.count_nonzero(peak > 4)),
               'pixels_above_8': int(np.count_nonzero(peak > 8))}
        for label, mask in [('face', face), ('rim', inside & ~face), ('outside', ~inside)]:
            row[label] = {'max': int(error[mask].max()), 'mean': float(error[mask].mean()),
                          'pixels': int(mask.sum()), 'changed': int(np.count_nonzero(peak[mask]))}
        results.append(row)
args.out.mkdir(parents=True, exist_ok=True)
(args.out / 'pixels.json').write_text(json.dumps(results, indent=2) + '\n')
(args.out / 'png-sha256.json').write_text(json.dumps(hashes, indent=2) + '\n')
for mode in ('mix-gaussian', 'mix-dual'):
    rows = [r for r in results if mode in r['case']]
    if not rows:
        continue
    print(mode, 'comparisons', len(rows), 'max', max(r['max_channel_error'] for r in rows),
          'face', max(r['face']['max'] for r in rows), 'rim', max(r['rim']['max'] for r in rows),
          'outside', max(r['outside']['max'] for r in rows))
