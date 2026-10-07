"""Compare declared native phase captures; measure the monotone edge response."""
import argparse,json
from pathlib import Path
import numpy as np
from PIL import Image
p=argparse.ArgumentParser();p.add_argument('report',type=Path);p.add_argument('--edge',action='store_true');p.add_argument('--out',type=Path,required=True);a=p.parse_args()
r=json.loads(a.report.read_text());root=Path(str(a.report).removesuffix('.json')+'.artifacts');out=[]
for name,meta in r['case_metadata'].items():
 mode=meta['mode'];sigma=meta['requested_sigma_logical']
 if mode not in ('gpu-copy','gpu-dual','gpu-dual3','gpu-canvas','gpu-retained'):continue
 ref=name.replace(mode,'gpu-bare' if mode=='gpu-copy' else 'gpu-gaussian')
 if mode=='gpu-copy':ref=ref.replace(f'-s{float(sigma)}','-s0.0')
 for phase in r['shot_phases']:
  aa=np.asarray(Image.open(root/f'{name}-p{phase}.png')).astype(np.int16)
  bb=np.asarray(Image.open(root/f'{ref}-p{phase}.png')).astype(np.int16)
  dd=abs(aa-bb);row={'case':name,'reference':ref,'phase':phase,'max_channel':int(dd.max()),'mean_channel':float(dd.mean()),'changed_pixels':int(np.any(dd>0,axis=2).sum())}
  if a.edge:
   def measure(img):
    v=img[img.shape[0]//2,:,0].astype(float)/255;d=np.diff(v);w=np.maximum(d,0);x=np.arange(len(w))+.5;mu=float(np.dot(w,x)/sum(w));var=float(np.dot(w,(x-mu)**2)/sum(w))
    return {'center_px':mu,'width_second_moment_px':var**.5,'negative_edge_mass':float(-np.minimum(d,0).sum())}
   row['candidate_edge']=measure(aa);row['reference_edge']=measure(bb)
  out.append(row)
a.out.write_text(json.dumps(out,indent=2)+'\n')
for mode in ('gpu-copy','gpu-dual','gpu-dual3','gpu-canvas','gpu-retained'):
 for sigma in (2.,10.):
  rows=[v for v in out if v['case'].endswith(f'{mode}-s{sigma}')]
  if not rows:continue
  print(mode,sigma,'max',max(v['max_channel'] for v in rows))
  if a.edge:print([(v['phase'],round(v['reference_edge']['width_second_moment_px'],3),round(v['candidate_edge']['width_second_moment_px'],3)) for v in rows])
