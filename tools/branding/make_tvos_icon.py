#!/usr/bin/env python3
"""tvOS 'App Icon & Top Shelf Image' brand assets from the approved Tidbits mark.
Landscape, layered (parallax: Back = coral+dots, Front = tile+T) per Apple's
imagestack format. BOTH app-icon roles (small 400x240 AND App Store 1280x768)
are imagestacks — actool crashes (cloneImageStack:toRepresentMarketingVariant:)
if the 1280x768 role is a flat imageset. Plus the Top Shelf images. Builds the
full .brandassets folder tree + Contents.json files into the asset catalog."""
import os, json
from PIL import Image, ImageDraw, ImageFont

CORAL=(255,116,111,255); CREAM=(252,245,233,255); INK=(35,30,26,255)
YELLOW=(255,201,60,255); BLUE=(45,91,255,255); GREEN=(47,203,138,255)
GRAPE=(139,92,246,255); PINK=(255,93,162,255)
FONT="/System/Library/Fonts/Supplemental/Arial Black.ttf"
CAT="TidbitsTrivia/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
SS=2

def rrect(d,b,r,**k): d.rounded_rectangle(b,radius=r,**k)
def circ(d,cx,cy,r,**k): d.ellipse([cx-r,cy-r,cx+r,cy+r],**k)
def Tglyph(S,color,hf):
    t=Image.new("RGBA",(S,S),(0,0,0,0)); dd=ImageDraw.Draw(t)
    f=ImageFont.truetype(FONT,int(0.55*S)); dd.text((S//2,S//2),"T",font=f,fill=color,anchor="mm")
    g=t.crop(t.getbbox()); h=int(hf*S); return g.resize((int(g.width*h/g.height),h),Image.LANCZOS)

def landscape(W,H,mode):
    """mode: 'back' (coral+dots, opaque), 'front' (tile+T, transparent)."""
    W,H=W*SS,H*SS
    im=Image.new("RGBA",(W,H),CORAL if mode=="back" else (0,0,0,0)); d=ImageDraw.Draw(im)
    side=0.80*H; tx0=W/2-side/2; ty0=H/2-side/2; tile=[tx0,ty0,tx0+side,ty0+side]
    if mode=="back":
        dots=[(tx0*0.40,H*0.24,side*0.085,"fill",YELLOW),(tx0*0.66,H*0.13,side*0.040,"fill",PINK),
              (tx0*0.34,H*0.74,side*0.075,"ring",GRAPE),(tx0*0.62,H*0.86,side*0.030,"fill",GREEN),
              (W-tx0*0.42,H*0.20,side*0.062,"fill",BLUE),(W-tx0*0.30,H*0.55,side*0.034,"fill",GRAPE),
              (W-tx0*0.46,H*0.80,side*0.078,"fill",GREEN)]
        for cx,cy,r,kind,col in dots:
            if kind=="ring": circ(d,cx,cy,r,outline=col,width=int(0.02*side))
            else: circ(d,cx,cy,r,fill=col)
    else:
        bw=0.040*side; so=0.026*side; tr=0.255*side
        rrect(d,[tile[0]+so,tile[1]+so,tile[2]+so,tile[3]+so],tr,fill=INK)
        rrect(d,tile,tr,fill=INK); rrect(d,[tx0+bw,ty0+bw,tx0+side-bw,ty0+side-bw],tr-bw*0.55,fill=CREAM)
        g=Tglyph(int(side),INK,0.345); gx=int(W/2-g.width/2); gy=int(H/2-g.height/2-0.012*side)
        im.alpha_composite(g,(gx,gy)); dr=0.030*side
        circ(d,W/2+0.125*side,gy+g.height-dr*0.6,dr,fill=CORAL)
    return im.resize((W//SS,H//SS),Image.LANCZOS)

def topshelf(W,H):
    W,H=W*SS,H*SS
    im=Image.new("RGBA",(W,H),CORAL); d=ImageDraw.Draw(im)
    g=Tglyph(H,(255,255,255,255),0.46)
    f=ImageFont.truetype(FONT,int(H*0.30)); word="TIDBITS"
    bb=d.textbbox((0,0),word,font=f); ww=bb[2]-bb[0]
    gap=int(H*0.10); total=g.width+gap+ww; x=(W-total)//2
    im.alpha_composite(g,(x,(H-g.height)//2))
    d.text((x+g.width+gap, H//2), word, font=f, fill=(255,255,255,255), anchor="lm")
    return im.resize((W//SS,H//SS),Image.LANCZOS)

def write_imageset(path, imgs):  # imgs: [(filename, PIL, scale)]
    os.makedirs(path,exist_ok=True)
    images=[]
    for fn,img,sc in imgs:
        img.convert("RGBA").save(os.path.join(path,fn)); images.append({"idiom":"tv","filename":fn,"scale":sc})
    json.dump({"images":images,"info":{"author":"xcode","version":1}}, open(os.path.join(path,"Contents.json"),"w"), indent=2)

def write_layer(stack, name, scaled):  # scaled: [(PIL, scale), ...]
    lp=os.path.join(stack,f"{name}.imagestacklayer"); os.makedirs(lp,exist_ok=True)
    json.dump({"info":{"author":"xcode","version":1}}, open(os.path.join(lp,"Contents.json"),"w"))
    write_imageset(os.path.join(lp,"Content.imageset"),
                   [(f"{name.lower()}-{sc}.png",img,sc) for img,sc in scaled])

def write_imagestack(path, layers):  # layers: [(name, [(PIL,scale),...]), ...] front-to-back
    os.makedirs(path,exist_ok=True)
    json.dump({"info":{"author":"xcode","version":1},
               "layers":[{"filename":f"{n}.imagestacklayer"} for n,_ in layers]},
              open(os.path.join(path,"Contents.json"),"w"), indent=2)
    for n,scaled in layers: write_layer(path, n, scaled)

# --- build the tree ---
os.makedirs(CAT,exist_ok=True)
# App Icon (small, 400x240): imagestack, layers at 1x + 2x
write_imagestack(os.path.join(CAT,"App Icon.imagestack"),
                 [("Front",[(landscape(400,240,"front"),"1x"),(landscape(800,480,"front"),"2x")]),
                  ("Back", [(landscape(400,240,"back"), "1x"),(landscape(800,480,"back"), "2x")])])
# App Icon - App Store (1280x768): ALSO an imagestack, single (1x) layers
write_imagestack(os.path.join(CAT,"App Icon - App Store.imagestack"),
                 [("Front",[(landscape(1280,768,"front"),"1x")]),
                  ("Back", [(landscape(1280,768,"back"), "1x")])])
# Top Shelf (1920x720 @1x, 3840x1440 @2x) + Wide (2320x720 @1x, 4640x1440 @2x)
write_imageset(os.path.join(CAT,"Top Shelf Image.imageset"), [("ts-1x.png",topshelf(1920,720),"1x"),("ts-2x.png",topshelf(3840,1440),"2x")])
write_imageset(os.path.join(CAT,"Top Shelf Image Wide.imageset"), [("tsw-1x.png",topshelf(2320,720),"1x"),("tsw-2x.png",topshelf(4640,1440),"2x")])
json.dump({"assets":[
    {"filename":"App Icon.imagestack","idiom":"tv","role":"primary-app-icon","size":"400x240"},
    {"filename":"App Icon - App Store.imagestack","idiom":"tv","role":"primary-app-icon","size":"1280x768"},
    {"filename":"Top Shelf Image Wide.imageset","idiom":"tv","role":"top-shelf-image-wide","size":"2320x720"},
    {"filename":"Top Shelf Image.imageset","idiom":"tv","role":"top-shelf-image","size":"1920x720"}],
    "info":{"author":"xcode","version":1}},
    open(os.path.join(CAT,"Contents.json"),"w"), indent=2)
print("wrote brand assets ->", CAT)
