import json
import gzip
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from subprocess import CompletedProcess

from run_android import cleanup, skin_temperature, stop_owned_perfetto
from summarize import gpu_cost, load_gpu, reduce_report
from presentation import cadence
from frame_cpu import phase_cost, audit_allocator_counters
from cpu_stack import in_phases, summarize, walk_stack


class StageSummaryTest(unittest.TestCase):
    def test_recorder_expiry_preserves_trace_without_signaling(self):
        result = CompletedProcess([], 1, '', 'No such file or directory')
        with patch('run_android.subprocess.run', return_value=result) as run:
            stop_owned_perfetto('42', {})
        self.assertEqual(run.call_count, 1)
        self.assertIn('/proc/42/comm', run.call_args.args[0])

    def test_recorder_reused_pid_is_not_signaled(self):
        result = CompletedProcess([], 0, 'unrelated-app\n', '')
        with patch('run_android.subprocess.run', return_value=result) as run:
            stop_owned_perfetto('42', {})
        self.assertEqual(run.call_count, 1)

    def test_recorder_permission_error_is_not_treated_as_expiry(self):
        result = CompletedProcess([], 1, '', 'Permission denied')
        with patch('run_android.subprocess.run', return_value=result):
            with self.assertRaisesRegex(RuntimeError, 'Cannot inspect'):
                stop_owned_perfetto('42', {})

    def test_recorder_exit_between_probe_and_signal_is_accepted(self):
        results = [CompletedProcess([], 0, 'perfetto\n', ''),
                   CompletedProcess([], 1, '', 'No such process'),
                   CompletedProcess([], 1, '', 'No such process')]
        with patch('run_android.subprocess.run', side_effect=results) as run:
            stop_owned_perfetto('42', {})
        self.assertEqual(run.call_count, 3)
        self.assertEqual(run.call_args_list[1].args[0],
                         ['adb', 'shell', 'kill', '-TERM', '42'])

    def test_stack_samples_belong_to_exact_half_open_phases_once(self):
        rows = [{'ts': ts} for ts in [0, 9, 10, 15, 20, 29, 30]]
        self.assertEqual([r['ts'] for r in in_phases(rows, [(0, 10), (20, 30)])],
                         [0, 9, 20, 29])
        with self.assertRaisesRegex(ValueError, 'overlapping'):
            in_phases(rows, [(0, 15), (10, 20)])

    def test_stack_counts_do_not_sum_nested_or_recursive_functions(self):
        frames = {0: {'mapping': 0, 'resolved_name': 'driver'},
                  1: {'mapping': 1, 'resolved_name': 'submit'},
                  2: {'mapping': 1, 'resolved_name': 'submit'}}
        sites = {0: {'frame_id': 2, 'parent_id': None},
                 1: {'frame_id': 1, 'parent_id': 0},
                 2: {'frame_id': 0, 'parent_id': 1}}
        rows = [{'callsite_id': 2, 'unwind_error': None},
                {'callsite_id': None, 'unwind_error': 'invalid_elf'}]
        result = summarize(rows, sites, frames,
                           {0: {'name': 'mali'}, 1: {'name': 'flutter'}}, 1)
        self.assertEqual(result['samples'], 2)
        self.assertEqual(dict(result['inclusive_functions'])['submit'], 1)
        self.assertEqual(result['nearest_engine_functions'], [('submit', 1)])
        self.assertEqual(dict(result['leaf_modules'])['no stack'], 1)
        self.assertEqual(result['unwind_errors']['invalid_elf'], 1)

    def test_stack_reader_rejects_cycles(self):
        with self.assertRaisesRegex(ValueError, 'Cyclic'):
            walk_stack(0, {0: {'frame_id': 0, 'parent_id': 0}}, {0: {}})

    def test_float_counter_audit_requires_exact_complete_error_accounting(self):
        markers = ['C|42|AllocatorVK|12.500000\n', 'C|42|AllocatorVK|3']
        self.assertEqual(audit_allocator_counters(markers, 42, 1)['sync_slice_parse_failures'], 0)
        with self.assertRaisesRegex(ValueError, 'Not every'):
            audit_allocator_counters(markers, 42, 2)
        with self.assertRaisesRegex(ValueError, 'format'):
            audit_allocator_counters(['B|42|AllocatorVK|1.0'], 42, 1)
        with self.assertRaisesRegex(ValueError, 'value'):
            audit_allocator_counters(['C|42|AllocatorVK|NaN'], 42, 1)

    def test_frame_cpu_clips_states_and_separates_scheduler_delay(self):
        rows = [{'ts': 0, 'dur': 4_000_000, 'state': 'Running'},
                {'ts': 4_000_000, 'dur': 3_000_000, 'state': 'R+'},
                {'ts': 7_000_000, 'dur': 2_000_000, 'state': 'S'}]
        result = phase_cost(rows, [r['ts'] for r in rows], 2_000_000, 8_000_000)
        self.assertEqual(result['wall_ms'], 6)
        self.assertEqual(result['running_ms'], 2)
        self.assertEqual(result['runnable_ms'], 3)
        self.assertEqual(result['not_runnable_ms'], 1)
        self.assertEqual(result['uncovered_ms'], 0)

    def test_frame_cpu_never_labels_missing_trace_as_blocked(self):
        result = phase_cost([{'ts': 10, 'dur': 10, 'state': 'Running'}], [10], 0, 30)
        self.assertEqual(result['uncovered_ms'], .00002)
        self.assertEqual(result['not_runnable_ms'], 0)

    def test_frame_cpu_rejects_overlapping_states(self):
        rows = [{'ts': 0, 'dur': 20, 'state': 'Running'},
                {'ts': 5, 'dur': 15, 'state': 'R'}]
        with self.assertRaisesRegex(ValueError, 'Overlapping'):
            phase_cost(rows, [0, 5], 0, 20)

    def test_buffer_cadence_deduplicates_merged_presentations(self):
        frames = [{'present_ns': ts, 'present_type': 'On-time Present', 'jank_type': 'None'}
                  for ts in [0, 10_000_000, 10_000_000, 30_000_000, None]]
        result = cadence(frames, 10_000_000)
        self.assertEqual(result['unique_presentations'], 3)
        self.assertEqual(result['unmapped_display_buffers'], 1)
        self.assertEqual(result['missed_presentation_slots'], 1)
        self.assertEqual(result['longest_presentation_gap_ms'], 20)

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
