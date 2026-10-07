import sys,json,statistics,importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[5]
spec=importlib.util.spec_from_file_location('stage',ROOT/'tool/ios_reference/perf/stage_bench/summarize.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
out={}
for p in sorted(Path(sys.argv[1]).glob('*.json')):
 if p.name.endswith(('build.json','energy.json','summary.json')):continue
 r=json.loads(p.read_text());gpu=m.load_gpu(p.with_suffix(''));data={}
 for scene,ws in r['windows_us'].items():
  rows=[]
  for w,run in zip(ws,r[scene]['runs']):
   a,c,e=m.gpu_cost(*gpu,w[0]*1000,w[1]*1000) if gpu else (0,0,0)
   rows.append({**{k:run[k] for k in ['n','build_p50','raster_p50','build_p95','raster_p95','build_p99','raster_p99','over_budget']},'gpu_ms':a/run['n']/1e6 if e else None,'gpu_mcycles':c/run['n']/1e6 if e and c else None})
  data[scene]={'runs':rows,'median':{k:statistics.median([x[k] for x in rows]) if all(x[k] is not None for x in rows) else None for k in rows[0]}}
 out[p.stem]=data
Path(sys.argv[2]).write_text(json.dumps(out,indent=2)+'\n')
for name,data in out.items():
 print(name,{s:{k:round(v,3) if isinstance(v,float) else v for k,v in d['median'].items()} for s,d in data.items()})
