#!/usr/bin/env python3
"""iOS launch screen assets: the splash reads like a zoomed-out app icon —
coral fills the screen (storyboard view bg), brand dots strewn full-bleed
(LaunchDots, transparent, aspectFill), the cream tile + Arial-Black T centered
(LaunchIcon, identical proportions to the shipped icon). Supersample → LANCZOS."""
import os, math
from PIL import Image, ImageDraw, ImageFont

CORAL=(255,116,111,255); CREAM=(252,245,233,255); INK=(35,30,26,255)
YELLOW=(255,201,60,255); BLUE=(45,91,255,255); GREEN=(47,203,138,255)
GRAPE=(139,92,246,255); PINK=(255,93,162,255)
FONT="/System/Library/Fonts/Supplemental/Arial Black.ttf"
AX="TidbitsTrivia/Assets.xcassets"
def rrect(d,b,r,**k): d.rounded_rectangle(b,radius=r,**k)
def circ(d,cx,cy,r,**k): d.ellipse([cx-r,cy-r,cx+r,cy+r],**k)

def tile(S):
    """The icon's front: 3D cream tile + bold T + coral period, on transparent.
    Same formulas as make_icon.render, then cropped tight to tile+shadow."""
    im=Image.new("RGBA",(S,S),(0,0,0,0)); d=ImageDraw.Draw(im)
    m=0.205*S; bw=0.040*S; so=0.026*S; tr=0.255*(S-2*m)
    rrect(d,[m+so,m+so,S-m+so,S-m+so],tr,fill=INK)          # shadow
    rrect(d,[m,m,S-m,S-m],tr,fill=INK)                      # border
    rrect(d,[m+bw,m+bw,S-m-bw,S-m-bw],tr-bw*0.55,fill=CREAM) # face
    tmp=Image.new("RGBA",(S,S),(0,0,0,0)); td=ImageDraw.Draw(tmp)
    f=ImageFont.truetype(FONT,int(0.55*S)); td.text((S//2,S//2),"T",font=f,fill=INK,anchor="mm")
    g=tmp.crop(tmp.getbbox()); th=int(0.345*S); g=g.resize((int(g.width*th/g.height),th),Image.LANCZOS)
    cx=S/2; cy=(m+(S-m))/2; gx=int(cx-g.width/2); gy=int(cy-g.height/2-0.012*S)
    im.alpha_composite(g,(gx,gy)); dr=0.030*S
    circ(d,cx+0.125*S,gy+g.height-dr*0.6,dr,fill=CORAL)
    pad=int(0.02*S); box=(int(m-pad),int(m-pad),int(S-m+so+pad),int(S-m+so+pad))
    return im.crop(box)

# strewn dots across a full portrait screen; central ellipse kept clear for the icon
DOTS=[(0.16,0.08,0.052,"fill",YELLOW),(0.27,0.065,0.026,"fill",PINK),
      (0.78,0.10,0.044,"fill",BLUE),(0.905,0.07,0.022,"fill",GRAPE),
      (0.40,0.045,0.024,"fill",GREEN),(0.08,0.30,0.040,"ring",GRAPE),
      (0.93,0.34,0.030,"fill",GREEN),(0.10,0.50,0.024,"fill",PINK),
      (0.91,0.52,0.034,"ring",BLUE),(0.06,0.66,0.046,"fill",GREEN),
      (0.155,0.72,0.022,"fill",YELLOW),(0.885,0.70,0.050,"fill",YELLOW),
      (0.80,0.80,0.024,"fill",PINK),(0.20,0.90,0.040,"fill",BLUE),
      (0.50,0.955,0.030,"ring",GRAPE),(0.63,0.90,0.020,"fill",GREEN)]
def dots(W,H):
    im=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(im)
    for fx,fy,fr,kind,col in DOTS:
        bx,by,br=fx*W,fy*H,fr*W
        if kind=="ring": circ(d,bx,by,br,outline=col,width=int(0.016*W))
        else: circ(d,bx,by,br,fill=col)
    return im

def imageset(name, base, render, scales=(1,2,3)):
    p=os.path.join(AX,name+".imageset"); os.makedirs(p,exist_ok=True)
    imgs=[]
    big=render(*[v*4 for v in base])  # 4x supersample
    for s in scales:
        tgt=tuple(v*s for v in base)
        big.resize(tgt,Image.LANCZOS).save(os.path.join(p,f"{name.lower()}-{s}x.png"))
        imgs.append(f'    {{ "idiom" : "universal", "filename" : "{name.lower()}-{s}x.png", "scale" : "{s}x" }}')
    open(os.path.join(p,"Contents.json"),"w").write(
        '{\n  "images" : [\n'+',\n'.join(imgs)+'\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n')
    print("wrote", p)

# LaunchIcon: square; render() ignores 2nd dim
imageset("LaunchIcon",(220,220), lambda w,h: tile(w))
imageset("LaunchDots",(440,956), lambda w,h: dots(w,h))

# Full-composite mock for visual verification (coral + dots + centered icon)
W,H=440,956; mock=Image.new("RGBA",(W,H),CORAL)
mock.alpha_composite(dots(W*4,H*4).resize((W,H),Image.LANCZOS))
ic=tile(220*4).resize((150,150),Image.LANCZOS); mock.alpha_composite(ic,((W-150)//2,(H-150)//2))
mock.convert("RGB").save("/tmp/launch_mock.png"); print("wrote /tmp/launch_mock.png")
