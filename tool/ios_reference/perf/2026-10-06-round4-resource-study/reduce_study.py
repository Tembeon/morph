#!/usr/bin/env python3
"""Reduce diagnostic-only counts and VM allocations; never use their timings."""
import collections
import json
import statistics
import sys
from pathlib import Path

for arg in sys.argv[1:]:
    path = Path(arg)
    report = json.loads(path.read_text())
    out = {}
    for scene, runs in report.get('resource_study', {}).items():
        rows = []
        for run in runs:
            counts = collections.Counter()
            roles = {}
            for layer in run['layers']:
                counts.update(layer['counts'])
                role = roles.setdefault(layer['role'], {'counts': collections.Counter(), 'peaks': {}})
                role['counts'].update(layer['counts'])
                for name,value in layer['peaks'].items():
                    role['peaks'][name] = max(role['peaks'].get(name,0), value)
            rows.append({'counts': dict(counts), 'global': run['global'], 'roles': roles})
        keys=set().union(*(r['counts'] for r in rows))
        out[scene] = {'median_counts': {k:statistics.median(r['counts'].get(k,0) for r in rows) for k in sorted(keys)}, 'runs': rows}
    for scene, runs in report.get('allocation_study', {}).items():
        rows=[]
        for run in runs:
            members=run.get('members', [])
            totals={k:sum(x.get(k,0) for x in members if x.get(k,0)>=0) for k in ['accumulatedSize','bytesCurrent','instancesAccumulated','instancesCurrent']}
            top=sorted(members,key=lambda x:x.get('accumulatedSize',0),reverse=True)[:35]
            rows.append({'totals':totals,'memoryUsage':run.get('memoryUsage'),'top': [{'class':x.get('class',{}).get('name'),'id':x.get('class',{}).get('id'), **{k:x.get(k) for k in totals}} for x in top]})
        out[scene]={'runs':rows}
    path.with_suffix('.study-summary.json').write_text(json.dumps(out,indent=2)+'\n')
    for scene, summary in out.items():
        print(path.name,scene,summary.get('median_counts', [r.get('totals') for r in summary['runs']]))
