import json,collections,sys
t=json.load(open(sys.argv[1]))
ev=t['traceEvents']
spans=[];stack=collections.defaultdict(list)
for e in sorted([e for e in ev if e.get('ph') in 'BEX'],key=lambda e:e['ts']):
  if e['ph']=='X': spans.append((e['tid'],e['ts'],e['ts']+e.get('dur',0),e['name'],len(stack[e['tid']])))
  elif e['ph']=='B': stack[e['tid']].append(e)
  elif e['ph']=='E' and stack[e['tid']]:
    b=stack[e['tid']].pop(); spans.append((e['tid'],b['ts'],e['ts'],b['name'],len(stack[e['tid']])))
draws=[s for s in spans if s[3]=='GPURasterizer::Draw']
t0=draws[0][1]
marks=sorted((e['ts'],e['name']) for e in ev if e.get('name','').startswith('scene:'))
for s in draws:
  d=(s[2]-s[1])/1000
  if d<12 and '--all' not in sys.argv: continue
  kids=[k for k in spans if k[0]==s[0] and k[1]>=s[1] and k[2]<=s[2]]
  c=collections.Counter(k[3] for k in kids); dur=collections.Counter()
  for k in kids: dur[k[3]]+=k[2]-k[1]
  ops=sum(v for n,v in c.items() if 'OpsTask::onExecute' in n)
  m=[n for ts,n in marks if ts<=s[1]]
  top=[(n[:40],round(dur[n]/1000,1),c[n]) for n,_ in dur.most_common(12) if n not in('GPURasterizer::Draw','Rasterizer::DoDraw','Rasterizer::DrawToSurfaces')][:7]
  print(f"{(s[1]-t0)/1000:8.1f} {d:7.2f} ops{ops:3} {m[-1] if m else ''}\n     {top}")
