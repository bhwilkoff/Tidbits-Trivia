#!/usr/bin/env python3
"""Tidbits app icon. Original strengths kept: a real BOLD-FONT 'T' (SF Rounded
Black — an actual letterform, not two rects), the 3D 'sticker' tile (hard offset
shadow) at the original ~0.59-of-canvas size, coral period dot. Dots reworked
into an organic, overlapping/strewn scatter, none touching the tile.
Supersampled 4x → LANCZOS for crisp edges."""
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

def render(S):
    im=Image.new("RGBA",(S,S),CORAL); d=ImageDraw.Draw(im)
    # 3D sticker tile (original size: margin ~0.205)
    m=0.205*S; bw=0.040*S; so=0.026*S
    tile=[m,m,S-m,S-m]; tr=0.255*(S-2*m)
    rrect(d,[tile[0]+so,tile[1]+so,tile[2]+so,tile[3]+so],tr,fill=INK)   # shadow
    rrect(d,tile,tr,fill=INK)                                            # border
    rrect(d,[m+bw,m+bw,S-m-bw,S-m-bw],tr-bw*0.55,fill=CREAM)             # face

    # Real bold-font 'T' (SF Rounded Black), cropped tight, scaled to fit
    tmp=Image.new("RGBA",(S,S),(0,0,0,0)); td=ImageDraw.Draw(tmp)
    f=ImageFont.truetype(SFR,int(0.55*S))
    td.text((S//2,S//2),"T",font=f,fill=INK,anchor="mm")
    g=tmp.crop(tmp.getbbox())
    target_h=int(0.345*S); sc=target_h/g.height
    g=g.resize((int(g.width*sc),target_h),Image.LANCZOS)
    tile_cx=S/2; tile_cy=(m+(S-m))/2
    gx=int(tile_cx-g.width/2); gy=int(tile_cy-g.height/2-0.012*S)
    im.alpha_composite(g,(gx,gy))
    # coral period dot, lower-right of the stem
    dr=0.030*S
    circ(d,tile_cx+0.125*S,gy+g.height-dr*0.6,dr,fill=CORAL)

    # Organic strewn dots (overlapping each other; clear of the tile)
    gap=0.014*S
    dots=[
        (0.140,0.150,0.057,"fill",YELLOW),  # upper-left
        (0.205,0.112,0.028,"fill",PINK),    # overlaps yellow
        (0.858,0.138,0.042,"fill",BLUE),    # upper-right
        (0.915,0.405,0.022,"fill",GRAPE),   # right edge accent
        (0.138,0.842,0.051,"ring",GRAPE),   # lower-left ring
        (0.205,0.882,0.019,"fill",GREEN),   # overlaps the ring
        (0.862,0.836,0.053,"fill",GREEN),   # lower-right
    ]
    for fx,fy,fr,kind,col in dots:
        bx,by,br=fx*S,fy*S,fr*S
        assert dpr(bx,by,*tile)>br+gap, f"dot {col} overlaps tile"
        if kind=="ring": circ(d,bx,by,br,outline=col,width=int(0.023*S))
        else: circ(d,bx,by,br,fill=col)
    return im

icon = render(1024*4).resize((1024,1024),Image.LANCZOS).convert("RGB")
for path in ["TidbitsTrivia/Assets.xcassets/AppIcon.appiconset/icon-1024.png",  # iOS
             "assets/icon.png"]:                                                # web PWA / og / apple-touch
    icon.save(path); print("wrote", path)
icon.save("/tmp/icon_new_1024.png")
