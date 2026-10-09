from pathlib import Path
import subprocess,json
p=Path('/tmp/morph-architecture/direct-field-material');python='/Users/tembeon/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
for left,right,label in [('control-v2-present-3','control-v2-present-4','control-repeat'),('candidate-v2-present-3','candidate-v2-present-4','candidate-repeat'),('control-v2-present-3','candidate-v2-present-3','present-pair-1'),('control-v2-present-4','candidate-v2-present-4','present-pair-2')]:
 args=[python,'/tmp/morph-architecture/navigation-research/compare_bounds.py',str(p/'results'/(left+'.json')),str(p/'results'/(right+'.json')),'--out',str(p/('pixels-'+label+'.json'))]
 with (p/('pixels-'+label+'.log')).open('w') as log:subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,check=True)
 d=json.loads((p/('pixels-'+label+'.json')).read_text());print(label,'chrome max',max(max(x['upper_chrome']['max'],x['lower_chrome']['max']) for x in d['rows']),'chrome over2',sum(x['upper_chrome']['over_2']+x['lower_chrome']['over_2'] for x in d['rows']),flush=True)
