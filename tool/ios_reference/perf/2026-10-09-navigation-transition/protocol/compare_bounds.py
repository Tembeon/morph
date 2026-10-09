"""Compare only PNGs named by fresh Navigation shot_graphs, never stale files."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
p=argparse.ArgumentParser()
p.add_argument('left',type=Path)
p.add_argument('right',type=Path)
p.add_argument('--out',required=True,type=Path)
a=p.parse_args()
l=json.loads(a.left.read_text());r=json.loads(a.right.read_text())
assert l['shot_graphs'].keys()==r['shot_graphs'].keys()
rows=[]
for name,g in l['shot_graphs'].items():
 lp=a.left.with_suffix('.artifacts')/(name+'.png')
 rp=a.right.with_suffix('.artifacts')/(name+'.png')
 aa=np.asarray(Image.open(lp).convert('RGBA')).astype(np.int16)
 bb=np.asarray(Image.open(rp).convert('RGBA')).astype(np.int16)
 assert aa.shape==bb.shape
 diff=np.max(np.abs(aa-bb),axis=2);h,w=diff.shape
 mask=np.zeros((h,w),dtype=bool)
 for graph in [g,r['shot_graphs'][name]]:
  for f in graph['foreground_filter_sources']:
   x,y,fw,fh=f['screen_rect'];dpr=l['device_pixel_ratio']
   x0=max(0,int(np.floor(x*dpr))-100);x1=min(w,int(np.ceil((x+fw)*dpr))+100)
   y0=max(0,int(np.floor(y*dpr))-100);y1=min(h,int(np.ceil((y+fh)*dpr))+100)
   mask[y0:y1,x0:x1]=True
 def metrics(d):
  return None if not d.size else {'pixels':int(d.size),'max':int(d.max()),'p95':float(np.percentile(d,95)),'mean':float(d.mean()),'changed':int(np.count_nonzero(d)),'over_2':int(np.count_nonzero(d>2))}
 def area(graph):return sum(f['source_size_logical'][0]*f['source_size_logical'][1] for f in graph['foreground_filter_sources'])
 rows.append({'shot':name,'left_png_sha256':hashlib.sha256(lp.read_bytes()).hexdigest(),'right_png_sha256':hashlib.sha256(rp.read_bytes()).hexdigest(),'image_size':[w,h],'left_source_area':area(g),'right_source_area':area(r['shot_graphs'][name]),'all':metrics(diff),'upper_chrome':metrics(diff[:500]),'lower_chrome':metrics(diff[h-400:]),'page':metrics(diff[500:h-400]),'glyph_witness':metrics(diff[mask])})
a.out.write_text(json.dumps({'left':str(a.left),'right':str(a.right),'limitations':['Framework-root toImage captures after timing; not direct SurfaceFlinger screen grabs.','Glyph witness is the union of transformed foreground boxes with a fixed 100-pixel halo; not engine filter attachment coverage.','Read only current report shot_graphs names; artifact directories contain older unowned PNGs.','Raw differences include unrelated one-pixel contour/render noise; compare the repeated control.'],'rows':rows},indent=2)+'\n')
for row in rows:
 if row['left_source_area']:print(row['shot'],round(row['left_source_area']),round(row['right_source_area']),row['glyph_witness'])
