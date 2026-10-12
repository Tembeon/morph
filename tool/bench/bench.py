#!/usr/bin/env python3
"""One command for the Pixel benches: build, run, trace, analyze, compare.

    tool/bench/bench.py [options]

  --rev REV          build this commit in a cached worktree
                     (/tmp/morph-perf/src/bench-<sha>); default: the working
                     tree as it is, uncommitted edits included
  --suite S          audit,nav (default both): the glass audit
                     (integration_test/glass_audit_test.dart) and the
                     navigation bench (lib/perf/navigation_stage_bench.dart)
  --tiers T          liquid,flat (default): one audit launch per tier; the
                     navigation bench runs its modes in one launch
  --scenes S         audit scenes (default all): home-scroll,segmented,
                     tab-bar,controls,menu,sheet,list
  --motions M        navigation motions (default enter,nested-push,
                     nested-pop,toolbar,steady)
  --runs N           repeats of every timed scene (default 3; 5 with --scenes)
  --idle S           seconds of the audit's resting home with no frames
                     scheduled (default 8; 0 skips it)
  --fixed            fixed performance mode, restored after the run. On the
                     Pixel 6a it pins high clocks: UI and raster halve and
                     frames over budget vanish, so it compares work, never
                     smoothness
  --sdk S            stable (flutter) or beta (flutter-beta)
  --label L          result directory name (default the short sha)
  --no-build         reuse the APKs of the last build of this source
  --no-cpu           skip the Dart CPU pass
  --save-baseline    make this run tool/bench/baseline.json
  --serial S         default the owner's Pixel 6a

Every launch runs under one Perfetto trace (trace.cfg): Flutter and Dart
trace events, sched, CPU / GPU clocks, GPU work periods, SurfaceFlinger's
frame timeline, ODPM power rails, thermal. The app announces its end on
logcat (MORPH_BENCH_DONE), the runner never polls on timers. Launch
settings travel in bench-args.json (example/lib/perf/bench_args.dart), so
one APK per suite serves every tier and scene selection.

Before every launch the runner waits up to --cool-wait seconds (default
300) for Thermal Status 0; a launch that starts warmer is marked in the
table. It holds /tmp/morph-native/pixel.lock for the whole run (waiting up to
--lock-wait seconds, default 2 h, while another run holds it) and on any
exit (including Ctrl-C) stops the app and the trace, removes the launch
settings and turns fixed performance mode back off.

Scenes with two or more frames put down to the UI thread get one more
launch of only those scenes with the Dart CPU profiler sampling over the
VM service (it costs UI time, so the timed launch never samples); the
table then lists the package's functions by inclusive time in those
frames. Nobody has to attach DevTools.

Traces stay in /tmp/morph-perf/bench/<label>/; the reports, the analysis
and summary.txt go to tool/ios_reference/perf/<date>-bench-<label>/.
"""
import argparse
import atexit
import re
import threading
import urllib.parse
import urllib.request
import datetime
import json
import os
import shutil
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
PKG = 'dev.tembeon.morph_example'
FILES = f'/sdcard/Android/data/{PKG}/files'
LOCK = '/tmp/morph-native/pixel.lock'
VENV = os.path.expanduser('~/.cache/morph-bench/venv')
SUITES = {
    'audit': ('integration_test/glass_audit_test.dart', 'glass', []),
    'nav': ('lib/perf/navigation_stage_bench.dart', 'stage-bench',
            ['--dart-define=NAV_SAMPLE_MS=1500', '--dart-define=NAV_WARM_MS=500']),
}

state = {'lock': False, 'perfetto': None, 'fixed': False, 'serial': None}


def log(*a):
    print('[bench]', *a, flush=True)


def adb(*a, check=True, timeout=120):
    r = subprocess.run(['adb', '-s', state['serial'], *a], capture_output=True, text=True,
                       timeout=timeout)
    if check and r.returncode:
        raise RuntimeError(f'adb {" ".join(a)}: {r.stderr.strip()}')
    return r.stdout


def sh(cmd):
    return adb('shell', cmd)


