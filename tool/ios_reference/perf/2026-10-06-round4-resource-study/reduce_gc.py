#!/usr/bin/env python3
"""Join scene-window young collections to UI BeginFrame slices in an atrace."""
import collections
import hashlib
import json
import re
import statistics
import sys
from pathlib import Path

p=Path(sys.argv[1])
line_re=re.compile(r'^\s*(.+?)-(\d+)\s+\(\s*[\d-]+\)\s+\[\d+\]\s+\S+\s+(\d+\.\d+): tracing_mark_write: (.*)$')
stacks=collections.defaultdict(list)
marks=collections.defaultdict(dict)
frames=[]
gcs=[]
ui=None
for line in p.open(errors='replace'):
 m=line_re.match(line)
 if not m: continue
 tid=m[2]; t=float(m[3])*1000; parts=m[4].split('|')
 if parts[0]=='B' and len(parts)>=3:
  name=parts[2]
  if name.startswith('scene:'):
   _,scene,run,edge=name.rsplit(':',3);marks[(scene,run)][edge]=t;ui=tid
  stacks[tid].append((name,t))
 elif parts[0]=='E' and stacks[tid]:
  name,a=stacks[tid].pop()
  if name=='Animator::BeginFrame': frames.append((tid,a,t))
  elif name=='CollectNewGeneration': gcs.append((tid,a,t))
out={'trace_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'scenes':{}}
for scene in sorted({s for s,r in marks}):
 spans=[(v['begin'],v['end']) for (s,r),v in marks.items() if s==scene and 'begin' in v and 'end' in v]
 fs=[(a,b) for tid,a,b in frames if tid==ui and any(x<=a<y for x,y in spans)]
 gs=[(a,b) for tid,a,b in gcs if tid==ui and any(x<=a<y for x,y in spans)]
 with_gc=[b-a for a,b in fs if any(x<b and y>a for x,y in gs)]
 without=[b-a for a,b in fs if not any(x<b and y>a for x,y in gs)]
 slow=[(a,b) for a,b in fs if b-a>16.667]
 row={'ui_frames':len(fs),'young_collections':len(gs),'gc_total_ms':sum(b-a for a,b in gs),'gc_max_ms':max((b-a for a,b in gs),default=0),'gc_frame_median_ms':statistics.median(with_gc) if with_gc else None,'other_frame_median_ms':statistics.median(without),'frames_over_16_667_ms':len(slow),'slow_frames_overlapping_gc':sum(any(x<b and y>a for x,y in gs) for a,b in slow)}
 out['scenes'][scene]=row
 print(scene,row)
p.with_suffix('.gc-summary.json').write_text(json.dumps(out,indent=2)+'\n')
