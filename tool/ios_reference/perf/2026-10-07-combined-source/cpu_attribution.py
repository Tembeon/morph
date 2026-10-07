import json, sys
from pathlib import Path
from perfetto.trace_processor import TraceProcessor
root=Path(sys.argv[1]); output={}
for launch in ['text-1','text-2']:
 report=json.loads((root/(launch+'.json')).read_text()); meta=json.loads((root/(launch+'.energy.json')).read_text())['meta']
 tp=TraceProcessor(trace=str(root/(launch+'.pftrace')))
 app=[r.upid for r in tp.query("select upid from process where name like 'dev.tembeon.morph_example%'")]
 if not app: print('process names',[(r.name) for r in tp.query("select name from process where name like '%morph%'")]); raise SystemExit(1)
 launchrows={}
 for case, windows in report['windows_us'].items():
  if 'updates' not in case: continue
  sums={}
  for a,b in windows:
   a=int(a*1000+meta['mono_to_trace_ns']); b=int(b*1000+meta['mono_to_trace_ns'])
   sql=f"select t.upid, sum(min(s.ts+s.dur,{b})-max(s.ts,{a}))/1e6 as ms from sched s left join thread t on t.utid=s.utid where s.utid!=0 and s.ts<{b} and s.ts+s.dur>{a} group by t.upid"
   for r in tp.query(sql):
    key='app' if r.upid in app else 'other'
    sums[key]=sums.get(key,0)+r.ms
  launchrows[case]=sums
 output[launch]=launchrows; tp.close()
(root/'cpu-attribution.json').write_text(json.dumps(output,indent=2)+'\n'); print(json.dumps(output,indent=2))
