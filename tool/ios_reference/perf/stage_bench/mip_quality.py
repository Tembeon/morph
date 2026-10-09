"""Compare native mip shots to the specified generator and Gaussian control.

Requires NumPy and Pillow. Only report-owned file names are read. Rectangular
interiors exclude rounded/AA edges; background checks exclude whole bounds.
The model uses scalar byte values, clamp edges and 8-bit rounding per pass.
"""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from mip_psf import collapsed_tent_weights


def halve_axis(values, axis, tent):
    values = np.moveaxis(values, axis, 0)
    if not tent:
        result = (values[::2] + values[1::2]) / 2
    else:
        padded = np.pad(values, [(1, 2)] + [(0, 0)] * (values.ndim - 1), mode='edge')
        result = (padded[:-3:2] + 3*padded[1:-2:2]
                  + 3*padded[2:-1:2] + padded[3::2]) / 8
    return np.moveaxis(result, 0, axis)


def reconstruct(values, height, width):
    """Bilinear sampling at normalized destination pixel centers."""
    for axis, size in [(0, height), (1, width)]:
        source_size = values.shape[axis]
        coordinate = (np.arange(size) + .5) * source_size / size - .5
        lower = np.floor(coordinate).astype(int)
        fraction = coordinate - lower
        shape = [1] * values.ndim
        shape[axis] = size
        fraction = fraction.reshape(shape)
        values = (np.take(values, np.clip(lower, 0, source_size-1), axis=axis) * (1-fraction)
                  + np.take(values, np.clip(lower+1, 0, source_size-1), axis=axis) * fraction)
    return values


def collapsed_axis(values, axis):
    values = np.moveaxis(values, axis, 0)
    origin = np.arange(len(values) // 16) * 16 - 15
    result = np.zeros((len(origin), *values.shape[1:]), dtype=np.float32)
    for offset, weight in enumerate(collapsed_tent_weights(4)):
        result += weight * values[np.clip(origin + offset, 0, len(values)-1)]
    return np.moveaxis(np.rint(result), 0, axis)


def model(source, lod, tent, wide=False):
    levels = [source.astype(np.float32)]
    if wide:
        if int(lod) != 4:
            raise ValueError('Collapsed producer supports levels four and five only')
        fourth = collapsed_axis(collapsed_axis(levels[0], 1), 0)
        fifth = np.rint(halve_axis(halve_axis(fourth, 0, True), 1, True))
        levels = [None, None, None, None, fourth, fifth]
    else:
        for _ in range(int(lod) + 1):
            values = halve_axis(halve_axis(levels[-1], 0, tent), 1, tent)
            levels.append(np.rint(values))
    lower = int(lod)
    fraction = lod - lower
    height, width = source.shape[:2]
    return np.rint((1-fraction)*reconstruct(levels[lower], height, width)
                   + fraction*reconstruct(levels[lower+1], height, width))


def stats(error, mask):
    values = error[mask]
    if not values.size:
        raise ValueError('Empty quality region')
    return {'max': float(values.max()), 'mean': float(values.mean()),
            'p95': float(np.quantile(values, .95))}


def analyze(report_path, shots):
    report = json.loads(report_path.read_text())
    if report.get('fixture') != 'shared-mip-owned-texture-blur-only':
        raise ValueError('Expected owned mip fixture')
    hashes = {}

    def read(name):
        path = shots / (name + '.png')
        hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        return np.asarray(Image.open(path).convert('RGB')).astype(np.float32)

    source_name = next(k for k, v in report['case_metadata'].items()
                       if v['mode'] == 'bare' and v['source_update'] == 'unchanged')
    source = read(source_name)
    rows = []
    for name, metadata in report['case_metadata'].items():
        if metadata['mode'] not in ['box', 'tent', 'wide', 'grouped', 'cached']:
            continue
        actual = read(name)
        if actual.shape != source.shape:
            raise ValueError('Image extent mismatch')
        control_name = next(k for k,v in report['case_metadata'].items()
                            if v['mode'] == 'gaussian' and v['lens_count'] == metadata['lens_count']
                            and v['source_update'] == metadata['source_update'])
        control = read(control_name)
        inside = np.zeros(source.shape[:2], dtype=bool)
        outside = np.ones(source.shape[:2], dtype=bool)
        dpr = report['device_pixel_ratio']
        for x,y,w,h in metadata['visible_rects_logical']:
            a,b,c,d = [int(round(v*dpr)) for v in (x,y,x+w,y+h)]
            outside[max(0,b-4):d+4,max(0,a-4):c+4] = False
            inside[b+16:d-16,a+16:c-16] = True
        row = {'case': name, 'to_native_gaussian': stats(np.abs(actual-control), inside),
               'background_to_bare': stats(np.abs(actual-source), outside)}
        if metadata['mode'] in ['box', 'tent', 'wide']:
            expected = model(source, metadata['lod'], metadata['mode']!='box',
                             wide=metadata['mode']=='wide')
            row['to_generator_model'] = stats(np.abs(actual-expected), inside)
        if metadata['mode'] == 'wide':
            tent_name = next(k for k,v in report['case_metadata'].items()
                             if v['mode'] == 'tent' and v['lens_count'] == metadata['lens_count']
                             and v['source_update'] == metadata['source_update'])
            row['to_original_tent'] = stats(np.abs(actual-read(tent_name)), inside)
        rows.append(row)
    return {'report_sha256': hashlib.sha256(report_path.read_bytes()).hexdigest(),
            'image_sha256': hashes, 'rows': rows,
            'limitations': ['Frozen phase zero, not motion fidelity or Apple reference.',
                            'Scalar byte model excludes color management and hardware precision differences.',
                            'Native Gaussian and pyramid PSFs are different; no equivalence is assumed.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('shots', type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    args.out.write_text(json.dumps(analyze(args.report, args.shots), indent=2) + '\n')


if __name__ == '__main__':
    main()
