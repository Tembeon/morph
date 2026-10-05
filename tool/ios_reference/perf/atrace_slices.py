#!/usr/bin/env python3
"""Sums the trace-event slices of an atrace text dump per thread.

    atrace_slices.py <atrace.txt> [pid] [top]

The dump is `adb shell atrace --async_stop` (or `atrace -t N`) output of an
app built with the TraceSystrace meta-data, so Flutter's TRACE_EVENTs land in
it as tracing_mark_write B/E pairs. Prints, per thread with slices, the slice
names by total self and inclusive time, their count and the mean per count.
"""
import collections
import re
import sys

LINE = re.compile(
    r'^\s*(?P<comm>.+?)-(?P<tid>\d+)\s+\(\s*(?P<tgid>[\d-]+)\)\s+\[\d+\]\s+\S+\s+'
    r'(?P<ts>\d+\.\d+): tracing_mark_write: (?P<body>.*)$'
)


def main():
    path = sys.argv[1]
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
