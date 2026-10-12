#!/usr/bin/env python3
"""Per-scene frame anatomy of one bench launch from its Perfetto trace.

    analyze.py <trace.pftrace> [--json out.json] [--cpu samples.json --report report.json]

The trace (tool/bench/bench.py) holds Flutter's and Dart's trace events
(profile builds forward them to systrace), the scheduler, CPU and GPU
frequency, the kernel's GPU work periods and the ODPM power rails. Scene windows come from the benches' own
`scene:<name>:<run>:begin|end` slices, so any bench that marks its scenes
is analyzed the same way.

Per scene: UI and raster frame times, GPU active time per frame, the
frames over the budget and the first limiter of each one, the UI phases
and the raster thread's self time by slice (where the CPU went), the share
of time the UI and raster threads waited for a CPU, the vsync slots the
app dropped (gaps between its queued buffers of 1.5 to 6 budgets: an
estimate, settles longer than that are not drops), CPU and GPU clocks and
the power of the rails.

With Dart CPU samples of the same launch (bench.py's sampler) and the
bench's report (its windows_us place the samples, CLOCK_MONOTONIC, on the
trace's clock), a scene also gets `dart`: the package's own functions by
inclusive time and every function by self time, over the UI frames put
down to the UI thread (all UI frames when none is).

A frame over budget is put down to the first of:
  gpu           GPU active time of the frame above 0.9 budget
  raster-wait   raster thread over budget, asleep for 40 %+ of it (fence,
                buffer or GPU wait)
  raster-sched  raster thread over budget, runnable without a CPU for 30 %+
  raster-cpu    raster thread over budget otherwise (encoding)
  ui-sched      UI thread over budget, runnable without a CPU for 30 %+
  ui-<phase>    UI thread over budget, by its largest phase (build, layout,
                paint, compositing, animate, other)
"""
import bisect
import collections
import json
import re
import statistics
import sys

from perfetto.trace_processor import TraceProcessor

PKG = 'dev.tembeon.morph_example'
UI_ROOTS = ('Animator::BeginFrame',)
RASTER_ROOTS = ('GPURasterizer::Draw', 'Rasterizer::DoDraw')
PHASES = {
    'BUILD': 'build',
    'LAYOUT (root)': 'layout',
    'LAYOUT': 'layout',
    'PAINT (root)': 'paint',
    'PAINT': 'paint',
    'COMPOSITING': 'compositing',
    'UPDATING COMPOSITING BITS (root)': 'compositing',
    'SEMANTICS (root)': 'semantics',
    'FINALIZE TREE': 'finalize',
    'Scavenge': 'gc',
    'CollectNewGeneration': 'gc',
    'CollectOldGeneration': 'gc',
    'StartConcurrentMarking': 'gc',
}
CLUSTERS = {'little': range(0, 4), 'mid': range(4, 6), 'big': range(6, 8)}


def q(tp, sql):
    return list(tp.query(sql))


def pct(values, p):
    if not values:
        return None
    s = sorted(values)
    return s[min(len(s) - 1, int(len(s) * p))]


def overlap(a0, a1, b0, b1):
    return max(0, min(a1, b1) - max(a0, b0))


class Intervals:
    """Sorted intervals with a value each; sums value-weighted overlap."""

    def __init__(self, rows):
        self.rows = sorted(rows)
        self.starts = [r[0] for r in self.rows]

    def total(self, a, b, weight=lambda row, ov: ov):
        i = max(0, bisect.bisect_left(self.starts, a) - 64)
        out = 0.0
        for row in self.rows[i:]:
            if row[0] >= b:
                break
            ov = overlap(row[0], row[1], a, b)
            if ov > 0:
                out += weight(row, ov)
        return out


def app_process(tp):
    rows = q(tp, f"select upid, pid, name from process where name like '{PKG}%' order by upid")
    if not rows:
        raise SystemExit('no app process in trace')
    return rows[-1].upid, rows[-1].pid


def threads(tp, upid, pid):
    """The UI thread (a `.ui` thread, or the platform thread when the
    engine merges them) and the busiest `.raster` thread."""
    out, busiest = {}, {}
    for r in q(tp, f'''select utid, tid, thread.name as name,
                         (select count(*) from thread_track t join slice s on s.track_id = t.id
                          where t.utid = thread.utid) as n
                       from thread where upid = {upid}'''):
        name = r.name or ''
        if name.endswith('.ui'):
            out['ui'] = r.utid
        elif name.endswith('.raster') and r.n > busiest.get('raster', -1):
            out['raster'], busiest['raster'] = r.utid, r.n
        elif r.tid == pid:
            out.setdefault('main', r.utid)
    if 'ui' not in out and 'main' in out:
        out['ui'] = out['main']
    return out


