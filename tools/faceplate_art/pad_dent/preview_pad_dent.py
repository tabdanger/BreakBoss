# Preview of the pad dent (ScopeAndPads.swift PadTouchSurface): composites the same radial dent on the Face 1 plates. Run from the repo root.
import json, numpy as np
from PIL import Image
import os; root=os.path.join(os.path.dirname(__file__),'../../../')
L=json.load(open(root+'BreakBoss.swiftpm/Resources/KnockLayout.json'))
faces={'platinum':'ModernPlatinum','modern':'ModernBlack','vintage':'Vintage','texture':'Texture'}
light={'platinum':(255,51,36),'modern':(255,51,36),'vintage':(255,237,158),'texture':(64,158,255)}
stops=[(0,(0,0,0,.46)),(.38,(0,0,0,.30)),(.68,(0,0,0,.10)),(.84,(255,255,255,.11)),(1,(255,255,255,0))]
def dent_rgba(size):
    n=int(size); yy,xx=np.mgrid[0:n,0:n]; r=np.hypot(xx-n/2+.5,yy-n/2+.5)/(n/2)
    out=np.zeros((n,n,4))
    for c in range(4):
        out[...,c]=np.interp(r,[s[0] for s in stops],[s[1][c] for s in stops])
    out[r>1]=0
    return out
def comp(img, rect, fingers, flash):
    x0,y0,x1,y1=rect; w,h=x1-x0,y1-y0
    a=img[y0:y1,x0:x1]
    if fingers: a[:]=a*(1-.12)
    if flash>0:
        col=np.array(light[face]); al=flash*.5; a[:]=a*(1-al)+col*al
        b=3; m=np.zeros((h,w),bool); m[:b]=m[-b:]=True; m[:,:b]=m[:,-b:]=True
        al2=flash*.8; a[m]=a[m]*(1-al2)+col*al2
    for (px,py,v,amt) in fingers:
        size=min(w,h)*(.42+.22*v)*(.55+.45*amt if amt<1 else 1)
        d=dent_rgba(size); n=d.shape[0]; op=(.55+.45*v)*amt
        cx,cy=int(px-n/2),int(py-n/2)
        for j in range(n):
            yy=cy+j
            if yy<0 or yy>=h: continue
            xs=max(0,-cx); xe=min(n,w-cx)
            if xe<=xs: continue
            seg=a[yy,cx+xs:cx+xe]; dd=d[j,xs:xe]; al=dd[:,3:4]*op
            seg[:]=seg*(1-al)+dd[:,:3]*al
    return a
for face in faces:
    base=np.asarray(Image.open(root+f'tools/faceplate_art/face1/Face1_{faces[face]}.png').convert('RGB')).astype(float)
    pads=L[face]['pads']
    # hits: (pad, x frac, y frac, start frame)
    hits=[(0,.5,.7,0),(7,.35,.85,5),(2,.6,.3,10),(9,.5,.5,13),(4,.7,.8,18),(11,.4,.6,22),(1,.5,.9,26),(1,.3,.4,28)]
    frames=[]
    top=600; bot=960
    for f in range(40):
        img=base.copy()
        per={}
        for (p,fx,fy,st) in hits:
            t=f-st
            if t<0 or t>9: continue
            amt=1.0 if t<5 else max(0,1-(t-4)/5)   # hold 5 frames, release over 5 (~160 ms)
            if t==0: amt=1.0
            fl=max(0,1-(t/30)/.22)
            r=pads[p]; w=r[2]-r[0]; h=r[3]-r[1]
            per.setdefault(p,[[],0,False])
            per[p][1]=max(per[p][1],fl)
            v=.55+.45*fy
            if amt>0: per[p][0].append((fx*w,fy*h,v,amt)); 
            if t<5: per[p][2]=True
        for p,(fing,fl,held) in per.items():
            r=pads[p]
            comp(img,r,fing if fing else [],fl) if True else None
        im=Image.fromarray(np.clip(img[top:bot,60:1390],0,255).astype('uint8'))
        frames.append(im.resize((im.width*3//5,im.height*3//5),Image.LANCZOS).quantize(128))
    frames[0].save(f'tools/faceplate_art/pad_dent/preview/pad-dent-{face}.gif',save_all=True,append_images=frames[1:],duration=33,loop=0,optimize=True)
    # still: pick frame with several dents
    if face=='platinum': pass
    frames[23].convert('RGB').save(f'tools/faceplate_art/pad_dent/preview/still-{face}.jpg',quality=88)
