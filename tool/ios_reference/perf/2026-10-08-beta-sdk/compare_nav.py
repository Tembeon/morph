import hashlib
import json
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

parser = argparse.ArgumentParser(description='Compare deterministic SDK phases')
parser.add_argument('root', type=Path)
parser.add_argument('--baseline', default='stable-nav-1')
parser.add_argument('--candidate', default='beta-nav-1')
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
root = args.root
rows = []
for tier in ['flat', 'liquid']:
    for motion in ['enter', 'nested-push', 'nested-pop', 'toolbar']:
        for frame in [0, 1, 4, 10, 20, 34, 48]:
            name = f'nav-navigation-{motion}-{tier}-f{frame}.png'
            a_path = root / (args.baseline + '.artifacts') / name
            b_path = root / (args.candidate + '.artifacts') / name
            a = np.asarray(Image.open(a_path)).astype(np.int16)
            b = np.asarray(Image.open(b_path)).astype(np.int16)
            if a.shape != b.shape:
                raise ValueError(f'Shape mismatch: {name}')
            delta = np.abs(a - b)
            pixels = delta.max(axis=2)
            chrome = np.concatenate([pixels[:230], pixels[-230:]])
            rows.append({
                'name': name, 'tier': tier, 'motion': motion, 'frame': frame,
                'max_channel': int(pixels.max()),
                'mean_abs_channel': float(delta.mean()),
                'changed_pixels': int(np.count_nonzero(pixels)),
                'over6_pixels': int(np.count_nonzero(pixels > 6)),
                'chrome_max': int(chrome.max()),
                'chrome_over6': int(np.count_nonzero(chrome > 6)),
                'stable_sha256': hashlib.sha256(a_path.read_bytes()).hexdigest(),
                'beta_sha256': hashlib.sha256(b_path.read_bytes()).hexdigest(),
            })
args.out.write_text(
    json.dumps(rows, indent=2) + '\n',
)
for tier in ['flat', 'liquid']:
    selected = [r for r in rows if r['tier'] == tier]
    print(tier, 'max', max(r['max_channel'] for r in selected),
          'chrome max', max(r['chrome_max'] for r in selected),
          'over6', sum(r['over6_pixels'] for r in selected))
