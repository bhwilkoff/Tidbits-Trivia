#!/usr/bin/env python3
"""Game Center achievement images — the EXACT Tidbits app icon, with the coral
period dot swapped for a per-achievement coral mark. 512x512 RGB, no alpha."""
import math
from PIL import Image, ImageDraw, ImageFont

CORAL=(255,116,111,255); CREAM=(252,245,233,255); INK=(35,30,26,255)
YELLOW=(255,201,60,255); BLUE=(45,91,255,255); GREEN=(47,203,138,255)
GRAPE=(139,92,246,255); PINK=(255,93,162,255)
SFR="/System/Library/Fonts/Supplemental/Arial Black.ttf"
C=CORAL

def rrect(d,b,r,**k): d.rounded_rectangle(b,radius=r,**k)
def circ(d,cx,cy,r,**k): d.ellipse([cx-r,cy-r,cx+r,cy+r],**k)

# --- marks (coral), centered at (cx,cy), sized by s ---
def m_sparkle(d,cx,cy,s):
    d.polygon([(cx,cy-s),(cx+s*.24,cy-s*.24),(cx+s,cy),(cx+s*.24,cy+s*.24),
               (cx,cy+s),(cx-s*.24,cy+s*.24),(cx-s,cy),(cx-s*.24,cy-s*.24)],fill=C)
def m_check(d,cx,cy,s):
    d.line([(cx-s*.75,cy),(cx-s*.18,cy+s*.6),(cx+s*.85,cy-s*.7)],fill=C,width=max(2,int(s*.34)),joint="curve")
def m_diamond(d,cx,cy,s):
    d.polygon([(cx,cy-s),(cx+s*.7,cy),(cx,cy+s),(cx-s*.7,cy)],fill=C)
    d.polygon([(cx,cy-s*.5),(cx+s*.35,cy),(cx,cy+s*.5),(cx-s*.35,cy)],fill=CREAM)
def m_flame(d,cx,cy,s):
    d.polygon([(cx,cy-s),(cx+s*.62,cy+s*.05),(cx+s*.5,cy+s*.7),(cx-s*.5,cy+s*.7),(cx-s*.62,cy+s*.05)],fill=C)
    d.polygon([(cx,cy-s*.25),(cx+s*.3,cy+s*.2),(cx+s*.22,cy+s*.6),(cx-s*.22,cy+s*.6),(cx-s*.3,cy+s*.2)],fill=CREAM)
def m_crown(d,cx,cy,s):
    d.polygon([(cx-s,cy+s*.55),(cx-s,cy-s*.45),(cx-s*.5,cy+s*.05),(cx,cy-s*.6),
               (cx+s*.5,cy+s*.05),(cx+s,cy-s*.45),(cx+s,cy+s*.55)],fill=C)
def m_pie(d,cx,cy,s):
    circ(d,cx,cy,s,outline=C,width=max(2,int(s*.26)))
    for ang in (90,210,330):
        a=math.radians(ang); d.line([(cx,cy),(cx+s*.82*math.cos(a),cy+s*.82*math.sin(a))],fill=C,width=max(2,int(s*.22)))
def m_target(d,cx,cy,s):
    circ(d,cx,cy,s,outline=C,width=max(2,int(s*.22)))
    circ(d,cx,cy,s*.42,fill=C)
def m_arrow(d,cx,cy,s):
    d.polygon([(cx,cy-s),(cx+s*.6,cy+s*.7),(cx,cy+s*.32),(cx-s*.6,cy+s*.7)],fill=C)
def m_book(d,cx,cy,s):
    rrect(d,[cx-s*.85,cy-s*.62,cx+s*.85,cy+s*.62],s*.14,fill=C)
    d.line([(cx,cy-s*.55),(cx,cy+s*.55)],fill=CREAM,width=max(2,int(s*.12)))

def render(S, mark, msz):
    im=Image.new("RGBA",(S,S),CORAL); d=ImageDraw.Draw(im)
    m=0.205*S; bw=0.040*S; so=0.026*S
    tile=[m,m,S-m,S-m]; tr=0.255*(S-2*m)
    rrect(d,[tile[0]+so,tile[1]+so,tile[2]+so,tile[3]+so],tr,fill=INK)
    rrect(d,tile,tr,fill=INK); rrect(d,[m+bw,m+bw,S-m-bw,S-m-bw],tr-bw*0.55,fill=CREAM)
    tmp=Image.new("RGBA",(S,S),(0,0,0,0)); td=ImageDraw.Draw(tmp)
    f=ImageFont.truetype(SFR,int(0.55*S)); td.text((S//2,S//2),"T",font=f,fill=INK,anchor="mm")
    g=tmp.crop(tmp.getbbox()); th=int(0.345*S); sc=th/g.height; g=g.resize((int(g.width*sc),th),Image.LANCZOS)
    cx0=S/2; cy0=(m+(S-m))/2; gx=int(cx0-g.width/2); gy=int(cy0-g.height/2-0.012*S)
    im.alpha_composite(g,(gx,gy))
    dr=0.030*S; mx=cx0+0.125*S; my=gy+g.height-dr*0.6
    mark(ImageDraw.Draw(im), mx, my, dr*msz)
    gap=0.014*S
    for fx,fy,fr,kind,col in [(0.140,0.150,0.057,"f",YELLOW),(0.205,0.112,0.028,"f",PINK),
        (0.858,0.138,0.042,"f",BLUE),(0.915,0.405,0.022,"f",GRAPE),(0.138,0.842,0.051,"r",GRAPE),
        (0.205,0.882,0.019,"f",GREEN),(0.862,0.836,0.053,"f",GREEN)]:
        bx,by,br=fx*S,fy*S,fr*S
        if kind=="r": circ(d,bx,by,br,outline=col,width=int(0.023*S))
        else: circ(d,bx,by,br,fill=col)
    return im

SPEC=[("ach-firstgame",m_sparkle,1.6),("ach-perfect",m_check,1.6),("ach-century",m_diamond,1.7),
      ("ach-streak7",m_flame,1.7),("ach-streak30",m_crown,1.6),("ach-fullpie",m_pie,1.6),
      ("ach-sharp",m_target,1.6),("ach-explorer",m_arrow,1.7),("ach-scholar",m_book,1.6)]
imgs=[]
for name,mark,msz in SPEC:
    img=render(512*4,mark,msz).resize((512,512),Image.LANCZOS).convert("RGB")
    img.save(f"tools/branding/gamecenter/{name}.png"); imgs.append(img); print("wrote",name)
# montage 3x3 for verification
M=Image.new("RGB",(512*3,512*3),(255,255,255))
for i,im in enumerate(imgs): M.paste(im,((i%3)*512,(i//3)*512))
M.resize((900,900)).save("/tmp/ach_montage.png"); print("montage /tmp/ach_montage.png")