def cleanup():
    try:
        if state['perfetto']:
            sh(f'kill -TERM {state["perfetto"]} 2>/dev/null; true')
            state['perfetto'] = None
        sh(f'am force-stop {PKG}; rm -f {FILES}/bench-args.json')
        if state['fixed']:
            sh('cmd power set-fixed-performance-mode-enabled false')
            state['fixed'] = False
    except Exception as e:
        log('cleanup:', e)
    if state['lock']:
        shutil.rmtree(LOCK, ignore_errors=True)
        state['lock'] = False


def take_lock(wait):
    """Takes the Pixel lock, waiting up to [wait] seconds for another run
    (another session's bench) to release it."""
    os.makedirs(os.path.dirname(LOCK), exist_ok=True)
    started, told = time.time(), False
    while True:
        try:
            os.mkdir(LOCK)
            break
        except FileExistsError:
            path = os.path.join(LOCK, 'owner')
            owner = open(path).read().strip() if os.path.exists(path) else '?'
            if time.time() - started > wait:
                raise SystemExit(f'Pixel is locked: {owner}')
            if not told:
                log(f'waiting for the Pixel lock ({owner})')
                told = True
            time.sleep(15)
    with open(os.path.join(LOCK, 'owner'), 'w') as f:
        f.write(f'tool/bench/bench.py pid {os.getpid()} {datetime.datetime.now()}\n')
    state['lock'] = True


def ensure_venv():
    py = os.path.join(VENV, 'bin', 'python')
    if not os.path.exists(py):
        log('creating', VENV)
        subprocess.run([sys.executable, '-m', 'venv', VENV], check=True)
        subprocess.run([py, '-m', 'pip', '-q', 'install', 'perfetto'], check=True)
    return py


def source(rev):
    if rev is None:
        sha = subprocess.check_output(['git', '-C', ROOT, 'rev-parse', '--short', 'HEAD'],
                                      text=True).strip()
        dirty = subprocess.run(['git', '-C', ROOT, 'diff', '--quiet', 'HEAD', '--', 'lib',
                                'example', 'pubspec.yaml']).returncode != 0
        return ROOT, sha + ('-dirty' if dirty else '')
    sha = subprocess.check_output(['git', '-C', ROOT, 'rev-parse', '--short', rev],
                                  text=True).strip()
    src = f'/tmp/morph-perf/src/bench-{sha}'
    if not os.path.isdir(src):
        subprocess.run(['git', '-C', ROOT, 'worktree', 'add', '--detach', src, sha], check=True,
                       capture_output=True)
    return src, sha


def build(src, suite, apk, sdk):
    target, report, defines = SUITES[suite]
    cmd = ['nice', '-n', '10', 'flutter-beta' if sdk == 'beta' else 'flutter', 'build', 'apk', '--profile',
           '--target-platform', 'android-arm64', '-t', target,
           f'--dart-define=AUDIT_OUT={FILES}/{report}', *defines]
    log('build', suite, 'from', src)
    t = time.time()
    r = subprocess.run(cmd, cwd=os.path.join(src, 'example'), capture_output=True, text=True)
    if r.returncode:
        sys.stderr.write(r.stdout[-3000:] + r.stderr[-3000:])
        raise SystemExit(f'build of {suite} failed')
    os.makedirs(os.path.dirname(apk), exist_ok=True)
    shutil.copy(os.path.join(src, 'example/build/app/outputs/flutter-apk/app-profile.apk'), apk)
    log(f'built {suite} in {time.time() - t:.0f} s')


def thermal():
    out = sh('dumpsys thermalservice')
    status = skin = None
    current = False
    for line in out.splitlines():
        if line.startswith('Thermal Status:'):
            status = int(line.split(':')[1])
        # The cached list above it can be minutes old.
        if line.startswith('Current temperatures from HAL'):
            current = True
        elif current and not line.startswith('\t'):
            current = False
        if current and 'mName=VIRTUAL-SKIN' in line:
            skin = float(line.split('mValue=')[1].split(',')[0])
    return status, skin


def wait_cool(limit):
    t = time.time()
    status, skin = thermal()
    while status and time.time() - t < limit:
        time.sleep(15)
        status, skin = thermal()
    if status:
        log(f'still Thermal Status {status} (skin {skin}) after {limit} s: running warm')
    return status, skin


