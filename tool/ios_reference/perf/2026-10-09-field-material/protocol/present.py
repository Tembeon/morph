from pathlib import Path
import subprocess
r=Path.cwd();o=Path('/tmp/morph-architecture/direct-field-material')
for binary,name in [('control','control-v2-present-3'),('candidate','candidate-v2-present-3'),('candidate','candidate-v2-present-4'),('control','control-v2-present-4')]:
 print('running',name,flush=True)
 args=['python3','tool/ios_reference/perf/stage_bench/run_android.py','run','--apk',str(o/(binary+'.apk')),'--out',str(o/'results'),'--name',name,'--trace','presentation','--schema','stage','--leave-installed','--pull-artifacts','--timeout','300']
 with (o/(name+'.run.log')).open('w') as log:subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,check=True)
 print('finished',name,flush=True)
