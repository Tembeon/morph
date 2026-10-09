from pathlib import Path
import subprocess
out=Path('/tmp/morph-architecture/direct-field-material')
for binary in ['candidate','control']:
 name=binary+'-v2-gpu-2';print('running',name,flush=True)
 args=['python3','tool/ios_reference/perf/stage_bench/run_android.py','run','--apk',str(out/(binary+'.apk')),'--out',str(out/'results'),'--name',name,'--trace','gpu','--schema','stage','--leave-installed','--pull-artifacts','--timeout','300']
 with (out/(name+'.run.log')).open('w') as log:subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,check=True)
 print('finished',name,flush=True)
