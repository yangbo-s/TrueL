from pathlib import Path
import subprocess,json
r=Path(__file__).resolve().parent.parent;tool='/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool'
for o in json.loads((r/'variants.json').read_text()):
 for size in [512,64,32,16]:
  out=r/'renders'/f"{o['id']}{'' if size==512 else '-'+str(size)}.png"
  p=subprocess.run([tool,str(r/'native'/o['id']/'AppIcon.icon'),'--export-image','--output-file',str(out),'--platform','macOS','--rendition','Default','--width',str(size),'--height',str(size),'--scale','1'],capture_output=True,text=True)
  if p.returncode: raise SystemExit(p.stderr+p.stdout)
 print('Rendered',o['id'],flush=True)