def slices_of(tp, utid):
    return q(tp, f'''
        select s.id, s.ts, s.dur, s.name, s.depth, s.parent_id
        from slice s join thread_track t on s.track_id = t.id
        where t.utid = {utid} and s.dur >= 0 order by s.ts''')


def scene_windows(tp, upid):
    rows = q(tp, f'''
        select s.ts, s.name from slice s
        join thread_track t on s.track_id = t.id
        join thread using (utid)
        where thread.upid = {upid} and s.name like 'scene:%' order by s.ts''')
    open_, out = {}, collections.defaultdict(list)
    for r in rows:
        parts = r.name.split(':')
        if len(parts) < 4:
            continue
        scene, run, edge = ':'.join(parts[1:-2]), parts[-2], parts[-1]
        if edge == 'begin':
            open_[(scene, run)] = r.ts
        elif edge == 'end' and (scene, run) in open_:
            out[scene].append((open_.pop((scene, run)), r.ts))
    return out


def thread_states(tp, utid):
    rows = q(tp, f'select ts, dur, state, cpu from thread_state where utid = {utid} and dur > 0')
    return Intervals([(r.ts, r.ts + r.dur, r.state, r.cpu) for r in rows])


def state_split(states, a, b):
    run = states.total(a, b, lambda r, ov: ov if r[2] == 'Running' else 0)
    runnable = states.total(a, b, lambda r, ov: ov if r[2] in ('R', 'R+') else 0)
    return run, runnable


def gpu_work(tp, upid):
    """The kernel's GPU work periods of the app's uid: slices on an
    android_gpu_work_period track, named by the active share ('%87.50')."""
    uid = None
    for r in q(tp, f'select uid, android_appid from process where upid = {upid}'):
        uid = r.uid or r.android_appid
    rows = q(tp, '''
        select s.ts, s.dur, s.name, extract_arg(t.dimension_arg_set_id, 'uid') as uid,
               extract_arg(t.dimension_arg_set_id, 'gpu') as gpu
        from slice s join track t on s.track_id = t.id
        where t.type = 'android_gpu_work_period' ''')
    periods = []
    for r in rows:
        if uid is not None and r.uid is not None and r.uid != uid:
            continue
        if r.dur > 0 and r.name.startswith('%'):
            periods.append((r.ts, r.ts + r.dur, int(r.dur * float(r.name[1:]) / 100)))
    return Intervals(periods), uid, len(periods)


def gpu_active(periods, a, b):
    return periods.total(a, b, lambda r, ov: r[2] * ov / (r[1] - r[0]))


def counter_rows(tp, where):
    return q(tp, f'''select c.ts, c.value, t.name as track from counter c
                     join counter_track t on c.track_id = t.id where {where} order by c.ts''')


def cpu_freq(tp):
    out = collections.defaultdict(list)
    for r in q(tp, '''select c.ts, c.value, t.cpu from counter c
                      join cpu_counter_track t on c.track_id = t.id
                      where t.name = 'cpufreq' order by c.ts'''):
        out[r.cpu].append((r.ts, r.value))
    return out


def step_mean(samples, a, b):
    if not samples:
        return None
    total, value, last = 0.0, samples[0][1], a
    for t, v in samples:
        if t <= a:
            value = v
            continue
        if t >= b:
            break
        total += value * (t - last)
        last, value = t, v
    total += value * (b - last)
    return total / (b - a) if b > a else value


def gpu_freq(tp):
    rows = q(tp, '''select c.ts, c.value from counter c join gpu_counter_track t on c.track_id = t.id
                    where t.name = 'gpufreq' order by c.ts''')
    return [(r.ts, r.value) for r in rows]


def busy_clock(samples, wins):
    """Time-weighted GPU clock (MHz) while powered (the track reads 0 when off)."""
    total = weight = 0.0
    for a, b in wins:
        i = max(0, bisect.bisect_right([t for t, _ in samples], a) - 1)
        for k in range(i, len(samples)):
            t, v = samples[k]
            if t >= b:
                break
            end = samples[k + 1][0] if k + 1 < len(samples) else b
            ov = overlap(t, end, a, b)
            if v > 0 and ov > 0:
                total += v * ov
                weight += ov
    return round(total / weight / 1000) if weight else None


