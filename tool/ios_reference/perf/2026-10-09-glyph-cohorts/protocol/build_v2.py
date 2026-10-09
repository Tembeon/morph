from pathlib import Path
import subprocess
out=Path('/tmp/morph-architecture/glyph-batch')
common=['NAV_HINTS=true','NAV_HINTS_IMMEDIATE_UI=true','NAV_THREAD_PHASES=true','MORPH_DIRECT_FIELD=true','NAV_MODES=liquid','NAV_RUNS=3','NAV_WARM_MS=500','NAV_SAMPLE_MS=800','NAV_SEED=2026100911','NAV_MOTIONS=enter,nested-push,nested-pop,toolbar','NAV_SHOTS=true','NAV_SHOT_FRAMES=0,1,4,5,6,8,10,20,34,48']
for name,flag in [('control-v2',False),('cohort-raster',True)]:
 args=['python3','tool/ios_reference/perf/stage_bench/run_android.py','build','--flutter','flutter-beta','--mode','release','--target','lib/perf/navigation_stage_bench.dart','--apk',str(out/(name+'.apk'))]
 for value in common+[f'MORPH_BAR_GLYPH_BATCH={str(flag).lower()}']:args+=['--define',value]
 with (out/(name+'.build.log')).open('w') as log:subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,check=True)
