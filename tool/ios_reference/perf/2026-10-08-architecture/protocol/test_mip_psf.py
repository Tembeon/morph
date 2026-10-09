"""Numerical invariants for the proposed mip-quality experiment."""

import unittest

import numpy as np

from mip_psf import downsample, response


class MipPsfTest(unittest.TestCase):
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
