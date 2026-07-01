#!/usr/bin/env python3
"""Android adaptive icon from the approved Tidbits mark. Foreground (color, on
TRANSPARENT — the coral comes from the background layer) + a monochrome 'T'
silhouette for Android 13+ themed icons. Density buckets for a 108dp foreground."""
import os, math
from PIL import Image, ImageDraw, ImageFont

CORAL=(255,116,111,255); CREAM=(252,245,233,255); INK=(35,30,26,255)
YELLOW=(255,201,60,255); BLUE=(45,91,255,255); GREEN=(47,203,138,255)
GRAPE=(139,92,246,255); PINK=(255,93,162,255)
FONT="/System/Library/Fonts/Supplemental/Arial Black.ttf"
RES="android/app/src/main/res"
DENS={"mdpi":108,"hdpi":162,"xhdpi":216,"xxhdpi":324,"xxxhdpi":432}

def rrect(d,b,r,**k): d.rounded_rectangle(b,radius=r,**k)
def circ(d,cx,cy,r,**k): d.ellipse([cx-r,cy-r,cx+r,cy+r],**k)

def T_glyph(S, color, target_h_frac):
    tmp=Image.new("RGBA",(S,S),(0,0,0,0)); td=ImageDraw.Draw(tmp)
    f=ImageFont.truetype(FONT,int(0.55*S)); td.text((S//2,S//2),"T",font=f,fill=color,anchor="mm")
    g=tmp.crop(tmp.getbbox()); th=int(target_h_frac*S); sc=th/g.height
    return g.resize((int(g.width*sc),th),Image.LANCZOS)

# The confetti lives in the BACKGROUND layer (full-bleed) so it fills the icon
# to the mask edge like iOS — instead of being crammed into the foreground where
# the adaptive safe-zone crop shrank it and clipped the corner dots.
def background(S):
    im=Image.new("RGBA",(S,S),CORAL); d=ImageDraw.Draw(im)
    for fx,fy,fr,kind,col in [(0.140,0.150,0.057,"fill",YELLOW),(0.205,0.112,0.028,"fill",PINK),
        (0.858,0.138,0.042,"fill",BLUE),(0.915,0.405,0.022,"fill",GRAPE),
        (0.138,0.842,0.051,"ring",GRAPE),(0.205,0.882,0.019,"fill",GREEN),
        (0.862,0.836,0.053,"fill",GREEN)]:
        bx,by,br=fx*S,fy*S,fr*S
        if kind=="ring": circ(d,bx,by,br,outline=col,width=int(0.023*S))
        else: circ(d,bx,by,br,fill=col)
    return im

# Foreground = ONLY the cream "T." tile, centered in the adaptive safe zone
# (margin 0.205 keeps the tile corners inside a circular mask). Matches iOS.
def foreground(S):
    im=Image.new("RGBA",(S,S),(0,0,0,0)); d=ImageDraw.Draw(im)
    m=0.205*S; bw=0.040*S; so=0.026*S; tile=[m,m,S-m,S-m]; tr=0.255*(S-2*m)
    rrect(d,[tile[0]+so,tile[1]+so,tile[2]+so,tile[3]+so],tr,fill=INK)
    rrect(d,tile,tr,fill=INK); rrect(d,[m+bw,m+bw,S-m-bw,S-m-bw],tr-bw*0.55,fill=CREAM)
    g=T_glyph(S,INK,0.345); tcx=S/2; tcy=(m+(S-m))/2
    gx=int(tcx-g.width/2); gy=int(tcy-g.height/2-0.012*S); im.alpha_composite(g,(gx,gy))
    dr=0.030*S; circ(d,tcx+0.125*S,gy+g.height-dr*0.6,dr,fill=CORAL)
    return im

def monochrome(S):
    im=Image.new("RGBA",(S,S),(0,0,0,0))
    g=T_glyph(S,(0,0,0,255),0.40)              # bold T silhouette, centered (themed-icon tint)
    im.alpha_composite(g,(S//2-g.width//2,S//2-g.height//2))
    return im

for bucket,px in DENS.items():
    bg=background(px*4).resize((px,px),Image.LANCZOS)
    fg=foreground(px*4).resize((px,px),Image.LANCZOS)
    mo=monochrome(px*4).resize((px,px),Image.LANCZOS)
    d=f"{RES}/mipmap-{bucket}"; os.makedirs(d,exist_ok=True)
    bg.save(f"{d}/ic_launcher_background.png")
    fg.save(f"{d}/ic_launcher_foreground.png"); mo.save(f"{d}/ic_launcher_monochrome.png")
    print("wrote", bucket, px)