class DartSampler(threading.Thread):
    """Polls the main isolate's CPU samples over the VM service every 2 s
    (the VM keeps them in a ring buffer) and keeps each as its timeline
    timestamp (CLOCK_MONOTONIC us) and its stack of function names, leaf
    first, marked with whether the function is the package's own."""

    def __init__(self, url):
        super().__init__(daemon=True)
        u = urllib.parse.urlparse(url)
        self.port = adb('forward', 'tcp:0', f'tcp:{u.port}').strip()
        self.base = f'http://127.0.0.1:{self.port}{u.path}'
        self.samples, self.period, self.stop = [], None, threading.Event()

    def rpc(self, method, **params):
        url = self.base + method + '?' + urllib.parse.urlencode(params)
        with urllib.request.urlopen(url, timeout=60) as r:
            d = json.load(r)
        if 'error' in d:
            raise RuntimeError(d['error'])
        return d['result']

    def collect(self, iso, since):
        now = self.rpc('getVMTimelineMicros')['timestamp']
        data = self.rpc('getCpuSamples', isolateId=iso, timeOriginMicros=since,
                        timeExtentMicros=now - since)
        self.period = data.get('samplePeriod', self.period)
        names = []
        for f in data.get('functions', []):
            fn = f.get('function', {})
            owner = (fn.get('owner') or {}).get('name')
            name = f'{owner}.{fn.get("name")}' if owner and owner != fn.get('name') else fn.get('name')
            url = (f.get('resolvedUrl') or ((fn.get('location') or {}).get('script') or {}).get('uri')
                   or '')
            names.append((name or '?', 'package:morph/' in url or '/morph/lib/' in url))
        for smp in data.get('samples', []):
            self.samples.append((smp['timestamp'], [names[i] for i in smp.get('stack', [])]))
        return now

    def run(self):
        try:
            self.rpc('setFlag', name='profile_period', value='250')
            self.rpc('setFlag', name='profiler', value='true')
            vm = self.rpc('getVM')
            iso = next(i['id'] for i in vm['isolates'] if i['name'] == 'main')
            since = self.rpc('getVMTimelineMicros')['timestamp']
            while not self.stop.wait(2):
                since = self.collect(iso, since)
            self.collect(iso, since)
        except Exception as e:
            log('sampler:', e)

    def finish(self, path):
        self.stop.set()
        self.join(10)
        adb('forward', '--remove', f'tcp:{self.port}', check=False)
        json.dump({'period_us': self.period, 'samples': self.samples}, open(path, 'w'))


def launch(name, suite, args, out_dir, trace_dir, done_timeout, cpu=False):
    _, report, _ = SUITES[suite]
    sh(f'am force-stop {PKG}; rm -rf {FILES}/{report}/report.json {FILES}/{report}/error.json')
    local_args = os.path.join(trace_dir, f'{name}.args.json')
    json.dump(args, open(local_args, 'w'))
    adb('push', local_args, f'{FILES}/bench-args.json')
    adb('push', os.path.join(HERE, 'trace.cfg'), '/data/local/tmp/bench.cfg')
    sh('rm -f /data/misc/perfetto-traces/bench.pftrace')
    pid = sh('cat /data/local/tmp/bench.cfg | perfetto --txt -c - '
             '-o /data/misc/perfetto-traces/bench.pftrace --background').strip().splitlines()[-1]
    state['perfetto'] = pid
    time.sleep(2)
    adb('logcat', '-c')
    started = time.time()
    adb('shell', 'am', 'start', '-W', '-n', f'{PKG}/.MainActivity')
    watcher = subprocess.Popen(['adb', '-s', state['serial'], 'logcat', '-v', 'raw', '-s',
                                'flutter:I'], stdout=subprocess.PIPE, text=True)
    done = sampler = None
    try:
        while time.time() - started < done_timeout:
            line = watcher.stdout.readline()
            if not line:
                break
            if cpu and sampler is None and 'VM service' in line and 'http://' in line:
                sampler = DartSampler(re.search(r'(http://\S+)', line).group(1))
                sampler.start()
            if 'MORPH_BENCH_DONE' in line:
                done = line.split('MORPH_BENCH_DONE', 1)[1].strip()
                break
    finally:
        watcher.kill()
    if sampler is not None:
        sampler.finish(os.path.join(trace_dir, f'{name}.cpu.json'))
    elapsed = time.time() - started
    sh(f'kill -TERM {pid}')
    for _ in range(60):
        if not sh(f'kill -0 {pid} 2>/dev/null && echo up; true').strip():
            break
        time.sleep(1)
    state['perfetto'] = None
    trace = os.path.join(trace_dir, f'{name}.pftrace')
    adb('pull', '/data/misc/perfetto-traces/bench.pftrace', trace, timeout=300)
    sh(f'rm -f {FILES}/bench-args.json')
    if done is None:
        raise SystemExit(f'{name}: no MORPH_BENCH_DONE within {done_timeout} s')
    adb('pull', done, os.path.join(out_dir, f'{name}.report.json'))
    sh(f'am force-stop {PKG}')
    if done.endswith('error.json'):
        raise SystemExit(f'{name}: the bench failed, see {out_dir}/{name}.report.json')
    log(f'{name}: {elapsed:.0f} s')
    return trace


