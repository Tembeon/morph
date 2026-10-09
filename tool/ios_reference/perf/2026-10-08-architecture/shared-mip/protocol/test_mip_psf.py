"""Numerical invariants for the proposed mip-quality experiment."""

import unittest

import numpy as np

from mip_psf import collapsed_tent_weights, downsample, response


class MipPsfTest(unittest.TestCase):
    def test_collapsed_four_levels_match_staged_decimation_interior(self):
        values = np.random.default_rng(123).random(1024)
        staged = values
        for _ in range(4):
            staged = downsample(staged, 'tent4')
        weights = collapsed_tent_weights(4)
        self.assertEqual(len(weights), 46)
        self.assertAlmostEqual(weights.sum(), 1)
        for j in range(2, len(staged)-2):
            direct = np.dot(weights, values[16*j-15:16*j+31])
            self.assertAlmostEqual(direct, staged[j])

    def test_gpu_tap_coordinates_realize_tent_weights(self):
        values = np.random.default_rng(123).random(64)
        centers = np.arange(32) * 2 + .5
        sampled = (np.interp(centers-.75, np.arange(64), values)
                   + np.interp(centers+.75, np.arange(64), values)) / 2
        np.testing.assert_allclose(sampled[1:-1], downsample(values, 'tent4')[1:-1])

    def test_constant_interior_preserves_dc(self):
        for kernel in ['box', 'tent4']:
            np.testing.assert_allclose(downsample(np.ones(64), kernel)[2:-2], 1)

    def test_reconstructed_impulse_preserves_mass_at_every_phase(self):
        for kernel in ['box', 'tent4']:
            for level in range(6):
                for phase in range(2 ** level):
                    self.assertAlmostEqual(response(level, phase, kernel).sum(), 1)

    def test_box_impulse_centroid_exposes_grid_phase(self):
        x = np.arange(-512, 513)
        for phase in range(8):
            self.assertAlmostEqual(np.dot(x, response(3, phase, 'box')),
                                   3.5 - phase)

    def test_tent_impulse_centroid_stays_at_source(self):
        x = np.arange(-512, 513)
        for level in range(6):
            for phase in range(2 ** level):
                self.assertAlmostEqual(np.dot(x, response(level, phase, 'tent4')), 0)


if __name__ == '__main__':
    unittest.main()
