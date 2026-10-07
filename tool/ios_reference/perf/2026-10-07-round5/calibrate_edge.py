import json,sys
import numpy as np
from pathlib import Path
from PIL import Image
root=Path(sys.argv[1]);name=sys.argv[2];report=json.loads((root/(name+'.json')).read_text());out={}
for key in report['case_metadata']:
 samples=[]
 for phase in report['shot_phases']:
  path=root/(name+'.artifacts')/f'{key}-p{phase}.png';a=np.asarray(Image.open(path).convert('RGB'),dtype=float);profile=a[1104,320:760,0];w=np.maximum(0,-np.diff(profile));x=np.arange(len(w))+320.5;mass=w.sum();mean=(w*x).sum()/mass;var=(w*(x-mean)**2).sum()/mass
  samples.append({'phase':phase,'edge_derivative_mass':float(mass),'centroid_px':float(mean),'sigma_device_px':float(np.sqrt(var))})
 out[key]=samples
(root/'calibration.json').write_text(json.dumps(out,indent=2)+'\n');print({k:np.median([v['sigma_device_px'] for v in vs]) for k,vs in out.items()})
