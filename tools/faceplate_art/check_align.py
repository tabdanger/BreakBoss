import numpy as np, json, cv2
from scipy import ndimage
K=json.load(open("knobs.json")); R=json.load(open("rects.json"))
ORDER=["pitch","tune","bounce","velocity","filter","clipDrive","output","boost","punch","analogEQ","grit","shine","tighten","noise"]
th=np.linspace(0,2*np.pi,120,endpoint=False)
def knob(im,gx,gy,x0,y0,r0):
    best=(0,None)
    for cx in range(int(x0)-10,int(x0)+11):
        for cy in range(int(y0)-10,int(y0)+11):
            for r in range(int(r0)-4,int(r0)+5):
                xs=(cx+r*np.cos(th)).astype(int); ys=(cy+r*np.sin(th)).astype(int)
                s=np.mean(np.abs(gx[ys,xs]*np.cos(th)+gy[ys,xs]*np.sin(th)))
                if s>best[0]: best=(s,(cx,cy))
    return best[1]
def padshift(g,gref,rects):
    out=[]
    for x0,y0,x1,y1 in rects:
        x0,y0,x1,y1=int(x0)-20,int(y0)-20,int(x1)+20,int(y1)+20
        a=cv2.Sobel(g[y0:y1,x0:x1].astype(np.float32),cv2.CV_32F,1,0)**2+cv2.Sobel(g[y0:y1,x0:x1].astype(np.float32),cv2.CV_32F,0,1)**2
        b=cv2.Sobel(gref[y0:y1,x0:x1].astype(np.float32),cv2.CV_32F,1,0)**2+cv2.Sobel(gref[y0:y1,x0:x1].astype(np.float32),cv2.CV_32F,0,1)**2
        a=np.sqrt(a);b=np.sqrt(b);a/=a.max()+1e-6;b/=b.max()+1e-6
        best=(-1,0,0)
        for dx in range(-14,15,1):
            for dy in range(-14,15,1):
                c=float((np.roll(np.roll(a,dy,0),dx,1)[15:-15,15:-15]*b[15:-15,15:-15]).sum())
                if c>best[0]: best=(c,dx,dy)
        out.append(np.hypot(best[1],best[2]))
    return out
def pads(g,dev):
    lo=630 if dev=="l" else 1180
    m=(g<int(np.percentile(g[lo:],30))+12).astype(np.uint8); m[:lo]=0
    m=cv2.morphologyEx(m,cv2.MORPH_OPEN,np.ones((9,9),np.uint8))
    n,lab,st,_=cv2.connectedComponentsWithStats(m)
    return [(x+w/2,y+h/2) for x,y,w,h,a in st[1:] if a>8000 and w<300 and h<300]
for dev in "lp":
    ref=None
    for mode in ["modern","vintage","texture","platinum"]:
        g=cv2.imread(f"out/{dev}_{mode}_plate.png",0).astype(float)
        gx=ndimage.sobel(g,1); gy=ndimage.sobel(g,0)
        kc=[knob(g,gx,gy,*K[f"{dev}_modern"][k]) for k in ORDER]
        if ref is None: ref=(kc,g)
        pd=padshift(g,ref[1],R[f"{dev}_modern"]["pads"])
        kd=[np.hypot(a[0]-b[0],a[1]-b[1]) for a,b in zip(kc,ref[0])]
        print(f"{dev}_{mode:9s} knobs off by max {max(kd):4.1f}px mean {np.mean(kd):4.1f} | pads max {max(pd):4.1f}px mean {np.mean(pd):4.1f}")
