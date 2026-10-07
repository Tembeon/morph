import importlib.util,json,sys,statistics
from pathlib import Path
root=Path(__file__).resolve().parents[4]
spec=importlib.util.spec_from_file_location('energy',root/'tool/ios_reference/perf/energy.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
for arg in sys.argv[1:]:
 base=Path(arg)
 report=json.loads(base.with_suffix('.json').read_text())
 data,meta=module.analyze(str(base.with_suffix('.pftrace')), report)
 out={'meta':meta,'cases':data}
 base.with_suffix('.energy.json').write_text(json.dumps(out,indent=2)+'\n')
 for name,rows in data.items():
  print(base.name,name, round(statistics.median(r['total_mj']/r['s'] for r in rows)), 'mW')
