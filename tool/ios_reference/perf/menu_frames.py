#!/usr/bin/env python3
"""One row per frame of a menu_frames_test report.

    menu_frames.py <report.json> [budget_ms] [--all]

Joins each run's FrameTimings (engine clock), the framework's
FlutterTimeline blocks and the VM timeline (Dart, GC, Embedder streams,
both on the Dart timeline clock - the same monotonic clock on Android and
iOS) and the run's marks. Prints the frames over the budget (default: the
report's refresh rate) with their phase split, the GC work inside their
build window and the last mark before them; then, per run, the active
frame percentiles; then the frames over budget grouped by the phase of the
scene they fall in, and every active frame by that phase. Besides the frames over budget it prints the
--top=N (6) heaviest builds of each run; --all prints every active frame.
"""
import collections
import json
import sys

PHASES = ['Animate', 'BUILD', 'LAYOUT', 'UPDATING COMPOSITING BITS', 'PAINT',
          'COMPOSITING', 'SEMANTICS', 'FINALIZE TREE', 'POST_FRAME']
SHORT = {'Animate': 'anim', 'BUILD': 'build', 'LAYOUT': 'layout',
         'UPDATING COMPOSITING BITS': 'bits', 'PAINT': 'paint',
         'COMPOSITING': 'comp', 'SEMANTICS': 'sem', 'FINALIZE TREE': 'fin',
         'POST_FRAME': 'post'}


def pick(values, q):
    v = sorted(values)
    return v[min(len(v) - 1, int(len(v) * q))] if v else 0.0


def gc_slices(events):
    out = []
    open_ = {}
    for ph, name, ts, dur, tid, cat in events:
        if 'GC' not in cat:
            continue
        if ph == 'X':
            out.append((ts, ts + (dur or 0), name, tid))
        elif ph == 'B':
            open_.setdefault((tid, name), []).append(ts)
        elif ph == 'E':
            stack = open_.get((tid, name))
            if stack:
                out.append((stack.pop(), ts, name, tid))
    return out


def other_slices(events):
    out = []
    open_ = {}
    for ph, name, ts, dur, tid, cat in events:
        if 'GC' in cat or name in SHORT:
            continue
        if ph == 'X':
            out.append((ts, ts + (dur or 0), name, tid))
        elif ph == 'B':
            open_.setdefault((tid, name), []).append(ts)
        elif ph == 'E':
            stack = open_.get((tid, name))
            if stack:
                out.append((stack.pop(), ts, name, tid))
    return out


def scene_phase(marks, t):
    last = None
    for mt, what in marks:
        if mt <= t:
            last = (mt, what)
    if last is None:
        return 'before', 0.0
    return last[1], (t - last[0]) / 1000


