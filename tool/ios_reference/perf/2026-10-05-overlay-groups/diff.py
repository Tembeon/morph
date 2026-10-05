# Max channel difference between the backdrop_overlay_test variants per
# tier and scene: python3 diff.py <run dir> (screenshots are not committed).
import sys, json, os, numpy as np
from PIL import Image
d=sys.argv[1]
r=json.load(open(f'{d}/report.json')); s=r['dpr']
print('liquid', r['liquid_available'], 'dpr', s)
for tier in ('liquid','frosted'):
    for scene in ('body','hero','lens','dialog','alert'):
        if not os.path.exists(f'{d}/{tier}-{scene}-shared.png'): continue
        im={v: np.asarray(Image.open(f'{d}/{tier}-{scene}-{v}.png').convert('RGB')).astype(int) for v in ('shared','none','own')}
        h=im['shared'].shape[0]
        y0=int(200*s)
        out=[]
        for a,b in (('shared','none'),('own','none'),('shared','own')):
            df=np.abs(im[a][y0:]-im[b][y0:]).max(axis=2)
            ys,xs=np.nonzero(df>12)
            box=(int(xs.min()/s),int((ys.min()+y0)/s),int(xs.max()/s),int((ys.max()+y0)/s)) if len(xs) else None
            out.append('%s-%s max %d n>12 %d box %s'%(a,b,df.max(),len(xs),box))
        print(tier,scene,' | '.join(out))
