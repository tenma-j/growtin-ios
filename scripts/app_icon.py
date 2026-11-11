# Génère l'icône de l'app : « G’ » en verre liquide vert sur fond noir (police Nunito Black, licence OFL).
# Usage : python3 scripts/app_icon.py <dossier contenant fonts/fontsource-nunito-…> 
import numpy as np, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
N=2048
def blur(a, r):
    im=Image.fromarray(np.clip(a*255,0,255).astype(np.uint8)) if a.dtype!=np.uint8 else Image.fromarray(a)
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)),dtype=np.float32)/255
import scipy.ndimage as ndi
def blurf(a,r):
    return ndi.gaussian_filter(a.astype(np.float32),r)
def glyph_mask(font_path, size_frac, quote_scale=1.0, gap=0.0, quote=u"’", dy=0.0):
    f=ImageFont.truetype(font_path,int(N*size_frac)); qf=ImageFont.truetype(font_path,int(N*size_frac*quote_scale))
    m=Image.new('L',(N,N),0); d=ImageDraw.Draw(m)
    gb=d.textbbox((0,0),"G",font=f); qb=d.textbbox((0,0),quote,font=qf)
    g=N*gap; total=(gb[2]-gb[0])+g+(qb[2]-qb[0])
    x=(N-total)/2-gb[0]; y=(N-(gb[3]-gb[1]))/2-gb[1]+N*dy
    d.text((x,y),"G",font=f,fill=255)
    d.text((x+gb[2]+g-qb[0], y+gb[1]-qb[1]),quote,font=qf,fill=255)
    return np.asarray(m,dtype=np.float32)/255
def render(mask, out, tint=(61,214,140), bevel=0.022):
    yy,xx=np.mgrid[0:N,0:N].astype(np.float32)/N
    bg=np.zeros((N,N,3),np.float32)+np.array([6,7,9])/255
    def blob(cx,cy,r,col,a):
        d=np.exp(-(((xx-cx)**2+(yy-cy)**2)/(r*r)))
        return d[...,None]*np.array(col)/255*a
    bg+=blob(0.5,0.55,0.40,(14,60,40),0.22)
    behind=bg*0.6+blob(0.30,0.28,0.20,(150,255,205),0.55)+blob(0.72,0.78,0.22,(20,170,105),0.8)
    # distance au bord (approx.) -> profil arrondi étroit, plateau au centre
    inside=ndi.distance_transform_edt(mask>0.5).astype(np.float32)/(N*bevel)
    h=np.sqrt(np.clip(1-(1-np.clip(inside,0,1))**2,0,1))
    h=blurf(h,N*0.0025)
    gy,gx=np.gradient(h)
    k=N*bevel*0.9; nx=-gx*k; ny=-gy*k; nz=np.ones_like(nx)
    l=np.sqrt(nx**2+ny**2+nz**2); nx/=l; ny/=l; nz/=l
    shift=N*0.05
    sx=np.clip((xx*N-nx*shift).astype(int),0,N-1); sy=np.clip((yy*N-ny*shift).astype(int),0,N-1)
    refr=behind[sy,sx]
    fres=np.clip(1-nz,0,1)
    t=np.array(tint)/255
    body=refr*0.9+t*(0.30+0.5*yy*0)[...,None]+t*(0.9*fres**0.7)[...,None]
    # teinte interne plus dense en bas (épaisseur du verre)
    body+=t*(0.22*yy)[...,None]
    L=np.array([-0.5,-0.7,0.5]); L/=np.linalg.norm(L)
    hv=L+np.array([0,0,1]); hv/=np.linalg.norm(hv)
    spec=np.clip(nx*hv[0]+ny*hv[1]+nz*hv[2],0,1)
    edge=fres**1.2
    rimTL=np.clip(-(nx*0.6+ny*0.8),0,1)*edge   # bord haut-gauche, très lumineux
    rimBR=np.clip(nx*0.6+ny*0.8,0,1)*edge       # bord bas-droit, liseré vert
    body+=(rimTL**1.3)[...,None]*np.array([0.95,1.0,0.97])*1.1
    body+=(rimBR**1.6)[...,None]*t*0.9
    body+=(spec**80)[...,None]*0.9
    # reflet doux en haut de la lettre
    top=np.clip(1-(yy-0.30)/0.18,0,1)*np.clip(inside,0,1)
    body+=(top*0.10)[...,None]
    a=blurf(mask,1.0)[...,None]
    shadow=blurf(np.roll(mask,int(N*0.02),axis=0),N*0.03)[...,None]
    img=bg*(1-0.6*shadow)+blurf(mask,N*0.06)[...,None]*t*0.12
    img=img*(1-a)+body*a
    img=np.clip(img,0,1)
    Image.fromarray((img*255).astype(np.uint8)).resize((1024,1024),Image.LANCZOS).save(out)
if __name__=="__main__":
    F=sys.argv[1]+'/fonts/'
    variants={
     'A':(F+'fontsource-fraunces-5.3.0/files/fraunces-latin-900-normal.woff',0.60,1.0,0.0),
     'B':(F+'fontsource-nunito-5.3.0/files/nunito-latin-900-normal.woff',0.64,1.0,-0.004),
     'C':(F+'fontsource-dm-serif-display-5.3.0/files/dm-serif-display-latin-400-normal.woff',0.66,1.0,0.0),
     'D':(F+'fontsource-sora-5.3.0/files/sora-latin-800-normal.woff',0.56,1.0,0.012),
    }
    for k,(p,sz,q,g) in variants.items():
        render(glyph_mask(p,sz,q,g),sys.argv[1]+f'/glass{k}.png')
    s=Image.new('RGB',(4*420,420),'white')
    for i,k in enumerate('ABCD'): s.paste(Image.open(sys.argv[1]+f'/glass{k}.png').resize((410,410)),(i*420,5))
    s.save(sys.argv[1]+'/glass.png')
