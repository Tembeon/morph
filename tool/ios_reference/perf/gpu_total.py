import re,sys,bisect
PERIOD=re.compile(r'\s(\d+\.\d+): gpu_work_period: gpu_id=(\d+) uid=(\d+) start_time_ns=(\d+) end_time_ns=(\d+) total_active_duration_ns=(\d+)')
FREQ=re.compile(r'\s(\d+\.\d+): gpu_frequency: state=(\d+) gpu_id=0')
for path in sys.argv[1:]:
    dev=open(path.replace('.gpuwork.txt','.device.txt')).read()
    m=re.search(r'uid:(\d+)',dev); uid=m.group(1) if m else None
    per=[];fr=[]
    for line in open(path,errors='replace'):
        a=PERIOD.search(line)
        if a and a.group(2)=='0' and a.group(3)==uid: per.append((int(a.group(4)),int(a.group(5)),int(a.group(6))))
        b=FREQ.search(line)
        if b: fr.append((float(b.group(1))*1e9,int(b.group(2))))
    fr.sort(); ft=[f[0] for f in fr]
    act=sum(p[2] for p in per)
    cyc=0
    for s,e,a in per:
        i=bisect.bisect_right(ft,(s+e)/2)-1
        f=fr[i][1] if i>=0 else (fr[0][1] if fr else 0)
        cyc+=a*1e-9*f*1e3
    span=(per[-1][1]-per[0][0])/1e9 if per else 0
    print(f'{path.split("/")[-1]:30} uid {uid} active {act/1e9:.3f} s over {span:.1f} s  Gcycles {cyc/1e9:.3f}')
