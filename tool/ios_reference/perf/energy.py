#!/usr/bin/env python3
"""Energy per audit scene from energy_android.sh launches.

    energy.py <dir> [--json out.json]

Every <dir>/<variant>-<i>.pftrace is read with Perfetto's trace processor
(pip install perfetto). The report <variant>-<i>.json carries the scene
windows (windows_us, CLOCK_MONOTONIC); per window the cumulative ODPM rail
counters give the energy (linear between samples, mJ), the cpufreq tracks
the time-weighted frequency per cluster, the sched table the busy share of
each cluster and where the app's UI (main) and raster threads ran; the skin
temperature before and after the launch comes from <variant>-<i>.device.txt.
Per variant and scene: medians over the launches, and every launch. The per-launch results are kept next to
each trace (<variant>-<i>.energy.json) and read from there when the trace
is gone, so a committed evidence directory reprints without its traces.
"""
import collections
import glob
import json
import os
import re
import statistics
import sys

from perfetto.trace_processor import TraceProcessor

CLUSTERS = {'little': range(0, 4), 'mid': range(4, 6), 'big': range(6, 8)}
PKG = 'dev.tembeon.morph_example'


def interp(samples, t):
    if not samples:
        return None
    if t <= samples[0][0]:
        return samples[0][1]
    if t >= samples[-1][0]:
        return samples[-1][1]
    lo, hi = 0, len(samples) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if samples[mid][0] <= t:
            lo = mid
        else:
            hi = mid
    (t0, v0), (t1, v1) = samples[lo], samples[hi]
    return v0 + (v1 - v0) * (t - t0) / (t1 - t0) if t1 > t0 else v0


def step_mean(samples, a, b):
    """Time-weighted mean of a step counter over [a, b)."""
    if not samples:
        return None
    total = 0.0
    value = samples[0][1]
    for t, v in samples:
        if t > a:
            break
        value = v
    last = a
    for t, v in samples:
        if t <= a:
            continue
        if t >= b:
            break
        total += value * (t - last)
        last, value = t, v
    total += value * (b - last)
    return total / (b - a)


