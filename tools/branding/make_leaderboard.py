#!/usr/bin/env python3
"""Game Center leaderboard images — the EXACT Tidbits app icon (make_icon.py),
with only the coral period dot swapped for a mark: a star (Classic High Score)
or a lightning bolt (Daily Streak). Everything else — tile, T, dots — identical.
512x512 RGB, no alpha (App Store Connect spec)."""
import math
from PIL import Image, ImageDraw, ImageFont

CORAL=(255,116,111,255); CREAM=(252,245,233,255); INK=(35,30,26,255)
YELLOW=(255,201,60,255); BLUE=(45,91,255,255); GREEN=(47,203,138,255)
GRAPE=(139,92,246,255); PINK=(255,93,162,255)
SFR="/System/Library/Fonts/Supplemental/Arial Black.ttf"

def rrect(d,b,r,**k): d.rounded_rectangle(b,radius=r,**k)
def circ(d,cx,cy,r,**k): d.ellipse([cx-r,cy-r,cx+r,cy+r],**k)
def dpr(px,py,x0,y0,x1,y1):
    nx,ny=min(max(px,x0),x1),min(max(py,y0),y1); return math.hypot(px-nx,py-ny)

def star(d,cx,cy,r,col):
    pts=[]
    for i in range(10):
        a=-math.pi/2+i*math.pi/5
        rad=r if i%2==0 else r*0.42
        pts.append((cx+rad*math.cos(a),cy+rad*math.sin(a)))
    d.polygon(pts,fill=col)

def bolt(d,cx,cy,h,col):
    # classic lightning bolt, unit box (y down), centered on (cx,cy)
    w=h*0.66
    u=[(0.58,0.0),(0.12,0.54),(0.42,0.54),(0.30,1.0),(0.88,0.40),(0.56,0.40)]
    pts=[(cx+(x-0.5)*w, cy+(y-0.5)*h) for x,y in u]
    d.polygon(pts,fill=col)

def render(S, mark):
    im=Image.new("RGBA",(S,S),CORAL); d=ImageDraw.Draw(im)
    # 3D sticker tile (identical to make_icon.py)
    m=0.205*S; bw=0.040*S; so=0.026*S
    tile=[m,m,S-m,S-m]; tr=0.255*(S-2*m)
    rrect(d,[tile[0]+so,tile[1]+so,tile[2]+so,tile[3]+so],tr,fill=INK)   # shadow
    rrect(d,tile,tr,fill=INK)                                            # border
    rrect(d,[m+bw,m+bw,S-m-bw,S-m-bw],tr-bw*0.55,fill=CREAM)             # face

    # Real bold 'T' (identical)
    tmp=Image.new("RGBA",(S,S),(0,0,0,0)); td=ImageDraw.Draw(tmp)
    f=ImageFont.truetype(SFR,int(0.55*S))
    td.text((S//2,S//2),"T",font=f,fill=INK,anchor="mm")
    g=tmp.crop(tmp.getbbox())
    target_h=int(0.345*S); sc=target_h/g.height
    g=g.resize((int(g.width*sc),target_h),Image.LANCZOS)
    tile_cx=S/2; tile_cy=(m+(S-m))/2
    gx=int(tile_cx-g.width/2); gy=int(tile_cy-g.height/2-0.012*S)
    im.alpha_composite(g,(gx,gy))

    # The mark — same coral, same lower-right-of-the-stem spot as the period.
    dr=0.030*S
    mx=tile_cx+0.125*S; my=gy+g.height-dr*0.6
    md=ImageDraw.Draw(im)
    if mark=="dot":   circ(md,mx,my,dr,fill=CORAL)
    elif mark=="star": star(md,mx,my,dr*1.7,CORAL)
    elif mark=="bolt": bolt(md,mx,my,dr*3.0,CORAL)

    # Organic strewn dots (identical)
    gap=0.014*S
    dots=[(0.140,0.150,0.057,"fill",YELLOW),(0.205,0.112,0.028,"fill",PINK),
          (0.858,0.138,0.042,"fill",BLUE),(0.915,0.405,0.022,"fill",GRAPE),
          (0.138,0.842,0.051,"ring",GRAPE),(0.205,0.882,0.019,"fill",GREEN),
          (0.862,0.836,0.053,"fill",GREEN)]
    for fx,fy,fr,kind,col in dots:
        bx,by,br=fx*S,fy*S,fr*S
        if kind=="ring": circ(d,bx,by,br,outline=col,width=int(0.023*S))
        else: circ(d,bx,by,br,fill=col)
    return im

for mark,name in [("star","leaderboard-classic-high"),("bolt","leaderboard-daily-streak")]:
    img=render(512*4, mark).resize((512,512),Image.LANCZOS).convert("RGB")
    img.save(f"tools/branding/gamecenter/{name}.png"); print("wrote", name)