def rails(tp):
    out = collections.defaultdict(list)
    for r in counter_rows(tp, "t.name like 'power.rails.%'"):
        out[r.track[len('power.rails.'):]].append((r.ts, r.value))
    return out


def interp(samples, t):
    if not samples:
        return None
    if t <= samples[0][0]:
        return samples[0][1]
    if t >= samples[-1][0]:
        return samples[-1][1]
    i = bisect.bisect_right([s[0] for s in samples], t)
    (t0, v0), (t1, v1) = samples[i - 1], samples[i]
    return v0 + (v1 - v0) * (t - t0) / (t1 - t0) if t1 > t0 else v0


def cadence(frames):
    """The frame period: the 10th percentile of the intervals between UI
    frame starts (4 - 50 ms), as the benches' own reports measure it."""
    starts = sorted(f.ts for f in frames)
    gaps = [(b - a) / 1e6 for a, b in zip(starts, starts[1:])]
    gaps = [g for g in gaps if 4 <= g <= 50]
    if len(gaps) < 8:
        return None
    return min((1000 / hz for hz in (60, 90, 120)), key=lambda p: abs(p - pct(gaps, 0.1)))


def short(name):
    """A slice name without its per-frame suffix (buffer and frame ids)."""
    return re.sub(r'\s*[-#(].*$|\s+\d+$', '', name) or name


def clock_offset(windows, report):
    """Trace ns minus timeline us * 1000, from the scenes' end marks."""
    diffs = []
    for scene, wins in windows.items():
        ref = report.get('windows_us', {}).get(scene) or []
        for (a, b), r in zip(wins, ref):
            if len(r) == 2 and r[1]:
                diffs.append(b - r[1] * 1000)
    return statistics.median(diffs) if diffs else None


def dart_hot(samples, period_us, intervals):
    """Self and package-inclusive ms of the samples inside intervals (us)."""
    intervals = sorted(intervals)
    starts = [a for a, _ in intervals]
    own, leaf, n = collections.Counter(), collections.Counter(), 0
    for ts, stack in samples:
        i = bisect.bisect_right(starts, ts) - 1
        if i < 0 or ts >= intervals[i][1] or not stack:
            continue
        n += 1
        leaf[stack[0][0]] += 1
        for name in {name for name, mine in stack if mine}:
            own[name] += 1
    ms = (period_us or 250) / 1000
    return {
        'samples': n,
        'morph_inclusive_ms': {k: round(v * ms, 1) for k, v in own.most_common(8)},
        'self_ms': {k: round(v * ms, 1) for k, v in leaf.most_common(8)},
    }


