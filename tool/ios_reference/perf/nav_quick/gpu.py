#!/usr/bin/env python3
"""GPU cost per frame of navigation runs recorded with run.py --gpu.

usage: gpu.py <base> [<base> ...]   (base = run.py's out, without suffix)

Prints, per case, the median over the report's repeats of the app's GPU
active ms and Mcycles per frame (gpu_work_period prorated over each
measured window, frequency integrated). Mcycles is the comparable number:
the GPU's DVFS keeps active ms near constant while the clock moves.
"""
import json
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'stage_bench'))
from summarize import gpu_cost, load_gpu  # noqa: E402

for base in sys.argv[1:]:
    report = json.loads(Path(base + '.json').read_text())
    gpu = load_gpu(Path(base))
    if gpu is None:
        raise SystemExit(f'{base}: no GPU trace')
    print(base)
    for name, windows in report['windows_us'].items():
        runs = report[name]['runs']
        ms, mc = [], []
        for run, (start, end) in zip(runs, windows):
            active, cycles, events = gpu_cost(*gpu, start * 1000, end * 1000)
            if not events:
                continue
            ms.append(active / run['n'] / 1e6)
            if cycles is not None:
                mc.append(cycles / run['n'] / 1e6)
        f = lambda v: f'{statistics.median(v):6.2f}' if v else '     -'
        print(f'  {name:42s} gpu_ms {f(ms)}  Mcycles {f(mc)}')
