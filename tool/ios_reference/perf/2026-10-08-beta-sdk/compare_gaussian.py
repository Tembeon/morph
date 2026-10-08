import hashlib
import json
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

parser = argparse.ArgumentParser(description='Compare native Gaussian phases')
parser.add_argument('directory', type=Path)
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
directory = args.directory
rows = []
for layout in ['single', 'large']:
    for baseline, candidate in [('blur', 'exact'), ('blur', 'paired'),
                                ('exact', 'paired')]:
        for phase in [-1.0, 0.0, 1.0]:
            prefix = f'{layout}-background-independent-'
            suffix = f'-s2.0-p{phase}.png'
            a_path = directory / (prefix + baseline + suffix)
            b_path = directory / (prefix + candidate + suffix)
            a = np.asarray(Image.open(a_path)).astype(np.int16)
            b = np.asarray(Image.open(b_path)).astype(np.int16)
            delta = np.abs(a - b)
            pixels = delta.max(axis=2)
            rows.append({
                'layout': layout, 'phase': phase, 'baseline': baseline,
                'candidate': candidate, 'max_channel': int(pixels.max()),
                'mean_abs_channel': float(delta.mean()),
                'over6_pixels': int(np.count_nonzero(pixels > 6)),
                'baseline_sha256': hashlib.sha256(a_path.read_bytes()).hexdigest(),
                'candidate_sha256': hashlib.sha256(b_path.read_bytes()).hexdigest(),
            })
args.out.write_text(json.dumps(rows, indent=2) + '\n')
for baseline, candidate in [('blur', 'exact'), ('blur', 'paired'), ('exact', 'paired')]:
    pair = [r for r in rows if r['baseline'] == baseline and r['candidate'] == candidate]
    print(baseline, candidate, 'max', max(r['max_channel'] for r in pair),
          'over6 pixels', sum(r['over6_pixels'] for r in pair))