def fmt(v, digits=1):
    return '-' if v is None else f'{v:.{digits}f}'


def table(results, baseline):
    head = (f'{"scene":34} {"fr":>4} {"ui50":>5} {"ui95":>5} {"ra50":>5} {"ra95":>5} '
            f'{"gpu95":>5} {"over%":>5} {"drop":>4} {"mW":>5}  causes / where')
    lines = [head, '-' * len(head)]
    for key, s in results.items():
        base = baseline.get(key)
        delta = ''
        if base:
            parts = []
            for m in ('ui_p95', 'raster_p95', 'gpu_p95', 'over_pct', 'power_mw'):
                a, b = base.get(m), s.get(m)
                if m == 'over_pct' and a is None and base.get('frames'):
                    a = round(100 * base['over'] / base['frames'], 1)
                if a is None or b is None:
                    continue
                d = b - a
                rel = d / a if a else 0
                if (m == 'power_mw' and abs(d) >= 0.05 * a) or (m == 'over_pct' and abs(d) >= 1) or (
                        m not in ('power_mw', 'over_pct') and abs(d) >= 0.5 and abs(rel) >= 0.1):
                    parts.append(f'{m.replace("_p95", "")} {a:.4g}->{b:.4g}')
            delta = '  [' + ', '.join(parts) + ']' if parts else '  [=]'
        causes = ' '.join(f'{k}:{v}' for k, v in s['causes'].items())
        top = ''
        if s['causes']:
            first = next(iter(s['causes']))
            ui = s.get('bad_ui_phase_ms_per_frame') or s['ui_phase_ms_per_frame']
            raster = s.get('bad_raster_self_ms_per_frame') or s['raster_self_ms_per_frame']
            if first.startswith('ui') and ui:
                top = ' bad ui: ' + ', '.join(f'{k} {v:.1f}' for k, v in list(ui.items())[:3])
            elif raster:
                top = ' bad raster: ' + ', '.join(f'{k} {v:.1f}' for k, v in
                                                 list(raster.items())[:3])
        warm = ' WARM' if s.get('thermal_status') else ''
        lines.append(f'{key[:34]:34} {s["frames"]:>4} {fmt(s["ui_p50"]):>5} {fmt(s["ui_p95"]):>5} '
                     f'{fmt(s["raster_p50"]):>5} {fmt(s["raster_p95"]):>5} {fmt(s["gpu_p95"]):>5} '
                     f'{s.get("over_pct", 0):>5.1f} {s["dropped"]:>4} {fmt(s["power_mw"], 0):>5}  '
                     f'{causes}{top}{warm}{delta}')
        if s.get('dart', {}).get('morph_inclusive_ms'):
            d = s['dart']
            lines.append(f'{"":34}   dart ({d["samples"]} samples): ' + ', '.join(
                f'{k} {v:.0f}' for k, v in list(d['morph_inclusive_ms'].items())[:4]) + ' ms')
        if layers := s.get('layers'):
            lines.append(f'{"":34}   passes/frame: {s.get("save_layers_per_frame", 0):.1f} '
                         f'({layers["backdrops_per_frame"]:.1f} backdrop, '
                         f'{layers["offscreen_per_frame"] - layers["backdrops_per_frame"]:.1f} '
                         f'other layers, {layers["in_picture_save_layers"]:.1f} inside pictures): '
                         + ', '.join(f'{k[:60]} {v:.1f}' for k, v in
                                     list(layers['owners_per_frame'].items())[:4]))
        # A stall only the profiled launch shows is the sampler's.
        stalls = s.get('dart', {}).get('stalls', []) if (s.get('ui_max') or 0) > 4 * s['budget_ms'] else []
        for stall in stalls[:2]:
            lines.append(f'{"":34}   stall {stall["ms"]:.0f} ms: ' + ', '.join(
                f'{k} {v:.0f}' for k, v in list(stall['self_ms'].items())[:3]))
    return '\n'.join(lines)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--rev')
    p.add_argument('--suite', default='audit,nav')
    p.add_argument('--tiers', default='liquid,flat')
    p.add_argument('--scenes', default='')
    p.add_argument('--motions', default='enter,nested-push,nested-pop,toolbar,steady')
    p.add_argument('--runs', type=int)
    p.add_argument('--idle', type=int, default=8)
    p.add_argument('--fixed', action='store_true')
    p.add_argument('--label')
    p.add_argument('--sdk', default='stable', choices=['stable', 'beta'])
    p.add_argument('--no-build', action='store_true')
    p.add_argument('--no-cpu', action='store_true')
    p.add_argument('--save-baseline', action='store_true')
    p.add_argument('--serial', default='26221JEGR12737')
    p.add_argument('--cool-wait', type=int, default=300)
    p.add_argument('--timeout', type=int, default=900)
    p.add_argument('--lock-wait', type=int, default=7200)
    o = p.parse_args()
    if o.runs is None:
        o.runs = 5 if o.scenes else 3
    state['serial'] = o.serial
    suites = [s for s in o.suite.split(',') if s]
    tiers = [t for t in o.tiers.split(',') if t]
    py = ensure_venv()
    src, sha = source(o.rev)
    label = o.label or sha
    trace_dir = f'/tmp/morph-perf/bench/{label}'
    apk_dir = f'/tmp/morph-perf/bench/apk/{sha}-{o.sdk}'
    out_dir = os.path.join(ROOT, 'tool/ios_reference/perf',
                           f'{datetime.date.today()}-bench-{label}')
    os.makedirs(trace_dir, exist_ok=True)
    os.makedirs(out_dir, exist_ok=True)

    for suite in suites:
        apk = f'{apk_dir}/{suite}.apk'
        if not (o.no_build and os.path.exists(apk)):
            build(src, suite, apk, o.sdk)

    atexit.register(cleanup)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda *_: sys.exit(130))
    take_lock(o.lock_wait)
    if o.fixed:
        sh('cmd power set-fixed-performance-mode-enabled true')
        state['fixed'] = True

    plan = []
    if 'audit' in suites:
        for tier in tiers:
            args = {'GALLERY_GLASS': tier, 'AUDIT_RUNS': str(o.runs), 'AUDIT_SHOTS': 'false',
                    'AUDIT_IDLE_S': str(o.idle)}
            if o.scenes:
                args['AUDIT_SCENES'] = o.scenes
            plan.append((f'audit-{tier}', 'audit', args, f'audit/{tier}'))
    if 'nav' in suites:
        plan.append(('nav', 'nav', {'NAV_MODES': ','.join(tiers), 'NAV_MOTIONS': o.motions,
                                    'NAV_RUNS': str(o.runs)}, 'nav'))

    results = {}
    meta = {'sdk': o.sdk, 'sha': sha, 'source': src, 'fixed': o.fixed, 'runs': o.runs,
            'date': str(datetime.datetime.now()), 'launches': {}}
    installed = None
    for name, suite, args, prefix in plan:
        if installed != suite:
            adb('install', '-r', '-d', f'{apk_dir}/{suite}.apk', timeout=300)
            installed = suite
        status, skin = wait_cool(o.cool_wait)
        trace = launch(name, suite, args, out_dir, trace_dir, o.timeout)
        after = thermal()
        meta['launches'][name] = {'args': args, 'thermal_before': [status, skin],
                                  'thermal_after': list(after)}
        analysis = os.path.join(out_dir, f'{name}.analysis.json')
        subprocess.run([py, os.path.join(HERE, 'analyze.py'), trace, '--json', analysis],
                       check=True, stdout=subprocess.DEVNULL)
        data = json.load(open(analysis))
        for scene, s in data['scenes'].items():
            s['thermal_status'] = status
            results[f'{prefix}/{scene}'] = s

    def needs_diagnosis(key):
        return sum(results[key]['causes'].values()) >= 2

    for name, suite, args, prefix in ([] if o.no_cpu else plan):
        keys = [k for k in results if k.startswith(prefix + '/') and needs_diagnosis(k)]
        scenes = [k[len(prefix) + 1:] for k in keys]
        scenes = [x for x in scenes if not x.startswith('idle') and x != 'first-enter']
        if not scenes:
            continue
        args = dict(args)
        if suite == 'audit':
            args.update(AUDIT_SCENES=','.join(scenes), AUDIT_IDLE_S='0',
                        AUDIT_CENSUS='true', AUDIT_CENSUS_OWNERS='true')
        else:
            parts = [x.split('-', 2)[2].rsplit('-', 1) for x in scenes if x.count('-') >= 3]
            if not parts:
                continue
            args.update(NAV_MOTIONS=','.join(dict.fromkeys(m for m, _ in parts)),
                        NAV_MODES=','.join(dict.fromkeys(t for _, t in parts)))
        if installed != suite:
            adb('install', '-r', '-d', f'{apk_dir}/{suite}.apk', timeout=300)
            installed = suite
        log(f'{name}: diagnostic pass (Dart CPU, layer owners) over', ', '.join(scenes))
        cname = f'{name}-cpu'
        trace = launch(cname, suite, args, out_dir, trace_dir, o.timeout, cpu=True)
        samples = os.path.join(trace_dir, f'{cname}.cpu.json')
        if not os.path.exists(samples):
            log(f'{cname}: no samples')
            continue
        analysis = os.path.join(out_dir, f'{cname}.analysis.json')
        subprocess.run([py, os.path.join(HERE, 'analyze.py'), trace, '--json', analysis,
                        '--cpu', samples, '--report', os.path.join(out_dir, f'{cname}.report.json')],
                       check=True, stdout=subprocess.DEVNULL)
        census = json.load(open(os.path.join(out_dir, f'{cname}.report.json'))).get('census', {})
        for scene, s in json.load(open(analysis))['scenes'].items():
            key = f'{prefix}/{scene}'
            if key not in keys:
                continue
            if 'dart' in s:
                results[key]['dart'] = s['dart']
            if scene in census:
                c = census[scene]
                results[key]['layers'] = {
                    'offscreen_per_frame': round(c['mean']['offscreen'], 2),
                    'backdrops_per_frame': round(c['mean']['backdrop'], 2),
                    'in_picture_save_layers': round(
                        max(0.0, s.get('save_layers_per_frame', 0) - c['mean']['offscreen']), 2),
                    'owners_per_frame': {k: round(v, 2) for k, v in
                                         list(c.get('owners', {}).items())[:12]},
                }
    json.dump(meta, open(os.path.join(out_dir, 'meta.json'), 'w'), indent=1)
    json.dump(results, open(os.path.join(out_dir, 'results.json'), 'w'), indent=1)

    baseline_path = os.path.join(HERE, 'baseline.json')
    baseline = json.load(open(baseline_path))['scenes'] if os.path.exists(baseline_path) else {}
    text = table(results, baseline)
    header = f'{sha}  runs {o.runs}  fixed-perf {o.fixed}  {meta["date"][:16]}'
    open(os.path.join(out_dir, 'summary.txt'), 'w').write(header + '\n\n' + text + '\n')
    print(header)
    print(text)
    if o.save_baseline:
        json.dump({'sha': sha, 'date': meta['date'], 'fixed': o.fixed, 'scenes': results},
                  open(baseline_path, 'w'), indent=1)
        log('saved', baseline_path)
    log('results in', out_dir)


if __name__ == '__main__':
    main()
