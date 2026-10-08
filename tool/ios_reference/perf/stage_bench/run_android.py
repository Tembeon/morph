#!/usr/bin/env python3
"""Build/run the standalone stage bench; restore the installed APK on exit."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import shutil
import tempfile
import time

ROOT = Path(__file__).resolve().parents[4]
PKG = 'dev.tembeon.morph_example'
DEVICE = f'/sdcard/Android/data/{PKG}/files/stage-bench'
TARGET = 'lib/perf/glass_stage_bench.dart'


def command(args, **kwargs):
    try:
        return subprocess.run(args, check=True, text=True, **kwargs)
    except subprocess.CalledProcessError as error:
        detail = error.stderr or error.stdout or ''
        raise RuntimeError(f'Command failed ({error.returncode}): {args}; {detail.strip()}') from error


def interrupted(signum, frame):
    raise KeyboardInterrupt


def cleanup(actions):
    """Attempt every owned-resource cleanup, including APK restoration."""
    failures = []
    for label, action in actions:
        try:
            action()
        except Exception as error:
            failures.append(f'{label}: {error}')
    if failures:
        raise RuntimeError('Cleanup incomplete: ' + '; '.join(failures))


def skin_temperature(thermal):
    """Prefer the final HAL sensor reading over an earlier cached reading."""
    readings = re.findall(r'Temperature\{mValue=(-?[0-9.]+)[^\n]*?mName=VIRTUAL-SKIN', thermal)
    return float(readings[-1]) if readings else None


def run(args):
    env = dict(os.environ, ANDROID_SERIAL=args.serial)

    def adb(*items, capture=True):
        return command(['adb', *items], env=env, timeout=45,
                       stdout=subprocess.PIPE if capture else None,
                       stderr=subprocess.PIPE if capture else None).stdout

    if not args.apk.is_file():
        raise FileNotFoundError(args.apk)
    args.out.mkdir(parents=True, exist_ok=True)
    base = args.out / args.name
    if any(Path(str(base) + suffix).exists() for suffix in ('.json', '.device.txt', '.gpuwork.txt', '.pftrace')):
        raise FileExistsError(f'Refusing to overwrite {base}')
    lock = Path('/tmp/morph-native/pixel.lock')
    lock.parent.mkdir(parents=True, exist_ok=True)
    lock.mkdir()
    owner = f'stage-bench pid={os.getpid()} serial={args.serial}'
    (lock / 'owner').write_text(owner + '\n')
    recorder = None
    recorder_file = None
    perfetto_pid = None
    gpu_state = None
    installed = False
    gallery_stopped = False
    notes = []
    remote_trace = f'/data/misc/perfetto-traces/morph-stage-{os.getpid()}.pftrace'
    remote_config = f'/data/local/tmp/morph-stage-{os.getpid()}.cfg'
    with tempfile.TemporaryDirectory(prefix='morph-stage-') as temporary:
        backup = Path(temporary) / 'original.apk'
        def stop_perfetto():
            nonlocal perfetto_pid
            if not perfetto_pid:
                return
            adb('shell', 'kill', '-TERM', perfetto_pid)
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                alive = subprocess.run(['adb', 'shell', 'kill', '-0', perfetto_pid],
                                       env=env, capture_output=True, timeout=15)
                if alive.returncode != 0:
                    perfetto_pid = None
                    return
                time.sleep(.25)
            raise TimeoutError('Owned Perfetto recorder did not stop')
        try:
            paths = adb('shell', 'pm', 'path', PKG).strip().splitlines()
            if len(paths) != 1 or not paths[0].startswith('package:'):
                raise RuntimeError('A single installed gallery APK is required for restoration')
            adb('pull', paths[0].removeprefix('package:'), str(backup))
            adb('shell', 'am', 'force-stop', PKG)
            gallery_stopped = True
            cool_deadline = time.monotonic() + 300
            before = adb('shell', 'dumpsys', 'thermalservice')
            while args.cool_c > 0:
                skin = skin_temperature(before)
                if skin is None or skin < args.cool_c:
                    break
                if time.monotonic() >= cool_deadline:
                    raise TimeoutError('Phone did not cool before the launch')
                time.sleep(5)
                before = adb('shell', 'dumpsys', 'thermalservice')
            notes = [f'apk: {args.apk}', f'sha256: {hashlib.sha256(args.apk.read_bytes()).hexdigest()}',
                     f'original_apk_sha256: {hashlib.sha256(backup.read_bytes()).hexdigest()}',
                     f'trace: {args.trace}', f'commit: {command(["git", "rev-parse", "HEAD"], cwd=ROOT, stdout=subprocess.PIPE).stdout.strip()}',
                     'before:', before, adb('shell', 'dumpsys', 'battery')]
            if skin_temperature(before) is not None:
                notes.append(f'skin: {skin_temperature(before)}')
            build_record = Path(str(args.apk) + '.build.json')
            if build_record.exists():
                shutil.copy2(build_record, Path(str(base) + '.build.json'))
            installed = True
            adb('install', '-r', str(args.apk))
            adb('shell', 'am', 'force-stop', PKG)
            adb('shell', 'rm', '-f', f'{DEVICE}/report.json', f'{DEVICE}/error.json')
            if args.trace == 'gpu':
                trace_dir = '/sys/kernel/tracing'
                names = ['tracing_on', 'trace_clock', 'buffer_size_kb',
                         'events/power/gpu_work_period/enable', 'events/power/gpu_frequency/enable']
                values = [adb('shell', 'cat', f'{trace_dir}/{name}').strip() for name in names]
                if values[0] != '0' or values[3:] != ['0', '0']:
                    raise RuntimeError('Kernel GPU tracing is already in use')
                gpu_state = dict(zip(names, values))
                adb('shell', f'cd {trace_dir} && echo mono > trace_clock && echo 8192 > buffer_size_kb && '
                    'echo > trace && echo 1 > events/power/gpu_work_period/enable && '
                    'echo 1 > events/power/gpu_frequency/enable && echo 1 > tracing_on')
                recorder_file = Path(str(base) + '.gpuwork.txt').open('w')
                recorder = subprocess.Popen(['adb', 'shell', 'cat', f'{trace_dir}/trace_pipe'],
                                            env=env, stdout=recorder_file, stderr=subprocess.DEVNULL)
            elif args.trace == 'energy':
                adb('push', str(ROOT / 'tool/ios_reference/perf/energy_android.cfg'), remote_config)
                result = adb('shell', f'cat {remote_config} | perfetto --txt -c - -o {remote_trace} --background')
                perfetto_pid = result.strip().splitlines()[-1]
                if not perfetto_pid.isdigit() or int(perfetto_pid) <= 1:
                    perfetto_pid = None
                    raise RuntimeError(f'Invalid Perfetto PID: {result}')
                time.sleep(3)
            notes.append(adb('shell', 'pm', 'list', 'packages', '-U', PKG))
            notes.append(adb('shell', 'am', 'start', '-W', '-n', f'{PKG}/.MainActivity'))
            app_pid = adb('shell', 'pidof', PKG).strip().split()[0]
            deadline = time.monotonic() + args.timeout
            while time.monotonic() < deadline:
                result = subprocess.run(['adb', 'shell', 'test', '-f', f'{DEVICE}/report.json'],
                                        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
                if result.returncode == 0:
                    break
                error = subprocess.run(['adb', 'shell', 'cat', f'{DEVICE}/error.json'],
                                       env=env, capture_output=True, text=True, timeout=15)
                if error.returncode == 0:
                    raise RuntimeError(error.stdout)
                time.sleep(1)
            else:
                raise TimeoutError('Stage benchmark did not finish')
            time.sleep(1)
            if perfetto_pid:
                stop_perfetto()
                adb('pull', remote_trace, str(base) + '.pftrace')
            adb('pull', f'{DEVICE}/report.json', str(base) + '.json')
            report = json.loads(Path(str(base) + '.json').read_text())
            if args.schema == 'stage':
                if report.get('schema') != 'morph-stage-bench-v1':
                    raise RuntimeError('Unexpected report schema')
            elif not report.get('liquid_available'):
                raise RuntimeError('Native audit did not enable liquid glass')
            if args.pull_artifacts:
                adb('pull', DEVICE, str(base) + '.artifacts')
            after = adb('shell', 'dumpsys', 'thermalservice')
            notes.extend(['after:', after, adb('shell', 'dumpsys', 'battery'),
                          'renderer log:', adb('logcat', '-d', f'--pid={app_pid}', '-s', 'flutter')])
            if skin_temperature(after) is not None:
                notes.append(f'skin: {skin_temperature(after)}')
            Path(str(base) + '.device.txt').write_text('\n'.join(notes))
        finally:
            def stop_stream():
                recorder.terminate()
                try:
                    recorder.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    recorder.kill()
                    recorder.wait()
            actions = []
            if perfetto_pid:
                actions.append(('stop Perfetto', stop_perfetto))
            if gpu_state:
                actions.append(('stop GPU trace', lambda: adb('shell', 'echo 0 > /sys/kernel/tracing/tracing_on')))
            if recorder:
                actions.append(('stop GPU stream', stop_stream))
            if recorder_file:
                actions.append(('close GPU output', recorder_file.close))
            if gpu_state:
                clock = gpu_state['trace_clock'].split('[')[1].split(']')[0]
                actions.append(('restore tracing settings', lambda: adb('shell',
                    f'cd /sys/kernel/tracing && echo 0 > events/power/gpu_work_period/enable && '
                    'echo 0 > events/power/gpu_frequency/enable && echo > trace && '
                    f'echo {clock} > trace_clock && echo {gpu_state["buffer_size_kb"]} > buffer_size_kb')))
            if args.trace == 'energy':
                actions.append(('remove owned Perfetto files', lambda: adb('shell', 'rm', '-f', remote_trace, remote_config)))
            if installed:
                actions.extend([
                    ('stop bench', lambda: adb('shell', 'am', 'force-stop', PKG)),
                    ('restore gallery APK', lambda: adb('install', '-r', str(backup))),
                ])
            if gallery_stopped or installed:
                actions.append(('open gallery', lambda: adb('shell', 'am', 'start', '-n', f'{PKG}/.MainActivity')))
            def unlock():
                if (lock / 'owner').read_text().strip() == owner:
                    (lock / 'owner').unlink()
                    lock.rmdir()
            actions.append(('release owned lock', unlock))
            try:
                cleanup(actions)
            except Exception as error:
                if backup.exists():
                    recovery = Path(str(base) + '.restore.apk')
                    shutil.copy2(backup, recovery)
                    raise RuntimeError(f'{error}; gallery recovery APK: {recovery}') from error
                raise
            finally:
                if notes and not Path(str(base) + '.device.txt').exists():
                    Path(str(base) + '.device.txt').write_text('\n'.join(notes) + '\nincomplete launch\n')
    print(f'Report: {base}.json; original gallery restored')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='step', required=True)
    build = sub.add_parser('build')
    build.add_argument('--apk', required=True, type=Path)
    build.add_argument('--target', default=TARGET)
    build.add_argument('--flutter', default='flutter',
                       help='Flutter executable, for example flutter-beta')
    build.add_argument('--define', action='append', default=[])
    launch = sub.add_parser('run')
    launch.add_argument('--apk', required=True, type=Path)
    launch.add_argument('--out', required=True, type=Path)
    launch.add_argument('--name', default='stage-1')
    launch.add_argument('--serial', default='26221JEGR12737')
    launch.add_argument('--trace', choices=['gpu', 'energy', 'none'], default='gpu')
    launch.add_argument('--schema', choices=['stage', 'native'], default='stage')
    launch.add_argument('--pull-artifacts', action='store_true')
    launch.add_argument('--timeout', type=int, default=600)
    launch.add_argument('--cool-c', type=float, default=37)
    args = parser.parse_args()
    if args.step == 'build':
        sdk = json.loads(command([args.flutter, '--version', '--machine'],
                                stdout=subprocess.PIPE).stdout)
        command([args.flutter, 'build', 'apk', '--profile', '--target-platform', 'android-arm64',
                 '-t', args.target, f'--dart-define=AUDIT_OUT={DEVICE}',
                 *[f'--dart-define={value}' for value in args.define]], cwd=ROOT / 'example')
        args.apk.parent.mkdir(parents=True, exist_ok=True)
        args.apk.write_bytes((ROOT / 'example/build/app/outputs/flutter-apk/app-profile.apk').read_bytes())
        Path(str(args.apk) + '.build.json').write_text(json.dumps({
            'target': args.target, 'defines': args.define,
            'flutter_executable': args.flutter, 'sdk': sdk,
            'commit': command(['git', 'rev-parse', 'HEAD'], cwd=ROOT, stdout=subprocess.PIPE).stdout.strip(),
            'source_sha256': hashlib.sha256((ROOT / 'example' / args.target).read_bytes()).hexdigest(),
            'apk_sha256': hashlib.sha256(args.apk.read_bytes()).hexdigest(),
        }, indent=2) + '\n')
    else:
        if not re_safe_name(args.name):
            parser.error('--name must contain only ASCII letters, digits, underscore or hyphen')
        if args.timeout <= 0 or not math.isfinite(args.cool_c) or args.cool_c < 0:
            parser.error('--timeout must be positive and --cool-c finite and nonnegative')
        for sig in (signal.SIGINT, signal.SIGTERM):
            signal.signal(sig, interrupted)
        run(args)


def re_safe_name(value):
    return bool(value) and all(c in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in value)


if __name__ == '__main__':
    main()
