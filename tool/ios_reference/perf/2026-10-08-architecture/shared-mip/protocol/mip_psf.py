"""Model shared mip blur quality; this is not a GPU performance benchmark.

Requires NumPy. Pixel centers, separable downsampling, bilinear reconstruction
and trilinear LOD mixing are explicit. No third-party shader is copied. The
Gaussian reference is a discrete normalized kernel, not Impeller output.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np

_RADIUS = 512


def collapsed_tent_weights(level):
    """Compose exact tent levels before decimation; rounding is excluded."""
    weights = np.ones(1)
    for step in range(level):
        kernel = np.zeros(3 * (2 ** step) + 1)
        kernel[::2 ** step] = np.array([1, 3, 3, 1]) / 8
        weights = np.convolve(weights, kernel)
    return weights


def downsample(values, kernel):
    """Halve an even row at destination centers 2*j + 1 in source units."""
    if len(values) % 2:
        raise ValueError('Even dimensions required')
    if kernel == 'box':
        return (values[::2] + values[1::2]) * .5
    if kernel != 'tent4':
        raise ValueError(kernel)
    padded = np.pad(values, (1, 2))
    return (padded[0:-3:2] + 3 * padded[1:-2:2]
            + 3 * padded[2:-1:2] + padded[3::2]) / 8


def response(level, phase, kernel, radius=_RADIUS):
    """Reconstruct a unit impulse, indexed relative to its original center."""
    values = np.zeros(2048)
    origin = 768 + phase
    values[origin] = 1
    for _ in range(level):
        values = downsample(values, kernel)
    x = np.arange(-radius, radius + 1, dtype=float)
    coordinates = (origin + x + .5) / (2 ** level) - .5
    return np.interp(coordinates, np.arange(len(values)), values,
                     left=0, right=0)


def gaussian(sigma, radius=_RADIUS):
    x = np.arange(-radius, radius + 1, dtype=float)
    weights = np.exp(-.5 * (x / sigma) ** 2)
    return weights / weights.sum()


def average_kernel(level, kernel):
    row = np.mean([response(level, phase, kernel)
                   for phase in range(2 ** level)], axis=0)
    return np.outer(row, row)


def fit_lod(sigma, averages):
    """Fit the averaged 2D PSF, without pretending LOD is Gaussian sigma."""
    row = gaussian(sigma)
    target = np.outer(row, row)
    best = None
    for level in range(len(averages) - 1):
        a, b = averages[level:level + 2]
        direction = b - a
        fraction = float(np.clip(np.sum((target - a) * direction)
                                 / np.sum(direction * direction), 0, 1))
        result = a + fraction * direction
        error = float(np.linalg.norm(result - target)
                      / np.linalg.norm(target))
        if best is None or error < best[0]:
            best = error, level + fraction, result
    return best


def phase_metrics(sigma, lod, kernel):
    """Test all phases for the centroids and a bounded 2D quality matrix."""
    level = math.floor(lod)
    fraction = lod - level
    period = 2 ** (level + 1)
    rows = [(response(level, phase, kernel),
             response(level + 1, phase, kernel))
            for phase in range(period)]
    x = np.arange(-_RADIUS, _RADIUS + 1, dtype=float)
    centers = [float(np.dot(x, (1 - fraction) * a + fraction * b))
               for a, b in rows]
    phases = sorted({0, period // 4, period // 2,
                     3 * period // 4, period - 1})
    target = np.outer(gaussian(sigma), gaussian(sigma))
    errors, variances, masses = [], [], []
    for px in phases:
        for py in phases:
            ax, bx = rows[px]
            ay, by = rows[py]
            psf = ((1 - fraction) * np.outer(ay, ax)
                   + fraction * np.outer(by, bx))
            masses.append(float(psf.sum()))
            errors.append(float(np.abs(psf - target).sum() / 2))
            marginal = psf.sum(axis=0)
            center = float(np.dot(x, marginal))
            variances.append(float(np.dot((x - center) ** 2, marginal)))
    return {
        'centroid_all_x_phases_px_min': min(centers),
        'centroid_all_x_phases_px_max': max(centers),
        'sampled_2d_phases': len(errors),
        'unit_impulse_mass_min': min(masses),
        'unit_impulse_mass_max': max(masses),
        'total_variation_to_gaussian_min': min(errors),
        'total_variation_to_gaussian_max': max(errors),
        'centered_sigma_x_min': math.sqrt(min(variances)),
        'centered_sigma_x_max': math.sqrt(max(variances)),
    }


def experiment():
    results = []
    for kernel in ['box', 'tent4']:
        averages = [average_kernel(level, kernel) for level in range(8)]
        for sigma in [4, 8, 16, 32]:
            error, lod, _ = fit_lod(sigma, averages)
            results.append({
                'downsample': kernel,
                'target_sigma_physical_px': sigma,
                'fitted_lod': lod,
                'phase_average_relative_l2': error,
                **phase_metrics(sigma, lod, kernel),
            })
    return {
        'schema': 'morph-mip-psf-v1',
        'source_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'numpy_version': np.__version__,
        'model': {
            'source': 'unit impulse on 2048x2048 conceptual grid',
            'coordinates': 'texel centers at index + 0.5; clamp-free interior',
            'box': '2x2 mean at each downsample step',
            'tent4': 'separable [1,3,3,1]/8 at each downsample step',
            'reconstruction': 'bilinear per mip; trilinear between two mips',
            'fit': 'least-squares to phase-averaged 2D Gaussian PSF',
            'lod_range': [0, 7],
            'color': 'linear scalar; no quantization or premultiplied edges',
        },
        'limitations': [
            'No CPU/GPU time, native compiler, driver, capture or submission measurements.',
            'This specifies a proposed mip generator, not glGenerateMipmap or Impeller behavior.',
            'Phase dependence is a diagnostic, not a measured visible shimmer amplitude.',
            'Impulse tests alone do not establish image or Apple-reference fidelity.',
            'Generating tent4 mips costs more work than box; timing is unknown.',
        ],
        'rows': results,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.write_text(json.dumps(experiment(), indent=2) + '\n')


if __name__ == '__main__':
    main()
