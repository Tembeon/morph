import hashlib,json,sys
from pathlib import Path
import numpy as np
from PIL import Image

def compare(a,b):
 aa=np.asarray(Image.open(a).convert('RGBA')).astype(np.int16);bb=np.asarray(Image.open(b).convert('RGBA')).astype(np.int16);d=np.abs(aa-bb)
 return {'a_sha256':hashlib.sha256(a.read_bytes()).hexdigest(),'b_sha256':hashlib.sha256(b.read_bytes()).hexdigest(),'max':int(d.max()),'changed_pixels':int(np.any(d,axis=2).sum()),'rmse':float(np.sqrt(np.mean(d.astype(float)**2))),'mean':float(d.mean())}
root=Path(sys.argv[1]);report=json.loads((root/(sys.argv[2]+'.json')).read_text());dest=root/(sys.argv[2]+'.parity.json');shots=root/(sys.argv[2]+'.artifacts');out={}
if len(sys.argv)>3:
 other=root/(sys.argv[3]+'.artifacts')
 for key in report['case_metadata']:
  out[key]=[{**compare(shots/f'{key}-p{p}.png',other/f'{key}-p{p}.png'),'phase':p} for p in report['shot_phases']]
else:
 for key in report['case_metadata']:
  mode=report['case_metadata'][key]['mode']
  ref='blur' if mode in ['dual','matrix'] else 'glass'
  if mode not in ['replay','cache','dual','dual-glass','matrix']:continue
  reference=key.replace('-'+mode+'-', '-'+ref+'-')
  out[key]=[{**compare(shots/f'{reference}-p{p}.png',shots/f'{key}-p{p}.png'),'phase':p} for p in report['shot_phases']]
dest.write_text(json.dumps(out,indent=2)+'\n');print({k:max(x['max'] for x in v) for k,v in out.items()})
