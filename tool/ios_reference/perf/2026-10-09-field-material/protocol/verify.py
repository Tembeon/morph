from pathlib import Path
import subprocess
out=Path('/tmp/morph-architecture/direct-field-material');r=Path.cwd()
steps=[('analyze-final',['flutter-beta','analyze'],r),('dartdoc-final',['dart-beta','doc','--dry-run'],r),('package-tests-final',['nice','-n','10','flutter-beta','test','-j','2'],r),('example-tests',['nice','-n','10','flutter-beta','test','-j','2'],r/'example'),('macos-build',['flutter-beta','build','macos','--release','--dart-define=MORPH_AUTODEMO=true'],r/'example'),('autodemo',[str(r/'example/build/macos/Build/Products/Release/morph_example.app/Contents/MacOS/morph_example')],r/'example'),('wasm-build',['flutter-beta','build','web','--wasm'],r/'example')]
for name,args,cwd in steps:
 print('checking',name,flush=True)
 with (out/(name+'.log')).open('w') as log:p=subprocess.run(args,cwd=cwd,stdout=log,stderr=subprocess.STDOUT)
 print(name,p.returncode,flush=True)
 if p.returncode:raise SystemExit(p.returncode)
