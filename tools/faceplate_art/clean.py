import numpy as np, json, math, os
from PIL import Image
from scipy import ndimage
K=json.load(open("knobs.json")); R=json.load(open("rects.json"))
os.makedirs("out",exist_ok=True)
ORDER=["pitch","tune","bounce","velocity","filter","clipDrive","output","boost","punch","analogEQ","grit","shine","tighten","noise"]
def L(a): return a[...,:3].mean(-1)
def save(arr,path): Image.fromarray(np.clip(arr,0,255).astype(np.uint8)).save(path)
def fill_rows(a,mask,box):
    x0,y0,x1,y1=box
    for y in range(y0,y1):
        m=mask[y,x0:x1]
        if not m.any(): continue
        bg=a[y,x0:x1][~m]
        a[y,x0:x1][m]=np.median(bg,axis=0) if len(bg) else a[y,x0]
def clusters(cols,gap):
    out=[];s=cols[0];p=cols[0]
    for c in cols[1:]:
        if c-p>gap: out.append((s,p)); s=c
        p=c
    out.append((s,p)); return out
layouts={"phone":{},"tablet":{}}
for n in ["p_modern","p_vintage","p_texture","l_modern","l_vintage","l_texture","p_platinum","l_platinum"]:
    phone=n[0]=="p"; mode=n.split("_")[1]; r=R[n]
    a=np.asarray(Image.open(f"src/{n}.png").convert("RGB")).astype(float); orig=a.copy(); lum=L(orig)
    H,W=lum.shape; yy,xx=np.mgrid[0:H,0:W]
    lay={"size":[W,H],"device":"phone" if phone else "tablet"}
    # ---------------- knobs
    knobs={}
    for k in ORDER:
        cx,cy,rad=K[n][k]
        dx=xx-cx; dy=yy-cy; rho=np.hypot(dx,dy)
        dm=(rho<rad-4)&(rho>4)&(lum<70)
        ys,xs=np.nonzero(dm)
        if len(xs):
            ang=math.degrees(math.atan2(np.mean(xs-cx),-np.mean(ys-cy)))
            rr=np.hypot(xs-cx,ys-cy); pin,pout=float(rr.min())/rad,float(rr.max())/rad
        else: ang,pin,pout=0,0.4,0.85
        knobs[k]={"x":cx,"y":cy,"r":rad,"bakedAngle":round(ang,1),"pointerInner":round(max(0.3,min(pin,0.6)),3),"pointerOuter":round(max(0.7,min(pout,0.92)),3)}
    S=48
    stack=[]
    for k in ORDER:
        cx,cy,rad=K[n][k]; c=rad*0.95
        crop=Image.fromarray(orig[int(cy-c):int(cy+c)+1,int(cx-c):int(cx+c)+1].astype(np.uint8)).resize((2*S+1,2*S+1),Image.LANCZOS)
        stack.append(np.asarray(crop).astype(float))
    master=np.median(np.stack(stack),axis=0)
    for k in ORDER:
        cx,cy,rad=K[n][k]; c=rad*0.95
        size=int(2*c)+1
        cap=np.asarray(Image.fromarray(master.astype(np.uint8)).resize((size,size),Image.LANCZOS)).astype(float)
        x0,y0=int(cx-c),int(cy-c)
        py,px=np.mgrid[0:size,0:size]; prho=np.hypot(px-(size-1)/2,py-(size-1)/2)
        rr=rad-3.5
        w=np.clip((rr-prho)/1.5,0,1)[...,None]
        reg=a[y0:y0+size,x0:x0+size]
        a[y0:y0+size,x0:x0+size]=cap*w+reg*(1-w)
        # specks of the old pointer just outside the pasted cap
        sub=a[y0-8:y0+size+8,x0-8:x0+size+8]; ls=L(sub)
        sy,sx=np.mgrid[0:sub.shape[0],0:sub.shape[1]]
        srho=np.hypot(sx-(cx-(x0-8)),sy-(cy-(y0-8)))
        ann=(srho>rr-3)&(srho<rad+0.5)
        med=ndimage.median_filter(ls,size=7)
        speck=ndimage.binary_dilation(ann&(ls<med-28),iterations=1)&ann
        for (vy,vx) in zip(*np.nonzero(speck)):
            ro=srho[vy,vx]; ph=math.atan2(vy-(cy-(y0-8)),vx-(cx-(x0-8))); vals=[]
            for sg in (-1,1):
                for f in (6,9,12):
                    q=ph+sg*f/max(ro,1); X=int(round(cx-(x0-8)+ro*math.cos(q))); Y=int(round(cy-(y0-8)+ro*math.sin(q)))
                    if 0<=X<sub.shape[1] and 0<=Y<sub.shape[0] and not speck[Y,X]: vals.append(sub[Y,X].copy())
            if vals: sub[vy,vx]=np.median(vals,axis=0)
    lay["knobs"]=knobs
    # ---------------- scope trace
    sx0,sy0,sx1,sy1=r["scope"]; ins=6
    sub=orig[sy0+ins:sy1-ins,sx0+ins:sx1-ins]; ex=sub[...,0]-(sub[...,1]+sub[...,2])/2
    # Column by column, so a slightly tilted or curved trace (aligned plates) is caught too.
    H=sub.shape[0]
    for x in range(sub.shape[1]):
        core=np.nonzero(ex[:,x]>14)[0]
        if len(core)==0: continue
        c=int(np.median(core)); lo=max(0,c-26); hi=min(H,c+27)
        glow=np.nonzero(ex[lo:hi,x]>2.5)[0]
        top=max(1,lo+(glow.min() if len(glow) else 0)-3); bot=min(H-2,lo+(glow.max() if len(glow) else 0)+3)
        ya,yb=top-1,bot+1
        for y in range(top,bot+1):
            t=(y-ya)/(yb-ya)
            a[sy0+ins+y,sx0+ins+x]=orig[sy0+ins+ya,sx0+ins+x]*(1-t)+orig[sy0+ins+yb,sx0+ins+x]*t
    lay["scope"]=[sx0+ins+4,sy0+ins+4,sx1-ins-4,sy1-ins-4]
    # ---------------- BPM digits
    bx=r["bpmBox"]; pad=10
    inner=lum[bx[1]+pad:bx[3]-pad,bx[0]+pad:bx[2]-pad]
    m=np.zeros_like(lum,bool); m[bx[1]+pad:bx[3]-pad,bx[0]+pad:bx[2]-pad]=inner>np.median(inner)+40
    cols=np.nonzero(m.any(0))[0]; cl=clusters(cols,2)
    gaps=[(cl[i+1][0]-cl[i][1],i) for i in range(len(cl)-1)]; gi=max(gaps)[1]
    d0,d1=cl[0][0],cl[gi][1]+1
    label_first=False   # every plate now shows "121 BPM"   # "BPM 120": the label is on the left
    if label_first: d0,d1=cl[gi+1][0],cl[-1][1]+1
    dm=m.copy(); dm[:,:d0]=False; dm[:,d1:]=False
    rc=dm.sum(1); rows=np.nonzero(rc>=2)[0]; runs=clusters(rows,1)
    best=max(runs,key=lambda r:r[1]-r[0]); ys=np.arange(best[0],best[1]+1)
    dm[:best[0],:]=False; dm[best[1]+1:,:]=False
    lay["bpmDigits"]=[int(d0),int(ys.min()),int(d1),int(ys.max())+1]; lay["bpmLabelX"]=int(cl[gi+1][0]); lay["bpmBox"]=bx
    if label_first:
        # The app draws digits right-aligned between bpmBox.x+12 and bpmLabelX-7.
        lay["bpmLabelX"]=int(bx[2]-4); lay["bpmBox"]=[int(cl[gi][1]-4),bx[1],bx[2],bx[3]]
    if n=="p_vintage":  # glare in this window fools the threshold; measured by eye
        d0,d1=283,331; ys=np.arange(696,722); lay["bpmDigits"]=[283,696,331,722]; lay["bpmLabelX"]=350
        dm=np.zeros_like(lum,bool); sub=lum[696:722,283:331]; dm[696:722,283:331]=sub>np.median(lum[bx[1]+10:bx[3]-10,bx[0]+10:bx[2]-10])+60
    lay["textColor"]=[int(v) for v in np.percentile(orig[dm],90,axis=0)]
    blk=np.zeros_like(dm); blk[ys.min()-3:ys.max()+4,d0-3:d1+3]=True
    if n=="p_vintage":
        y0b,y1b,x0b,x1b=ys.min()-4,ys.max()+5,d0-4,d1+4
        Lc=orig[y0b:y1b,x0b-1].astype(float); Rc=orig[y0b:y1b,x1b].astype(float)
        Tc=orig[y0b-1,x0b:x1b].astype(float); Bc=orig[y1b,x0b:x1b].astype(float)
        H,W=y1b-y0b,x1b-x0b
        for j in range(H):
            for i in range(W):
                dl,dr,dt,db=i+1,W-i,j+1,H-j
                w=np.array([1/dl,1/dr,1/dt,1/db])**2
                v=(w[0]*Lc[j]+w[1]*Rc[j]+w[2]*Tc[i]+w[3]*Bc[i])/w.sum()
                a[y0b+j,x0b+i]=v
    else:
        fill_rows(a,blk,bx)
    # ---------------- kit / preset names
    for key,bk in (("kitText","kitBox"),("presetText","presetBox")):
        x0,y0,x1,y1=r[bk]; p=8
        inner=lum[y0+p:y1-p,x0+p:x1-p]
        mm=np.zeros_like(lum,bool); mm[y0+p:y1-p,x0+p:x1-p]=inner>np.median(inner)+40
        cols=np.nonzero(mm.any(0))[0]; cl=clusters(cols,7)
        chev=cl[-1]; tm=mm.copy(); tm[:,chev[0]-2:]=False
        ys=np.nonzero(tm.any(1))[0]; xs=np.nonzero(tm.any(0))[0]
        lay[bk]=[x0,y0,x1,y1]
        lay[key]=[int(xs.min()),int(ys.min()),int(chev[0]-10),int(ys.max())+1]
        blk=np.zeros_like(tm); blk[ys.min()-3:ys.max()+4,xs.min()-3:xs.max()+4]=True
        fill_rows(a,blk,[x0,y0,x1,y1])
    # ---------------- LEDs (off state)
    half=18 if phone else 14
    leds={}
    for nm,key in (("tempoSync","ledTempo"),("followDAW","ledFollow")):
        b=r[key]; cx=(b[0]+b[2])//2; cy=(b[1]+b[3])//2
        rect=[cx-half,cy-half,cx+half,cy+half]; leds[nm+"Rect"]=rect
        p=orig[rect[1]:rect[3],rect[0]:rect[2]].copy()
        py,px=np.mgrid[0:2*half,0:2*half]; rho=np.hypot(px-half+0.5,py-half+0.5)
        ring=(rho>half*0.88)&(rho<half)
        bg=np.median(p[ring],axis=0)
        core_r=half*0.52; glow_out=half*0.88
        glow=np.clip((glow_out-rho)/(glow_out-core_r),0,1)[...,None]*(rho>=core_r)[...,None]
        q=p*(1-glow)+bg*glow
        dim=np.array([96,40,30]) if mode=="vintage" else np.array([70,22,16])
        shade=np.clip(1-rho/(core_r*1.05),0.55,1)[...,None]
        core=rho<core_r
        q[core]=(dim*shade)[core]
        rim=(rho>=core_r*0.82)&(rho<core_r)
        q[rim]=q[rim]*0.5+np.array([40,12,10])*0.5
        save(q,f"out/{n}_led_off.png")
    lay["leds"]=leds
    # ---------------- ONE-SHOT on / LOOP off
    one=r["oneShotButton"]; loop=r["loopButton"]
    def parts(rect):
        x0,y0,x1,y1=rect; inner=orig[y0+5:y1-5,x0+5:x1-5]; l=L(inner)
        bg=np.median(inner.reshape(-1,3),axis=0); bl=bg.mean()
        Rr,G=inner[...,0],inner[...,1]
        redm=(Rr-G>60)&(Rr>120)
        bright=l>bl+35
        h=inner.shape[0]; split=int(h*0.62)
        text=bright&~redm; text[split:]=False
        dash=(bright|redm); dash[:split]=False
        return inner,bg,text,dash
    oi,obg,otext,odash=parts(one); li,lbg,ltext,ldash=parts(loop)
    on_text=np.percentile(li[ltext],95,axis=0) if ltext.any() else np.array([235,235,235])
    off_text=np.percentile(oi[otext],95,axis=0) if otext.any() else np.array([150,150,150])
    def recolor(inner,bg,text,dash,new_text,src,src_dash,src_bg):
        q=inner.copy(); bl=bg.mean()
        mx=max(1,L(inner)[text].max()-bl) if text.any() else 1
        cov=np.clip((L(inner)-bl)/mx,0,1)
        tm=ndimage.binary_dilation(text,iterations=1)
        q[tm]=(bg*(1-cov[...,None])+np.array(new_text)*cov[...,None])[tm]
        dm=ndimage.binary_dilation(dash,iterations=3); q[dm]=bg
        sy,sx=np.nonzero(src_dash); ty,tx=np.nonzero(dash)
        if len(sy) and len(ty):
            oy=int(round(ty.mean()-sy.mean())); ox=int(round(tx.mean()-sx.mean()))
            box=ndimage.binary_dilation(src_dash,iterations=5)
            for y,x in zip(*np.nonzero(box)):
                Y,X=y+oy,x+ox
                if 0<=Y<q.shape[0] and 0<=X<q.shape[1]: q[Y,X]=bg+(src[y,x]-src_bg)
        return q
    def put(q,rect,name):
        x0,y0,x1,y1=rect; p=orig[y0:y1,x0:x1].copy(); p[5:-5,5:-5]=q; save(p,f"out/{n}_{name}.png")
    put(recolor(oi,obg,otext,odash,on_text,li,ldash,lbg),one,"oneshot_on")
    put(recolor(li,lbg,ltext,ldash,off_text,oi,odash,obg),loop,"loop_off")
    lay["oneShotButton"]=one; lay["loopButton"]=loop
    # ---------------- CLIPPER off
    cr=r["clipperRect"]; p=orig[cr[1]:cr[3],cr[0]:cr[2]].copy()
    pr,pg=p[...,0],p[...,1]; rm=(pr-pg>40); white=(pr>200)&(pg>170)
    q=p.copy(); q[rm]=q[rm]*np.array([0.32,0.30,0.30]); q[white]=np.array([120,70,66])
    save(q,f"out/{n}_clipper_off.png"); lay["clipperRect"]=cr
    # ---------------- PLAY on
    pr_=r["playRect"]; p=orig[pr_[1]:pr_[3],pr_[0]:pr_[2]].copy(); l=L(p); bgl=np.median(l)
    cov=np.clip((l-bgl)/max(1,(l.max()-bgl)),0,1); cov[cov<0.25]=0
    col=np.array([255,86,52]); q=p*(1-cov[...,None])+(col*(0.55+0.45*cov[...,None]))*cov[...,None]
    save(q,f"out/{n}_play_on.png"); lay["playRect"]=pr_
    for k in ["diceRect","saveRect","exportRect","menuRect"]: lay[k]=r[k]
    lay["modeButtons"]={m:r["mode_"+m] for m in ["modern","vintage","texture"]}
    lay["pads"]=r["pads"]
    lay["padOrder"]=[8,9,10,11,4,5,6,7,0,1,2,3] if phone else [6,7,8,9,10,11,0,1,2,3,4,5]
    save(a,f"out/{n}_plate.png")
    layouts["phone" if phone else "tablet"][mode]=lay
    print(n,"ok","bpm",lay["bpmDigits"],lay["bpmLabelX"],"kit",lay["kitText"],"pre",lay["presetText"],"knob0",knobs["pitch"])
def ints(o):
    if isinstance(o,dict): return {k:ints(v) for k,v in o.items()}
    if isinstance(o,list): return [ints(v) for v in o]
    if isinstance(o,(np.integer,)): return int(o)
    if isinstance(o,(np.floating,)): return float(o)
    return o
json.dump(ints(layouts["tablet"]),open("out/KnockLayout.json","w"),indent=1)
json.dump(ints(layouts["phone"]),open("out/PhoneKnockLayout.json","w"),indent=1)
