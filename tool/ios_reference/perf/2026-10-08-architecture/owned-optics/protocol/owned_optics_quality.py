"""Compare shared owned-source Morph optics to matched native-filter optics.

Frozen phase-zero frames only. No Apple fidelity or motion admission follows
from these statistics. Foreground checks cover opaque white text interiors;
they intentionally do not equate antialiased text edges over different glass.
"""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from mip_quality import stats


def analyze(report_path, shots):
    report = json.loads(report_path.read_text())
    if report['fixture'] != 'shared-source-morph-optics':
        raise ValueError('Expected the real Morph optical fixture')
    hashes = {}

    def read(name):
        path = shots / (name + '.png')
        hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        image = Image.open(path).convert('RGB')
        crop_path = shots / (name + '.json')
        if crop_path.exists():
            hashes[crop_path.name] = hashlib.sha256(crop_path.read_bytes()).hexdigest()
            x,y,w,h = json.loads(crop_path.read_text())['crop']
            if x < 0 or y < 0 or x+w > image.width or y+h > image.height:
                raise ValueError('Native screen crop exceeds frame')
            image = image.crop((x,y,x+w,y+h))
        return np.asarray(image).astype(np.float32)

    def find(mode, metadata):
        return next(k for k,v in report['case_metadata'].items()
                    if v['mode'] == mode and v['lens_count'] == metadata['lens_count']
                    and v['source_update'] == metadata['source_update'])

    rows = []
    for name, metadata in report['case_metadata'].items():
        owned = metadata['mode'].startswith('owned-')
        if not owned and metadata['mode'] != 'glass-grouped':
            continue
        control_mode = 'glass-zero' if metadata['mode'] == 'owned-raw' else 'glass-merged'
        actual = read(name)
        control_name = find(control_mode, metadata)
        control = read(control_name)
        foreground = read(find('foreground', metadata))
        if actual.shape != control.shape or actual.shape != foreground.shape:
            raise ValueError('Image extent mismatch')
        inside = np.zeros(actual.shape[:2], dtype=bool)
        outside = np.ones(actual.shape[:2], dtype=bool)
        bounds = np.zeros(actual.shape[:2], dtype=bool)
        for x,y,w,h in metadata['visible_rects_logical']:
            a,b,c,d = [int(round(v*report['device_pixel_ratio'])) for v in (x,y,x+w,y+h)]
            inside[b+16:d-16,a+16:c-16] = True
            outside[max(0,b-4):d+4,max(0,a-4):c+4] = False
            bounds[max(0,b-4):d+4,max(0,a-4):c+4] = True
        ink = (foreground == 255).all(axis=2)
        if not ink.any():
            raise ValueError('Missing opaque foreground witness')
        error = np.abs(actual-control)
        row = {'case': name, 'control': control_name,
               'comparison': 'owned-source' if owned else 'layer-sharing',
               'whole_image': stats(error, np.ones(actual.shape[:2], dtype=bool)),
               'interior': stats(error, inside & ~ink),
               'rim_and_bounds': stats(error, bounds & ~inside & ~ink),
               'outside': stats(error, outside),
               'opaque_foreground': stats(np.abs(actual-foreground), ink)}
        if metadata['mode'] in ('owned-wide', 'owned-serial-wide'):
            tent = metadata['mode'].replace('wide', 'tent')
            row['to_owned_tent'] = stats(np.abs(actual-read(find(tent, metadata))), bounds)
        if metadata['mode'].startswith('owned-serial-'):
            batched = metadata['mode'].replace('owned-serial-', 'owned-')
            row['to_batched'] = stats(np.abs(actual-read(find(batched, metadata))), bounds)
        rows.append(row)
    return {'report_sha256': hashlib.sha256(report_path.read_bytes()).hexdigest(),
            'image_sha256': hashes, 'rows': rows,
            'limitations': ['Frozen phase zero; source acquisition, history/reveal and arbitrary transforms are not covered.',
                            'Owned cached Gaussian preserves requested logical sigma and DPR; graph bounds and filter phase may still differ.',
                            'Approximate pyramid kernels remain different from stock Gaussian.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('shots', type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    args.out.write_text(json.dumps(analyze(args.report,args.shots),indent=2)+'\n')


if __name__ == '__main__':
    main()
