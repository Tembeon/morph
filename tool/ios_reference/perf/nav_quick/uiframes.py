import json,sys,collections
t=json.load(open(sys.argv[1])); c=json.load(open(sys.argv[2]))
ev=t['traceEvents']
spans=[];stack=collections.defaultdict(list)
for e in sorted([e for e in ev if e.get('ph') in 'BEX'],key=lambda e:e['ts']):
  if e['ph']=='X': spans.append((e['tid'],e['ts'],e['ts']+e.get('dur',0),e['name']))
  elif e['ph']=='B': stack[e['tid']].append(e)
  elif e['ph']=='E' and stack[e['tid']]:
    b=stack[e['tid']].pop(); spans.append((e['tid'],b['ts'],e['ts'],b['name']))
frames=[s for s in spans if s[3] in ('Animator::BeginFrame','BeginFrame') ]
names=collections.Counter(s[3] for s in spans if s[2]-s[1]>5000); print(names.most_common(8))
fns=c['functions']
def name(i):
    f=fns[i]['function']; n=f.get('name','?'); o=f.get('owner',{}); on=o.get('name','') if isinstance(o,dict) else ''
    return f"{on}.{n}" if on else n
long=[s for s in frames if s[2]-s[1]>float(sys.argv[3])*1000]
print(len(frames),'frames',len(long),'long')
incl=collections.Counter(); n=0
for f in long:
  for s in c['samples']:
    if s.get('stack') and f[1]<=s['timestamp']<=f[2]:
      n+=1; seen=set()
      for i in s['stack']:
        nm=name(i)
        if nm not in seen: incl[nm]+=1; seen.add(nm)
print('samples',n)
for k,v in incl.most_common(70): print(v,k)