def analyze(path, cpu=None, report=None):
    tp = TraceProcessor(trace=path)
    upid, pid = app_process(tp)
    th = threads(tp, upid, pid)
    if 'ui' not in th or 'raster' not in th:
        raise SystemExit(f'UI or raster thread missing: {th}')
    ui_slices = slices_of(tp, th['ui'])
    raster_slices = slices_of(tp, th['raster'])
    windows = scene_windows(tp, upid)
    ui_states = thread_states(tp, th['ui'])
    raster_states = thread_states(tp, th['raster'])
    periods, uid, gpu_events = gpu_work(tp, upid)
    freqs = cpu_freq(tp)
    gfreq = gpu_freq(tp)
    rail = rails(tp)

    def tree(slices, roots):
        frames, children = [], collections.defaultdict(list)
        for s in slices:
            if s.parent_id is not None:
                children[s.parent_id].append(s)
            if s.name in roots:
                frames.append(s)
        return frames, children

    ui_frames, ui_kids = tree(ui_slices, UI_ROOTS)
    budget_ms = cadence(ui_frames) or 1000 / 60
    budget = budget_ms * 1e6
    raster_frames, raster_kids = tree(raster_slices, RASTER_ROOTS)
    raster_frames = [f for f in raster_frames if f.name == raster_frames[0].name] if raster_frames else []

    def descendants(kids, root):
        stack, out = list(kids.get(root.id, [])), []
        while stack:
            s = stack.pop()
            out.append(s)
            stack.extend(kids.get(s.id, []))
        return out

    def ui_phases(f):
        out = collections.Counter()
        stack = list(ui_kids.get(f.id, []))
        while stack:
            s = stack.pop()
            name = PHASES.get(s.name)
            if name:
                out[name] += s.dur
            else:
                stack.extend(ui_kids.get(s.id, []))
        out['other'] = max(0, f.dur - sum(out.values()))
        return out

    def raster_self(f):
        out = collections.Counter()
        for s in [f] + descendants(raster_kids, f):
            kids = raster_kids.get(s.id, [])
            out[short(s.name)] += max(0, s.dur - sum(k.dur for k in kids))
        return out

    # Each raster frame draws the newest UI frame that ended before it.
    ui_ends = [f.ts + f.dur for f in ui_frames]
    pairs, used = [], set()
    for d in raster_frames:
        i = bisect.bisect_right(ui_ends, d.ts) - 1
        while i >= 0 and i in used:
            i -= 1
        ui = ui_frames[i] if i >= 0 and d.ts - ui_ends[i] < 4 * budget else None
        if ui is not None:
            used.add(i)
        pairs.append((ui, d))

    offset = clock_offset(windows, report) if cpu and report else None
    # Presented buffers; SDKs that present off the raster thread leave the
    # raster frames' ends as the closest mark.
    queued = sorted(s.ts for s in raster_slices if s.name == 'queueBuffer') or sorted(
        f.ts + f.dur for f in raster_frames)

    starts = [d.ts for d in raster_frames]

    def gpu_of(d):
        """GPU active time from this frame's raster start to the next one's
        (at most a budget after its raster end): the work it submitted."""
        i = bisect.bisect_right(starts, d.ts)
        end = d.ts + d.dur + budget
        if i < len(starts):
            end = min(end, max(starts[i], d.ts + d.dur))
        return gpu_active(periods, d.ts, end) / 1e6

    out = {'budget_ms': budget_ms, 'gpu_uid': uid, 'gpu_events': gpu_events, 'scenes': {}}
    for scene, wins in windows.items():
        frames = []
        for a, b in wins:
            for ui, d in pairs:
                if a <= d.ts < b:
                    frames.append((ui, d))
        ui_ms, ra_ms, gpu_ms = [], [], []
        causes = collections.Counter()
        phases = collections.Counter()
        rself = collections.Counter()
        ui_wait = ra_wait = ui_total = ra_total = 0
        ui_all, ui_bad = [], []
        bad_raster, bad_ui, n_bad_raster, n_bad_ui = collections.Counter(), collections.Counter(), 0, 0
        for ui, d in frames:
            r0, r1 = d.ts, d.ts + d.dur
            g = gpu_of(d)
            ra = d.dur / 1e6
            ra_ms.append(ra)
            gpu_ms.append(g)
            rself.update(raster_self(d))
            run, runnable = state_split(raster_states, r0, r1)
            ra_wait += runnable
            ra_total += d.dur
            u = None
            if ui is not None:
                u = ui.dur / 1e6
                ui_ms.append(u)
                ph = ui_phases(ui)
                phases.update(ph)
                ui_all.append((ui.ts, ui.ts + ui.dur))
                urun, urunnable = state_split(ui_states, ui.ts, ui.ts + ui.dur)
                ui_wait += urunnable
                ui_total += ui.dur
            if not (ra > budget_ms or (u or 0) > budget_ms or g > budget_ms):
                continue
            if ra > budget_ms:
                bad_raster.update(raster_self(d))
                n_bad_raster += 1
            if ui is not None and u > budget_ms:
                bad_ui.update(ph)
                n_bad_ui += 1
            if g > 0.9 * budget_ms:
                causes['gpu'] += 1
            elif ra > budget_ms:
                sleep = d.dur - run - runnable
                if sleep > 0.4 * d.dur:
                    causes['raster-wait'] += 1
                elif runnable > 0.3 * d.dur:
                    causes['raster-sched'] += 1
                else:
                    causes['raster-cpu'] += 1
            elif ui is not None:
                ui_bad.append((ui.ts, ui.ts + ui.dur))
                if urunnable > 0.3 * ui.dur:
                    causes['ui-sched'] += 1
                else:
                    causes['ui-' + ph.most_common(1)[0][0]] += 1
        span = sum(b - a for a, b in wins)
        energy = {}
        for name, samples in rail.items():
            e = sum((interp(samples, b) or 0) - (interp(samples, a) or 0) for a, b in wins)
            energy[name] = e / (span / 1e9) / 1000 if span else 0  # uWs/s -> mW
        clusters = {}
        for cname, cpus in CLUSTERS.items():
            means = [step_mean(freqs[c], a, b) for c in cpus if freqs.get(c) for a, b in wins]
            means = [m for m in means if m is not None]
            if means:
                clusters[cname] = round(statistics.mean(means) / 1000)
        dropped = 0
        for a, b in wins:
            i, j = bisect.bisect_left(queued, a), bisect.bisect_left(queued, b)
            for t0, t1 in zip(queued[i:j], queued[i + 1:j]):
                gap = (t1 - t0) / budget
                if 1.5 <= gap <= 6:
                    dropped += round(gap) - 1
        n_frames = len(frames)
        dart = None
        if cpu and offset is not None:
            # A stall (one frame of several budgets) would own the totals;
            # it is listed on its own.
            chosen = ui_bad or ui_all
            us = [((a - offset) / 1000, (b - offset) / 1000) for a, b in chosen]
            normal = [w for w in us if w[1] - w[0] <= 4 * budget_ms * 1000]
            dart = dart_hot(cpu['samples'], cpu.get('period_us'), normal)
            dart['over'] = bool(ui_bad)
            dart['stalls'] = [
                {'ms': round((b - a) / 1000, 1),
                 **dart_hot(cpu['samples'], cpu.get('period_us'), [(a, b)])}
                for a, b in us if b - a > 4 * budget_ms * 1000]
        seconds = span / 1e9
        out['scenes'][scene] = {
            'budget_ms': budget_ms,
            'runs': len(wins),
            'seconds': round(seconds, 2),
            'frames': n_frames,
            'fps': round(n_frames / seconds, 1) if seconds else None,
            'ui_p50': pct(ui_ms, .5), 'ui_p95': pct(ui_ms, .95), 'ui_max': max(ui_ms, default=None),
            'raster_p50': pct(ra_ms, .5), 'raster_p95': pct(ra_ms, .95),
            'raster_max': max(ra_ms, default=None),
            'gpu_p50': pct(gpu_ms, .5), 'gpu_p95': pct(gpu_ms, .95),
            'gpu_ms_per_s': round(sum(gpu_active(periods, a, b) for a, b in wins)
                                  / 1e6 / seconds, 2) if seconds else None,
            'save_layers_per_frame': round(sum(
                1 for x in raster_slices if x.name == 'Canvas::saveLayer'
                and any(a <= x.ts < b for a, b in wins)) / n_frames, 2) if n_frames else 0,
            'submits_per_frame': round(sum(
                1 for x in raster_slices if x.name == 'QueueSubmit'
                and any(a <= x.ts < b for a, b in wins)) / n_frames, 2) if n_frames else 0,
            'over': sum(causes.values()),
            'over_pct': round(100 * sum(causes.values()) / n_frames, 1) if n_frames else 0,
            'causes': dict(causes.most_common()),
            'ui_phase_ms_per_frame': {k: round(v / 1e6 / max(1, len(ui_ms)), 3)
                                      for k, v in phases.most_common()},
            'raster_self_ms_per_frame': {k: round(v / 1e6 / max(1, n_frames), 3)
                                         for k, v in rself.most_common(8)},
            'bad_raster_self_ms_per_frame': {k: round(v / 1e6 / n_bad_raster, 2)
                                             for k, v in bad_raster.most_common(8)},
            'bad_ui_phase_ms_per_frame': {k: round(v / 1e6 / n_bad_ui, 2)
                                          for k, v in bad_ui.most_common()},
            'ui_runnable_share': round(ui_wait / ui_total, 3) if ui_total else None,
            'raster_runnable_share': round(ra_wait / ra_total, 3) if ra_total else None,
            'dropped': dropped,
            'cpu_mhz': clusters,
            'gpu_mhz': busy_clock(gfreq, wins),
            'power_mw': round(sum(energy.values())) if energy else None,
            'rails_mw': {k: round(v) for k, v in sorted(energy.items(), key=lambda kv: -kv[1])},
        }
        if dart is not None:
            out['scenes'][scene]['dart'] = dart
    tp.close()
    return out


def main():
    args = sys.argv[1:]
    path = args[0]

    def opt(flag):
        return json.load(open(args[args.index(flag) + 1])) if flag in args else None

    result = analyze(path, opt('--cpu'), opt('--report'))
    if '--json' in args:
        json.dump(result, open(args[args.index('--json') + 1], 'w'), indent=1)
    print(json.dumps(result, indent=1))


if __name__ == '__main__':
    main()
