#!/usr/bin/env python3
"""Check cached raster running time against a direct thread-name SQL join."""
import json
import sys
from pathlib import Path
from perfetto.trace_processor import TraceProcessor

for arg in sys.argv[1:]:
    path = Path(arg)
    report = json.loads(path.with_suffix('.json').read_text())
    cache = json.loads(path.with_suffix('.energy.json').read_text())
    offset = cache['meta']['mono_to_trace_ns']
    tp = TraceProcessor(trace=str(path))
    rows = list(tp.query("""select utid,tid,name from thread where name like '%.raster'
        and upid in (select upid from process where name like 'dev.tembeon.morph_example%')"""))
    out = {'threads': [dict(utid=r.utid, tid=r.tid, name=r.name) for r in rows], 'scenes': {}}
    for scene, windows in report['windows_us'].items():
        actual = legacy = 0.0
        last = rows[-1].utid
        for a, b in windows:
            a, b = a * 1000 + offset, b * 1000 + offset
            sql = f"""select sum(min(s.ts+s.dur,{b})-max(s.ts,{a}))/1e6 as ms
                from sched s join thread t on t.utid=s.utid
                where s.ts<{b} and s.ts+s.dur>{a} and t.name like '%.raster'
                and t.upid in (select upid from process where name like 'dev.tembeon.morph_example%')"""
            actual += list(tp.query(sql))[0].ms or 0.0
            legacy += list(tp.query(f"""select sum(min(ts+dur,{b})-max(ts,{a}))/1e6 as ms
                from sched where ts<{b} and ts+dur>{a} and utid={last}"""))[0].ms or 0.0
        cached = sum(sum(w['thread_ms']['raster'].values()) for w in cache['out'][scene])
        assert abs(actual-cached) < 0.001, (scene, actual, cached)
        out['scenes'][scene] = {'direct_raster_ms': actual, 'cached_raster_ms': cached, 'legacy_last_thread_ms': legacy}
    tp.close()
    path.with_suffix('.raster-verification.json').write_text(json.dumps(out, indent=2)+'\n')
    print(path.name, 'direct SQL matches cached raster time; threads:', len(rows))