def analyze(trace, report):
    tp = TraceProcessor(trace=trace)
    q = lambda sql: list(tp.query(sql))
    snap = {}
    for r in q("select snapshot_id, clock_id, clock_value from clock_snapshot"):
        snap.setdefault(r.snapshot_id, {})[r.clock_id] = r.clock_value
    offs = [s[6] - s[3] for s in snap.values() if 6 in s and 3 in s]
    mono_to_trace = statistics.median(offs) if offs else 0
    rails = collections.defaultdict(list)
    for r in q("""select t.name as name, c.ts as ts, c.value as value from counter c
                  join counter_track t on c.track_id = t.id
                  where t.name like 'power.%' order by c.ts"""):
        rails[r.name].append((r.ts, r.value))
    rails = {k: v for k, v in rails.items() if 'rails' in k}
    freq = collections.defaultdict(list)
    for r in q("""select t.cpu as cpu, c.ts as ts, c.value as value from counter c
                  join cpu_counter_track t on c.track_id = t.id
                  where t.name = 'cpufreq' order by c.ts"""):
        freq[r.cpu].append((r.ts, r.value))
    upid = q(f"select upid, pid from process where name like '{PKG}%' order by upid desc limit 1")
    threads = {}
    if upid:
        pid = upid[0].pid
        for r in q(f"select utid, tid, name from thread where upid = {upid[0].upid}"):
            if r.tid == pid:
                threads['ui'] = r.utid
            elif r.name and r.name.endswith('.raster'):
                threads['raster'] = r.utid
            elif r.name and 'DartWorker' in r.name:
                threads.setdefault('workers', []).append(r.utid)
    out = {}
    windows = dict(report.get('windows_us', {}))
    for scene, ws in windows.items():
        for k, (a_us, b_us) in enumerate(ws):
            if b_us <= a_us:
                continue
            a = a_us * 1000 + mono_to_trace
            b = b_us * 1000 + mono_to_trace
            sec = (b - a) / 1e9
            row = {'s': sec, 'rails_mj': {}}
            for name, s in rails.items():
                va, vb = interp(s, a), interp(s, b)
                if va is not None:
                    row['rails_mj'][short(name)] = (vb - va) / 1000
            row['total_mj'] = sum(row['rails_mj'].values())
            row['freq_mhz'] = {}
            for cl, cpus in CLUSTERS.items():
                m = step_mean(freq.get(cpus[0], []), a, b)
                row['freq_mhz'][cl] = m / 1000 if m else None
            busy = {cl: 0 for cl in CLUSTERS}
            for r in q(f"""select cpu, sum(min(ts + dur, {b}) - max(ts, {a})) as d from sched
                           where utid != 0 and ts < {b} and ts + dur > {a} group by cpu"""):
                for cl, cpus in CLUSTERS.items():
                    if r.cpu in cpus:
                        busy[cl] += r.d / ((b - a) * len(cpus))
            row['busy'] = busy
            place = {}
            for role, utid in threads.items():
                ids = utid if isinstance(utid, list) else [utid]
                if not ids:
                    continue
                per = {cl: 0.0 for cl in CLUSTERS}
                for r in q(f"""select cpu, sum(min(ts + dur, {b}) - max(ts, {a})) as d from sched
                               where utid in ({','.join(map(str, ids))}) and ts < {b} and ts + dur > {a}
                               group by cpu"""):
                    for cl, cpus in CLUSTERS.items():
                        if r.cpu in cpus:
                            per[cl] += r.d / 1e6
                place[role] = per
            row['thread_ms'] = place
            out.setdefault(scene, []).append(row)
    meta = {'rails': sorted(short(n) for n in rails),
            'threads': {k: (v if not isinstance(v, list) else len(v)) for k, v in threads.items()},
            'mono_to_trace_ns': mono_to_trace}
    tp.close()
    return out, meta


def skins(path):
    try:
        return [float(x) for x in re.findall(r'^skin: ([0-9.]+)', open(path).read(), re.M)]
    except OSError:
        return []


def short(name):
    return re.sub(r'^power\.rails\.', '', re.sub(r'^power\.', '', name))


def frames(report, scene):
    s = report.get(scene)
    if not isinstance(s, dict):
        return {}
    m = s['median']
    return {k: m.get(k) for k in ('build_p95', 'raster_p95', 'over_budget')}


