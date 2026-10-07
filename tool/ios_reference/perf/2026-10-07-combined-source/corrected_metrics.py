"""Aggregate native repeats without hiding launch-to-launch variation."""
import json
import statistics
from pathlib import Path
import sys
root = Path(sys.argv[1])
gpu = json.loads((root / 'corrected-gpu/summary/summary.json').read_text())
energy = json.loads((root / 'corrected-energy/summary.json').read_text())['text']
rows = {}
for launch in gpu:
    for row in launch['rows']:
        bucket = rows.setdefault(row['case'], {'metadata': {k: row[k] for k in ['motion','mode','requested_sigma_logical']}, 'gpu_launches':[], 'runs':[]})
        bucket['gpu_launches'].append(row['gpu_ms'])
        bucket['runs'].extend(row['runs'])
for case,row in rows.items():
    for metric in ['gpu_ms','build_p50','build_p95','build_p99','raster_p50','raster_p95','raster_p99','over_budget','vsync_gap_slots']:
        row[metric] = statistics.median(x[metric] for x in row['runs'])
    row['power_launches_mw'] = [v['total_mj']/v['s'] for _,v in energy[case]]
    row['power_mw'] = statistics.mean(row['power_launches_mw'])
    row['gpu_rail_launches_mw'] = [v['rails_mj']['rails.gpu']/v['s'] for _,v in energy[case]]
    row['frames_counted'] = sum(x['n'] for x in row['runs'])
    if row['metadata']['mode'] != 'mix-bare':
        baseline = case.replace(row['metadata']['mode'],'mix-native')
        row['baseline'] = baseline
(root / 'corrected-metrics.json').write_text(json.dumps(rows,indent=2)+'\n')
for motion in ['background','updates','dynamic']:
 for sigma in [2]:
  names=[f'cluster-{motion}-merged-mix-{mode}-s{sigma}.0' for mode in ['native','gaussian']]
  print(motion,sigma,' | '.join(f"{rows[n]['gpu_ms']:.3f} ms / {rows[n]['power_mw']:.0f} mW" for n in names))
