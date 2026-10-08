"""Compare deterministic Navigation phases without discarding body noise."""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


def compare(directory, baseline, candidate):
    rows = []
    for motion in ['enter', 'nested-push', 'nested-pop', 'toolbar']:
        for frame in [0, 1, 4, 10, 20, 34, 48]:
            a_path = directory / f'nav-navigation-{motion}-{baseline}-f{frame}.png'
            b_path = directory / f'nav-navigation-{motion}-{candidate}-f{frame}.png'
            a = np.asarray(Image.open(a_path)).astype(np.int16)
            b = np.asarray(Image.open(b_path)).astype(np.int16)
            if a.shape != b.shape:
                raise ValueError(f'Different image dimensions: {b_path}')
            pixels = np.abs(a - b).max(axis=2)
            chrome = np.concatenate((pixels[:230], pixels[-230:]))
            ys, xs = np.where(pixels == pixels.max())
            rows.append({
                'motion': motion, 'frame': frame,
                'baseline': baseline, 'candidate': candidate,
                'max_channel': int(pixels.max()),
                'changed_pixels': int(np.count_nonzero(pixels)),
                'over6_pixels': int(np.count_nonzero(pixels > 6)),
                'chrome_max': int(chrome.max()),
                'chrome_changed_pixels': int(np.count_nonzero(chrome)),
                'chrome_over6': int(np.count_nonzero(chrome > 6)),
                'max_coordinates': [[int(x), int(y)] for x, y in zip(xs, ys)]
                    if 0 < pixels.max() and len(xs) < 100 else None,
                'baseline_sha256': hashlib.sha256(a_path.read_bytes()).hexdigest(),
                'candidate_sha256': hashlib.sha256(b_path.read_bytes()).hexdigest(),
            })
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--pair', action='append', required=True,
                        help='Baseline,candidate mode names')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    rows = []
    for pair in args.pair:
        baseline, candidate = pair.split(',')
        selected = compare(args.directory, baseline, candidate)
        rows.extend(selected)
        print(pair, 'pairs', len(selected),
              'max', max(r['max_channel'] for r in selected),
              'chrome max', max(r['chrome_max'] for r in selected),
              'changed pixels', sum(r['changed_pixels'] for r in selected))
    args.out.write_text(json.dumps(rows, indent=2) + '\n')


if __name__ == '__main__':
    main()