def main():
    d = sys.argv[1]
    rows = collections.defaultdict(lambda: collections.defaultdict(list))
    metas = {}
    names = {p[:-8] for p in glob.glob(os.path.join(d, '*.pftrace'))}
    names |= {p[:-12] for p in glob.glob(os.path.join(d, '*.energy.json'))}
    for base in sorted(names):
        trace = base + '.pftrace'
        run = os.path.basename(base)
        variant = run.rsplit('-', 1)[0]
        cache = trace[:-8] + '.energy.json'
        report = json.load(open(trace[:-8] + '.json'))
        if os.path.exists(cache):
            data = json.load(open(cache))
            out, meta = data['out'], data['meta']
        else:
            out, meta = analyze(trace, report)
            json.dump({'out': out, 'meta': meta}, open(cache, 'w'), indent=1)
        metas[run] = meta
        for scene, ws in out.items():
            total = {
                's': sum(w['s'] for w in ws),
                'total_mj': sum(w['total_mj'] for w in ws),
                'rails_mj': {k: sum(w['rails_mj'].get(k, 0) for w in ws) for k in ws[0]['rails_mj']},
                'freq_mhz': {cl: statistics.mean([w['freq_mhz'][cl] for w in ws if w['freq_mhz'][cl]] or [0])
                             for cl in CLUSTERS},
                'busy': {cl: statistics.mean([w['busy'][cl] for w in ws]) for cl in CLUSTERS},
                'thread_ms': {role: {cl: sum(w['thread_ms'].get(role, {}).get(cl, 0) for w in ws) for cl in CLUSTERS}
                              for role in ws[0]['thread_ms']},
                'skin_c': skins(trace[:-8] + '.device.txt'),
                'frames': frames(report, scene),
                'adpf': report.get('adpf'),
                'served': (report.get('fusion_served_ahead'), report.get('fusion_fused_here')),
            }
            rows[variant][scene].append((run, total))
    first = next(iter(metas.values()), {})
    print('rails:', first.get('rails'), 'threads:', first.get('threads'))
    for variant in sorted(rows):
        print(f'\n== {variant}')
        for scene, runs in rows[variant].items():
            med = lambda f: statistics.median([f(t) for _, t in runs])
            print(f"{scene:12s} n={len(runs)} s={med(lambda t: t['s']):.1f} total {med(lambda t: t['total_mj']):.0f} mJ"
                  f" ({med(lambda t: t['total_mj'] / t['s']):.0f} mW) | " +
                  ' '.join(f"{k}={med(lambda t, k=k: t['rails_mj'].get(k, 0)):.0f}"
                           for k in sorted(runs[0][1]['rails_mj'])))
            for run, t in runs:
                f = t['frames']
                print(f"    {run:14s} {t['total_mj']:8.0f} mJ {t['s']:6.1f}s  freq L/M/B "
                      + '/'.join(f"{t['freq_mhz'][c]:.0f}" for c in CLUSTERS)
                      + '  busy ' + '/'.join(f"{t['busy'][c]:.2f}" for c in CLUSTERS)
                      + '  ui ms ' + '/'.join(f"{t['thread_ms'].get('ui', {}).get(c, 0):.0f}" for c in CLUSTERS)
                      + '  raster ms ' + '/'.join(f"{t['thread_ms'].get('raster', {}).get(c, 0):.0f}" for c in CLUSTERS)
                      + f"  b95 {f.get('build_p95') or 0:.2f} r95 {f.get('raster_p95') or 0:.2f} over {f.get('over_budget') or 0:.0f}"
                      + '  skin ' + '>'.join(f'{c:.1f}' for c in t['skin_c']))
    groups = {
        'cpu': ('rails.cpu.big', 'rails.cpu.mid', 'rails.cpu.little'),
        'gpu': ('rails.gpu',),
        'mem': ('rails.ddr.a', 'rails.ddr.b', 'rails.ddr.c', 'rails.memory.interface', 'rails.system.fabric'),
        'disp': ('rails.display',),
    }
    print('\nmedian per variant and scene: total mJ (mW) | cpu big/mid/little | gpu | mem | display | '
          'build p95 / raster p95 / over budget (median of launches) | n')
    scenes = []
    for v in rows.values():
        scenes += [s for s in v if s not in scenes]
    for scene in scenes:
        for variant in sorted(rows):
            runs = rows[variant].get(scene)
            if not runs:
                continue
            med = lambda f: statistics.median([f(t) for _, t in runs])
            rail = lambda t, names: sum(t['rails_mj'].get(n, 0) for n in names)
            f = lambda k: med(lambda t: t['frames'].get(k) or 0)
            print(f"{scene:12s} {variant:6s} {med(lambda t: t['total_mj']):7.0f} ({med(lambda t: t['total_mj'] / t['s']):5.0f}) | "
                  + '/'.join(f"{med(lambda t, c=c: t['rails_mj'].get(c, 0)):.0f}" for c in groups['cpu'])
                  + f" | {med(lambda t: rail(t, groups['gpu'])):6.0f} | {med(lambda t: rail(t, groups['mem'])):5.0f}"
                  + f" | {med(lambda t: rail(t, groups['disp'])):5.0f} | {f('build_p95'):.2f} / {f('raster_p95'):.2f} / {f('over_budget'):.0f}"
                  + f" | {len(runs)}")
    if '--json' in sys.argv:
        json.dump({v: {s: r for s, r in sc.items()} for v, sc in rows.items()},
                  open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)


if __name__ == '__main__':
    main()
