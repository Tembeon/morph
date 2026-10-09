#!/usr/bin/env python3
"""Install a nav bench APK, run it, pull the report; optional Dart CPU samples.
usage: run.py SERIAL APK OUTBASE [--cpu] [--gpu] [--skia] [--hz | --60] [--real]"""
import json, re, subprocess, sys, time, urllib.parse, urllib.request, os
serial, apk, out = sys.argv[1:4]
cpu = '--cpu' in sys.argv
PKG = 'dev.tembeon.morph_example'
DEV = f'/sdcard/Android/data/{PKG}/files/stage-bench'
env = dict(os.environ, ANDROID_SERIAL=serial)
def adb(*a, check=True):
    r = subprocess.run(['adb', *a], env=env, capture_output=True, text=True, timeout=120)
    if check and r.returncode: raise RuntimeError(f'{a}: {r.stderr}')
    return r.stdout
adb('install', '-r', '-d', apk)
adb('shell', 'am', 'force-stop', PKG)
adb('shell', 'rm', '-f', f'{DEV}/report.json', f'{DEV}/error.json')
adb('logcat', '-c')
gpu = '--gpu' in sys.argv
recorder = None
TR = '/sys/kernel/tracing'
if gpu:
    state = [adb('shell', 'cat', f'{TR}/{n}').strip() for n in ('tracing_on', 'events/power/gpu_work_period/enable')]
    if state != ['0', '0']:
        raise SystemExit('kernel GPU tracing already in use')
    adb('shell', f'cd {TR} && echo mono > trace_clock && echo 8192 > buffer_size_kb && echo > trace && '
        'echo 1 > events/power/gpu_work_period/enable && echo 1 > events/power/gpu_frequency/enable && echo 1 > tracing_on')
    gpu_file = open(out + '.gpuwork.txt', 'w')
    recorder = subprocess.Popen(['adb', 'shell', 'cat', f'{TR}/trace_pipe'], env=env, stdout=gpu_file, stderr=subprocess.DEVNULL)
tapper = None
if '--real' in sys.argv:
    # The bench (NAV_REAL_INPUT) logs NAVTAP x y / NAVKEY code when an
    # action should start; answering with real input gives the action the
    # platform's input boost, as a user's touch would.
    tapper = subprocess.Popen(['adb', 'logcat', '-v', 'raw', '-s', 'flutter:I'], env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    import threading
    def answer():
        for line in tapper.stdout:
            parts = line.split()
            if len(parts) == 3 and parts[0] == 'NAVTAP':
                subprocess.run(['adb', 'shell', 'input', 'tap', parts[1], parts[2]], env=env)
            elif len(parts) == 2 and parts[0] == 'NAVKEY':
                subprocess.run(['adb', 'shell', 'input', 'keyevent', parts[1]], env=env)
    threading.Thread(target=answer, daemon=True).start()
adb('shell', 'am', 'start', '-W', '-n', f'{PKG}/.MainActivity', *(['--ez', 'trace-skia', 'true'] if '--skia' in sys.argv else []), *(['--ez', 'morph-max-refresh', 'true'] if '--hz' in sys.argv else []), *(['--ef', 'morph-frame-rate', '60'] if '--60' in sys.argv else []))
time.sleep(2)
pid = adb('shell', 'pidof', PKG).split()[0]
base = None; port = None
def rpc(method, **p):
    with urllib.request.urlopen(base + method + '?' + urllib.parse.urlencode(p), timeout=120) as r:
        d = json.load(r)
    if 'error' in d: raise RuntimeError(d['error'])
    return d['result']
if cpu:
    for _ in range(20):
        log = adb('logcat', '-d', f'--pid={pid}')
        m = re.findall(r'(http://127\.0\.0\.1:\d+/[^\s]+)', log)
        if m: break
        time.sleep(1)
    u = urllib.parse.urlparse(m[-1])
    port = adb('forward', 'tcp:0', f'tcp:{u.port}').strip()
    base = f'http://127.0.0.1:{port}{u.path}'
    rpc('setFlag', name='profile_period', value='250')
    rpc('setFlag', name='profiler', value='true')
    rpc('setVMTimelineFlags', recordedStreams='[Dart,Embedder,GC]')
t0 = time.time()
while True:
    r = subprocess.run(['adb', 'shell', f'test -f {DEV}/report.json && echo ok; test -f {DEV}/error.json && cat {DEV}/error.json'], env=env, capture_output=True, text=True)
    if 'ok' in r.stdout: break
    if r.stdout.strip(): raise SystemExit('bench error: ' + r.stdout)
    if time.time() - t0 > 1800: raise SystemExit('timeout')
    time.sleep(3)
time.sleep(1)
if cpu:
    vm = rpc('getVM')
    iso = next(i['id'] for i in vm['isolates'] if i['name'] == 'main')
    tl = rpc('getVMTimeline')
    open(out + '.timeline.json', 'w').write(json.dumps(tl))
    data = rpc('getCpuSamples', isolateId=iso, timeOrigin=0, timeExtent=rpc('getVMTimelineMicros')['timestamp'])
    open(out + '.cpu.json', 'w').write(json.dumps(data))
    adb('forward', '--remove', f'tcp:{port}')
if gpu:
    adb('shell', f'echo 0 > {TR}/tracing_on')
    recorder.terminate(); recorder.wait()
    gpu_file.close()
    adb('shell', f'cd {TR} && echo 0 > events/power/gpu_work_period/enable && echo 0 > events/power/gpu_frequency/enable && echo > trace && echo local > trace_clock')
    open(out + '.device.txt', 'w').write(adb('shell', 'pm', 'list', 'packages', '-U', PKG))
if tapper:
    tapper.terminate()
adb('pull', f'{DEV}/report.json', out + '.json')
open(out + '.log.txt', 'w').write(adb('logcat', '-d', f'--pid={pid}'))
print('ok', out)
