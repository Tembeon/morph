import json
import gzip
from pathlib import Path
import tempfile
import unittest

from run_android import cleanup, skin_temperature
from summarize import gpu_cost, load_gpu, reduce_report


class StageSummaryTest(unittest.TestCase):
    def test_cooldown_uses_latest_hal_reading(self):
        thermal = ('Cached temperatures:\nTemperature{mValue=32.0, mType=3, mName=VIRTUAL-SKIN}\n'
                   'Current temperatures from HAL:\nTemperature{mValue=39.0, mType=3, mName=VIRTUAL-SKIN}\n')
        self.assertEqual(skin_temperature(thermal), 39.0)
        self.assertIsNone(skin_temperature('no sensor'))

    def test_frequency_transitions_inside_one_gpu_period(self):
        active, cycles, count = gpu_cost([(0, 20_000_000, 10_000_000)],
                                        [(0, 100_000_000), (10_000_000, 200_000_000)],
                                        5_000_000, 15_000_000)
        self.assertEqual(active, 5_000_000)
        self.assertEqual(cycles, 750_000)
        self.assertEqual(count, 1)

    def test_future_frequency_is_never_backfilled(self):
        active, cycles, _ = gpu_cost([(0, 20, 10)], [(5, 100_000_000)], 0, 20)
        self.assertEqual(active, 10)
        self.assertIsNone(cycles)

    def test_uid_filter_and_missing_uid(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder) / 'stage-1'
            Path(str(base) + '.gpuwork.txt').write_text(
                ' t 1.0: gpu_work_period: gpu_id=0 uid=17 start_time_ns=100 end_time_ns=200 total_active_duration_ns=90\n'
                ' t 1.0: gpu_work_period: gpu_id=0 uid=99 start_time_ns=100 end_time_ns=200 total_active_duration_ns=10\n')
            Path(str(base) + '.device.txt').write_text('package:dev.tembeon.morph_example uid:17\n')
            periods, _ = load_gpu(base)
            self.assertEqual(periods, [(100, 200, 90)])
            trace = Path(str(base) + '.gpuwork.txt')
            Path(str(trace) + '.gz').write_bytes(gzip.compress(trace.read_bytes()))
            trace.unlink()
            self.assertEqual(load_gpu(base)[0], periods)
            Path(str(base) + '.device.txt').write_text('uid:17\n')
            with self.assertRaisesRegex(ValueError, 'exact app UID'):
                load_gpu(base)

    def test_missing_gpu_is_unavailable_and_negative_deltas_are_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'stage-1.json'
            report = {'schema': 'morph-stage-bench-v1', 'liquid_available': True,
                      'runs': 1, 'budget_ms': 16.67, 'case_metadata': {}, 'windows_us': {}}
            for mode, cost in [('bare', 2), ('capture', 1)]:
                report['case_metadata'][mode] = {'mode': mode, 'layout': 'single',
                                                'motion': 'background', 'plan': 'independent'}
                report['windows_us'][mode] = [[100, 1000]]
                report[mode] = {'runs': [{
                    'n': 4, 'build_mean': cost, 'raster_mean': cost,
                    'build_p50': cost, 'raster_p50': cost,
                    'build_p95': cost, 'raster_p95': cost,
                    'build_p99': cost, 'raster_p99': cost, 'over_budget': 0,
                    'frames': [[t, 100, 100, 200] for t in [100, 300, 500, 700]],
                }]}
            path.write_text(json.dumps(report))
            result = reduce_report(path)
            self.assertIsNone(result['rows'][0]['gpu_ms'])
            self.assertEqual(result['deltas'][0]['delta_raster_mean'], -1)
            report['capture']['runs'][0]['frames'][0][0] = 99
            path.write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError, 'outside measured window'):
                reduce_report(path)

    def test_cleanup_continues_to_gallery_restore_after_trace_failure(self):
        done = []

        def fail():
            raise OSError('trace unavailable')

        with self.assertRaisesRegex(RuntimeError, 'stop trace'):
            cleanup([('stop trace', fail), ('restore APK', lambda: done.append('restored')),
                     ('unlock', lambda: done.append('unlocked'))])
        self.assertEqual(done, ['restored', 'unlocked'])


if __name__ == '__main__':
    unittest.main()
