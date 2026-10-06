#!/usr/bin/env python3
"""Sums the trace-event slices of an atrace text dump per thread.

    atrace_slices.py <atrace.txt> [pid] [top]
    atrace_slices.py <atrace.txt> --scenes

The dump is `adb shell atrace --async_stop` (or `atrace -t N`) output of an
app built with the TraceSystrace meta-data, so Flutter's TRACE_EVENTs land in
it as tracing_mark_write B/E pairs. Prints, per thread with slices, the slice
names by total self and inclusive time, their count and the mean per count.

With --scenes it windows the trace by the glass audit's scene markers (the
zero-length slices scene:<name>:<run>:begin / :end) and prints, per scene,
the raster frames in its windows and per frame: saveLayers, queue submits
on the raster and the UI thread, the raster frame and its encode, the UI
phases, and the new-generation collections (frames per scavenge). A slice
belongs to the window its start falls in.
"""
import collections
import re
import sys

LINE = re.compile(
    r'^\s*(?P<comm>.+?)-(?P<tid>\d+)\s+\(\s*(?P<tgid>[\d-]+)\)\s+\[\d+\]\s+\S+\s+'
    r'(?P<ts>\d+\.\d+): tracing_mark_write: (?P<body>.*)$'
)


def scenes(path):
    slices = []
    marks = collections.defaultdict(dict)
    names = {}
    stacks = collections.defaultdict(list)
    with open(path, errors='replace') as f:
        for line in f:
            m = LINE.match(line)
            if not m:
                continue
            parts = m.group('body').split('|')
            tid = m.group('tid')
            ts = float(m.group('ts')) * 1000
            names[tid] = m.group('comm')
            if parts[0] == 'B' and len(parts) >= 3:
                name = parts[2]
                if name.startswith('scene:') and name.count(':') >= 3:
                    _, scene, run, edge = name.rsplit(':', 3)
                    marks[(scene, run)][edge] = ts
                stacks[tid].append([name, ts, 0.0])
            elif parts[0] == 'E' and stacks[tid]:
                name, start, child = stacks[tid].pop()
                d = ts - start
                slices.append((start, tid, name, d, d - child))
                if stacks[tid]:
                    stacks[tid][-1][2] += d
    windows = collections.defaultdict(list)
    for (scene, run), edges in marks.items():
        if 'begin' in edges and 'end' in edges:
            windows[scene].append((edges['begin'], edges['end']))
    if not windows:
        print('no scene markers')
        return

    def thread(tid):
        comm = names.get(tid, '')
        if 'raster' in comm:
            return 'raster'
        return 'ui' if tid == ui_tid else 'other'

    ui_tid = None
    for start, tid, name, d, own in slices:
        if name.startswith('scene:'):
            ui_tid = tid
            break
    rows = []
    for scene, spans in windows.items():
        spans.sort()
        total = collections.defaultdict(lambda: [0, 0.0, 0.0])
        for start, tid, name, d, own in slices:
            if not any(a <= start < b for a, b in spans):
                continue
            t = total[(thread(tid), name)]
            t[0] += 1
            t[1] += d
            t[2] += own
        frames = total[('raster', 'GPURasterizer::Draw')][0]
        ui_frames = total[('ui', 'Animator::BeginFrame')][0]
        seconds = sum(b - a for a, b in spans) / 1000
        scav = total[('ui', 'CollectNewGeneration')][0]

        def per(thread_name, name, field=0, frames_=None):
            n = frames_ if frames_ is not None else frames
            return total[(thread_name, name)][field] / n if n else 0.0

        rows.append((scene, {
            'runs': len(spans),
            'seconds': seconds,
            'raster frames': frames,
            'ui frames': ui_frames,
            'saveLayer/frame': per('raster', 'Canvas::saveLayer'),
            'saveLayer self ms/frame': per('raster', 'Canvas::saveLayer', 2),
            'raster submits/frame': per('raster', 'QueueSubmit'),
            'raster submit ms/frame': per('raster', 'QueueSubmit', 1),
            'Draw incl ms/frame': per('raster', 'GPURasterizer::Draw', 1),
            'Encode self ms/frame': per('raster', 'SurfaceFrame::Encode', 2),
            'ui submits/frame': per('ui', 'QueueSubmit', 0, ui_frames),
            'ui submit ms/frame': per('ui', 'QueueSubmit', 1, ui_frames),
            'BeginFrame incl ms/frame': per('ui', 'Animator::BeginFrame', 1, ui_frames),
            'BUILD self ms/frame': per('ui', 'BUILD', 2, ui_frames),
            'LAYOUT self ms/frame': per('ui', 'LAYOUT', 2, ui_frames),
            'PAINT self ms/frame': per('ui', 'PAINT', 2, ui_frames),
            'COMPOSITING self ms/frame': per('ui', 'COMPOSITING', 2, ui_frames),
            'scavenges': scav,
            'frames/scavenge': ui_frames / scav if scav else float('inf'),
            'scavenge ms': total[('ui', 'CollectNewGeneration')][1],
        }))
    keys = list(rows[0][1].keys())
    print(f'{"":28}' + ''.join(f'{scene:>13}' for scene, _ in rows))
    for k in keys:
        cells = []
        for _, r in rows:
            v = r[k]
            cells.append(f'{v:13d}' if isinstance(v, int) else f'{v:13.3f}')
        print(f'{k:28}' + ''.join(cells))


def main():
    path = sys.argv[1]
    if len(sys.argv) > 2 and sys.argv[2] == '--scenes':
        scenes(path)
        return
    pid = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
    top = int(sys.argv[3]) if len(sys.argv) > 3 else 25
    stacks = collections.defaultdict(list)
    names = {}
    incl = collections.defaultdict(float)
    self_ = collections.defaultdict(float)
    count = collections.defaultdict(int)
    span = {}
    with open(path, errors='replace') as f:
        for line in f:
            m = LINE.match(line)
            if not m:
                continue
            body = m.group('body')
            parts = body.split('|')
            if pid is not None and len(parts) > 1 and parts[1] != pid:
                continue
            tid = m.group('tid')
            ts = float(m.group('ts')) * 1000
            names[tid] = m.group('comm')
            first, last = span.get(tid, (ts, ts))
            span[tid] = (min(first, ts), max(last, ts))
            if parts[0] == 'B' and len(parts) >= 3:
                stacks[tid].append([parts[2], ts, 0.0])
            elif parts[0] == 'E' and stacks[tid]:
                name, start, child = stacks[tid].pop()
                d = ts - start
                key = (tid, name)
                incl[key] += d
                self_[key] += d - child
                count[key] += 1
                if stacks[tid]:
                    stacks[tid][-1][2] += d
    by_thread = collections.defaultdict(list)
    for (tid, name), total in incl.items():
        by_thread[tid].append((total, name))
    for tid, rows in sorted(by_thread.items(), key=lambda kv: -sum(t for t, _ in kv[1])):
        first, last = span[tid]
        print(f'== {names[tid]} (tid {tid}), window {last - first:.0f} ms')
        print(f'{"incl ms":>10} {"self ms":>10} {"count":>7} {"incl/cnt":>9}  name')
        for total, name in sorted(rows, reverse=True)[:top]:
            key = (tid, name)
            print(f'{total:10.1f} {self_[key]:10.1f} {count[key]:7d} {total / count[key]:9.3f}  {name}')
        print()


main()
