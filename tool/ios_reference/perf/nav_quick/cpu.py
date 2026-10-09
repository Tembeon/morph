import json,sys,collections
d=json.load(open(sys.argv[1]))
fns=d['functions']
def name(i):
    f=fns[i]['function']
    n=f.get('name','?'); o=f.get('owner',{}); on=o.get('name','') if isinstance(o,dict) else ''
    lib=f.get('location',{}).get('script',{}).get('uri','') if isinstance(f.get('location'),dict) else ''
    return f"{on}.{n}" if on else n, lib
samples=d['samples']
t0=min(s['timestamp'] for s in samples); t1=max(s['timestamp'] for s in samples)
lo=float(sys.argv[2]) if len(sys.argv)>2 else 0; hi=float(sys.argv[3]) if len(sys.argv)>3 else 1e18
ss=[s for s in samples if s.get('stack') and lo<= (s['timestamp']-t0)/1000 <=hi]
excl=collections.Counter(); incl=collections.Counter()
for s in ss:
    st=s['stack']
    excl[name(st[0])[0]]+=1
    seen=set()
    for i in st:
        n=name(i)
        if 'morph' in n[1] and n[0] not in seen:
            incl[n[0]]+=1; seen.add(n[0])
print('samples',len(ss),'span ms',(t1-t0)/1000, 'period us', d.get('samplePeriod'))
print('--- exclusive'); [print(v,k) for k,v in excl.most_common(25)]
print('--- inclusive (morph code)'); [print(v,k) for k,v in incl.most_common(40)]