def main():
    path = sys.argv[1]
    report = json.load(open(path))
    rate = report.get('refresh_rate') or 60
    budget = float(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2][0] != '-' else 1000 / rate
    show_all = '--all' in sys.argv
    top = next((int(a[6:]) for a in sys.argv if a.startswith('--top=')), 6)
    print(f"tier {report['tier']} platform {report['platform']} rate {rate} budget {budget:.2f} detail {report.get('detail')}")
    by_phase = collections.defaultdict(list)
    all_by_phase = collections.defaultdict(list)
    summary = []
    for ri, run in enumerate(report['runs']):
        marks = run['marks']
        blocks = run['blocks']
        gcs = gc_slices(run['events'])
        others = other_slices(run['events'])
        if run.get('trace_error'):
            print('trace error:', run['trace_error'])
        rows = []
        for vs, bs, bf, rs, rf, n in run['timings']:
            b = (bf - bs) / 1000
            r = (rf - rs) / 1000
            if b <= 0.3 and r <= 0.3:
                continue
            ph = collections.defaultdict(float)
            for name, s, e in blocks:
                if bs <= s <= bf:
                    for p in PHASES:
                        if name == p:
                            ph[p] += (e - s) / 1000
            gc = [(name, (min(e, bf) - max(s, bs)) / 1000) for s, e, name, tid in gcs if s < bf and e > bs]
            gc_ms = sum(d for _, d in gc)
            heavy = sorted(((e - s) / 1000, name) for s, e, name, tid in others if bs <= s <= bf and (e - s) >= 1000)
            what, since = scene_phase(marks, bs)
            rows.append(dict(n=n, b=b, r=r, ph=ph, gc=gc, gc_ms=gc_ms, what=what, since=since, heavy=heavy[-3:], vs=vs))
        build = [x['b'] for x in rows]
        raster = [x['r'] for x in rows]
        over = [x for x in rows if x['b'] > budget or x['r'] > budget]
        summary.append((len(rows), pick(build, .5), pick(build, .95), max(build or [0]), pick(raster, .5), pick(raster, .95), len(over),
                        len([x for x in rows if x['b'] > budget]), len([x for x in rows if x['r'] > budget])))
        print(f'\n== run {ri}: {len(rows)} active, {len(over)} over')
        shown = set(id(x) for x in rows) if show_all else (set(id(x) for x in over) | set(id(x) for x in sorted(rows, key=lambda x: -x['b'])[:top]))
        for x in [x for x in rows if id(x) in shown]:
            phs = ' '.join(f"{SHORT[p]} {x['ph'][p]:.1f}" for p in PHASES if x['ph'][p] >= 0.1)
            gc = ' '.join(f'{n} {d:.1f}' for n, d in x['gc'] if d >= 0.05)
            heavy = ', '.join(f'{n} {d:.1f}' for d, n in x['heavy'])
            flag = ('B' if x['b'] > budget else '-') + ('R' if x['r'] > budget else '-')
            print(f"{flag} #{x['n']:5d} build {x['b']:5.1f} raster {x['r']:5.1f} | {phs} | gc {x['gc_ms']:.1f} {gc} | {x['what']} +{x['since']:.0f} ms | {heavy}")
        for x in rows:
            key = x['what'] if x['since'] < 1000 else x['what'] + ' (late)'
            all_by_phase[key].append(x)
            if x in over:
                by_phase[key].append(x)
    print('\nrun: active build p50 p95 worst | raster p50 p95 | over (build, raster)')
    for i, s in enumerate(summary):
        print(f'{i}: {s[0]} {s[1]:.1f} {s[2]:.1f} {s[3]:.1f} | {s[4]:.1f} {s[5]:.1f} | {s[6]} ({s[7]}, {s[8]})')
    if summary:
        med = [pick([s[k] for s in summary], .5) for k in range(9)]
        print(f'median: {med[0]:.0f} build {med[1]:.1f} {med[2]:.1f} {med[3]:.1f} | raster {med[4]:.1f} {med[5]:.1f} | over {med[6]:.0f} ({med[7]:.0f}, {med[8]:.0f})')
    print('\nactive frames by scene phase (all runs): build and raster p50 / p95 / max')
    for key, xs in sorted(all_by_phase.items(), key=lambda kv: -len(kv[1])):
        b = [x['b'] for x in xs]
        r = [x['r'] for x in xs]
        print(f"{key:40s} {len(xs):4d}  build {pick(b, .5):5.1f} {pick(b, .95):5.1f} {max(b):5.1f}  raster {pick(r, .5):5.1f} {pick(r, .95):5.1f} {max(r):5.1f}")
    print('\nover-budget frames by scene phase (all runs): count, build-over, raster-over, gc-in-build')
    for key, xs in sorted(by_phase.items(), key=lambda kv: -len(kv[1])):
        print(f"{key:40s} {len(xs):4d} {sum(x['b'] > budget for x in xs):4d} {sum(x['r'] > budget for x in xs):4d} {sum(x['gc_ms'] > 0.5 for x in xs):4d}")


main()
