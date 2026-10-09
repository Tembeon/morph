"""Native frame crops must exclude display chrome without hiding glass errors."""

import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image

from owned_optics_quality import analyze


class NativeOpticsQualityTest(unittest.TestCase):
    def fixture(self, folder, crop):
        names = ['owned-raw', 'glass-zero', 'foreground']
        report = {'fixture': 'shared-source-morph-optics', 'device_pixel_ratio': 1,
                  'case_metadata': {}}
        for mode in names:
            name = 'mip-' + mode + '-n1-reuse'
            report['case_metadata'][name] = {
                'mode': mode, 'lens_count': 1, 'source_update': 'unchanged',
                'visible_rects_logical': [[8,8,48,48]]}
            pixels = np.full((96,80,3), 17, dtype=np.uint8)
            pixels[19:83,7:71] = 128
            pixels[49:51,37:39] = 255
            if mode == 'owned-raw':
                pixels[42,30] = 140
            Image.fromarray(pixels).save(folder / (name + '.png'))
            (folder / (name + '.json')).write_text(json.dumps({'crop': crop}))
        path = folder / 'report.json'
        path.write_text(json.dumps(report))
        return path

    def test_native_crop_retains_optical_error_and_hashes_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            report = self.fixture(folder, [7,19,64,64])
            result = analyze(report, folder)
            row = result['rows'][0]
            self.assertEqual(row['rim_and_bounds']['max'], 12)
            self.assertEqual(row['outside']['max'], 0)
            self.assertEqual(row['opaque_foreground']['max'], 0)
            self.assertEqual(len(result['image_sha256']), 6)

    def test_native_crop_rejects_out_of_frame_extent(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            report = self.fixture(folder, [7,19,100,100])
            with self.assertRaisesRegex(ValueError, 'exceeds frame'):
                analyze(report, folder)


if __name__ == '__main__':
    unittest.main()
