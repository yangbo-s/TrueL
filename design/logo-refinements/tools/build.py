from pathlib import Path
from html import escape
import json
R=Path(__file__).resolve().parent.parent
G={(g['family'],g['char']):g for g in json.loads((R/'glyphs.json').read_text())}
INK='#111111'; ACCENT='#169B8B'
OPTIONS=[
 {'id':'1A','name':'紧凑联字','family':'inter','font':'Inter ExtraBold','weight':800,'kind':'tl','drop':0,'size':560},
 {'id':'1B','name':'舒展联字','family':'manrope','font':'Manrope ExtraBold','weight':800,'kind':'tl','drop':.065,'size':540},
 {'id':'1C','name':'书卷联字','family':'lora','font':'Lora Bold','weight':700,'kind':'tl','drop':0,'size':570},
 {'id':'3A','opening':'rotate-closing','name':'紧凑句读','family':'manrope','font':'Manrope ExtraBold','weight':800,'kind':'quotes','dy':.43,'gap':.50,'size':545},
 {'id':'3B','name':'平衡句读','family':'lora','font':'Lora Bold','weight':700,'kind':'quotes','dy':0,'gap':.45,'size':535},
 {'id':'3C','name':'流动句读','family':'sourceserif4','font':'Source Serif 4 Black','weight':900,'kind':'quotes','dy':.28,'gap':.42,'size':555},
]

def path(g,fill,tx=0,ty=0,scale=1):
 return f'<path fill="{fill}" transform="translate({tx:.4f} {ty:.4f}) scale({scale:.6f})" d="{g["d"]}"/>'

def make(o):
 if o['kind']=='tl':
  t,l=G[o['family'],'T'],G[o['family'],'L']
  bx,by,bw,bh=t['bounds'];lx,ly,lw,lh=l['bounds']
  dx=sum(t['stem'])/2-sum(l['stem'])/2; dy=bh*o['drop']
  left=min(bx,lx+dx);top=min(by,ly+dy);right=max(bx+bw,lx+lw+dx);bottom=max(by+bh,ly+lh+dy)
  if o['id']=='1C':
   joined=json.loads((R/'1C-contour.json').read_text())
   black=path(joined,INK)
   accent_shape=path(joined,ACCENT)
  else:
   black=path(t,INK)+path(l,INK,dx,dy)
   accent_shape=path(l,ACCENT,dx,dy)
  edge=max(t['stem'][1],l['stem'][1]+dx)+1.0
  clip_top=bottom-lh*.36
  color=f'<clipPath id="accent-{o["id"]}"><rect x="{edge:.4f}" y="{clip_top:.4f}" width="{right-edge+20:.4f}" height="{bottom-clip_top+10:.4f}"/></clipPath><g clip-path="url(#accent-{o["id"]})">'+accent_shape+'</g>'
 else:
  l,r=G[o['family'],'’' if o.get('opening')=='rotate-closing' else '‘'],G[o['family'],'’']
  lx,ly,lw,lh=l['bounds'];rx,ry,rw,rh=r['bounds']
  target=360;sl=target/lh;sr=target/rh
  dx=lw*sl+o['gap']*lw*sl;dy=target*o['dy']
  left=0;top=0;right=dx+rw*sr;bottom=dy+target
  opening=path(l,INK,-lx*sl,-ly*sl,sl)
  if o.get('opening')=='rotate-closing':
   opening=f'<g transform="translate({lw*sl:.4f} {target}) rotate(180)">'+opening+'</g>'
  black=opening+path(r,INK,dx-rx*sr,dy-ry*sr,sr)
  cut=dy+target*.72
  color=f'<clipPath id="accent-{o["id"]}"><rect x="{dx-1:.4f}" y="{cut:.4f}" width="{rw*sr+2:.4f}" height="{target:.4f}"/></clipPath><g clip-path="url(#accent-{o["id"]})">'+path(r,ACCENT,dx-rx*sr,dy-ry*sr,sr)+'</g>'
 s=o['size']/max(right-left,bottom-top)
 # An optical nudge balances the long L foot against the shared stem.
 cx=512-(left+right)*s/2-(7 if o['kind']=='tl' else 0)
 cy=512-(top+bottom)*s/2
 transform=f'translate({cx:.4f} {cy:.4f}) scale({s:.6f})'
 return f'<g transform="{transform}">{black}</g>',f'<g transform="{transform}">{color}</g>'

def svg(o,content,plate=False):
 bg='<rect x="0" y="0" width="1024" height="1024" rx="224" fill="#FFFFFF"/>' if plate else ''
 return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-labelledby="title"><title id="title">TrueL {o["id"]} {o["name"]}</title><metadata>Glyph source: {escape(o["font"])} {o["weight"]}. Original outlines extracted with CoreText; positioned, rotated where noted, and color-clipped.</metadata>{bg}{content}</svg>'

for o in OPTIONS:
 black,color=make(o)
 master=R/'native'/o['id']/'AppIcon.icon';(master/'Assets').mkdir(parents=True,exist_ok=True)
 (master/'Assets/ink.svg').write_text(svg(o,black))
 (master/'Assets/accent.svg').write_text(svg(o,color))
 conf={'fill':{'solid':'srgb:1.00000,1.00000,1.00000,1.00000'},'groups':[{'layers':[{'glass':False,'image-name':'accent.svg','name':'accent'},{'glass':False,'image-name':'ink.svg','name':'glyph'}],'shadow':{'kind':'none','opacity':0},'translucency':{'enabled':False,'value':0}}],'supported-platforms':{'squares':['macOS']}}
 (master/'icon.json').write_text(json.dumps(conf,indent=2)+'\n')
 (R/f'{o["id"]}.svg').write_text(svg(o,black+color,True))
 (R/f'{o["id"]}-mark.svg').write_text(svg(o,black+color))
(R/'variants.json').write_text(json.dumps(OPTIONS,ensure_ascii=False,indent=2)+'\n')
print('Built 6 font-based variants with SVG outlines and Icon Composer masters')
