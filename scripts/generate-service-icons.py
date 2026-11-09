import argparse,re,json,math,hashlib,subprocess,tempfile
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageColor
parser=argparse.ArgumentParser(description='Regenerate the bundled icon atlas from checked-out icon repositories.')
parser.add_argument('--lobe', type=Path, required=True, help='Lobe Icons repository checkout')
parser.add_argument('--simple', type=Path, required=True, help='Simple Icons repository checkout')
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
lobe=args.lobe/'packages/static-png/light'
simple=args.simple
entries=[]
for f in ('Catalog.swift','ManualCatalog.swift'):
 entries+=re.findall(r'ServiceDef\(id: "([^"]+)", name: "([^"]+)"', (root/'Sources/CooltimeCore'/f).read_text())
known_lobe={p.stem for p in lobe.glob('*.png') if not p.stem.endswith(('-text','-color','-brand','-brand-color'))}
known_simple={p.stem for p in (simple/'icons').glob('*.svg')}
# Prefixes are matched only when they identify the same company or product.
overrides={
'aider':'','aider-local-usage':'','livekit-cloud-sessions':'livekit','intercom-fin-conversations':'intercom','openart-cli-balance':'',
'codex':'openai','sheet-11':'antigravity','sheet-86':'openai','sheet-87':'anthropic','sheet-90':'xai','sheet-93':'together','sheet-112':'',
'sheet-121':'','browserbase-usage':'','datadog-bits-usage':'datadog','jasper-api-usage':'',
'aws-bedrock-usage':'bedrock','azure-foundry-monitor-usage':'azureai','salesforce-wallet-usage':'',
'composio-project-usage':'','mistral-admin-spend-status':'mistral','microsoft365-copilot-report':'microsoft',
'thoughtspot-spotter-usage':'','kling-api-package-usage':'kling','gemini-api-request-usage':'gemini',
'vertex-token-monitoring':'vertexai','workspace-gemini-audit':'google','magnific-team-credits':'freepik',
'scenario-cu-usage':'','you-api-balance':'','fal-api-balance':'fal','figma-ai-usage':'figma',
'augment-credit-usage':'','opencode-go-usage':'opencode','huggingface-inference-usage':'huggingface',
'vercel-ai-gateway':'vercel','runway':'runway','luma':'luma','stability':'stability',
'copilot':'githubcopilot','sheet-13':'cursor','sheet-14':'cursor','sheet-17':'zedindustries',
'sheet-19':'','sheet-21':'replit','sheet-25':'','sheet-30':'','sheet-31':'',
'sheet-33':'firebase','sheet-35':'','sheet-38':'','sheet-42':'','sheet-43':'freepik',
'sheet-46':'','sheet-47':'runway','sheet-49':'kling','sheet-50':'luma','sheet-54':'hailuo',
'sheet-56':'google','sheet-58':'','sheet-62':'','sheet-63':'capcut','sheet-64':'topazlabs',
'sheet-66':'','sheet-74':'','sheet-76':'notion','sheet-78':'','sheet-79':'','sheet-84':'',
'sheet-88':'gemini','sheet-89':'mistral','sheet-91':'groq','sheet-92':'cerebras',
'sheet-94':'fireworks','sheet-95':'huggingface','sheet-97':'fal','sheet-99':'cloudflare',
'sheet-100':'bedrock','sheet-101':'vertexai','sheet-102':'azureai','sheet-106':'',
'sheet-107':'jina','sheet-110':'brave','sheet-115':'n8n','sheet-118':'microsoft',
'sheet-119':'google','sheet-124':'hubspot','sheet-125':'','sheet-127':'','sheet-128':'intercom',
'sheet-129':'zendesk','sheet-135':'livekit','sheet-141':'duolingo','sheet-142':'khanacademy',
'sheet-156':'linkedin','sheet-164':'autodesk','sheet-163':'autodesk',
'sheet-181':'microsoft','sheet-184':'microsoft',
}
for id,key in list(overrides.items()):
 if key and key not in known_lobe and key not in known_simple: print('BAD OVERRIDE',id,key)

def normalize(s):return re.sub(r'[^a-z0-9]','',s.lower())
def infer(name):
 base=re.split(r'[（(/]| 個人| Teams| Cloud| API| Web| AI| Enterprise| Agent| Inference',name)[0].strip()
 choices=[x for x in known_lobe if normalize(x)==normalize(base)]
 if choices:return sorted(choices)[0]
 choices=[x for x in known_simple if normalize(x)==normalize(base)]
 return sorted(choices)[0] if choices else ''

hexes={normalize(o['title']):o['hex'] for o in json.loads((simple/'data/simple-icons.json').read_text())}
font=next(str(p) for p in (Path('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'), Path('/System/Library/Fonts/Supplemental/Arial Bold.ttf')) if p.exists())
size=72; columns=12
atlas=Image.new('RGBA',(columns*size,math.ceil(len(entries)/columns)*size),(0,0,0,0))
manifest=[]
with tempfile.TemporaryDirectory() as tmp:
 for index,(id,name) in enumerate(entries):
  key=overrides.get(id,infer(name))
  source='lobe' if key in known_lobe else 'simple' if key in known_simple else 'monogram'
  tile=Image.new('RGBA',(size,size),(0,0,0,0));draw=ImageDraw.Draw(tile)
  if source!='monogram':
   draw.rounded_rectangle((1,1,70,70),radius=15,fill='#FFFFFF')
   if source=='lobe':
    iconpath=next((p for p in (lobe/f'{key}-color.png',lobe/f'{key}.png') if p.exists()))
    icon=Image.open(iconpath).convert('RGBA')
   else:
    output=Path(tmp)/(key+'.png')
    if not output.exists():subprocess.run(['inkscape',str(simple/'icons'/f'{key}.svg'),'--export-filename='+str(output),'--export-width=128','--export-height=128'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    icon=Image.open(output).convert('RGBA')
    rgb=ImageColor.getrgb('#'+hexes.get(normalize(key),'343B4C'))
    solid=Image.new('RGBA',icon.size,rgb+(255,))
    solid.putalpha(icon.getchannel('A'));icon=solid
   icon.thumbnail((54,54),Image.Resampling.LANCZOS)
   tile.alpha_composite(icon,((72-icon.width)//2,(72-icon.height)//2))
  else:
   digest=hashlib.sha256(id.encode()).digest()
   hue=digest[0]/256
   import colorsys
   rgb=tuple(round(c*255) for c in colorsys.hsv_to_rgb(hue,0.55,0.65))
   draw.rounded_rectangle((1,1,70,70),radius=15,fill=rgb+(255,))
   front=re.split(r'[（(/]',name)[0].strip()
   words=re.findall('[A-Za-z0-9]+',front)
   initials=(words[0][:2] if words else front[:1]).upper()
   if len(words)>1 and (words[0].lower() in ('google','microsoft','amazon','adobe','salesforce','github')):initials=(words[0][0]+words[1][0]).upper()
   initials=initials[:2]
   f=ImageFont.truetype(font,32 if len(initials)==1 else 25)
   draw.text((36,35),initials,font=f,anchor='mm',fill='#FFFFFF')
  atlas.alpha_composite(tile,((index%columns)*size,(index//columns)*size))
  manifest.append({'id':id,'name':name,'index':index,'source':source,'key':key})

out=root/'Sources/Cooltime/Resources';out.mkdir(parents=True,exist_ok=True)
atlas.save(out/'ServiceIcons.png',optimize=True)
(root/'Sources/Cooltime/ServiceIconCatalog.swift').write_text('''import Foundation

/// ServiceIcons.png: 12 columns of 72 px cells. Every catalog entry has an icon.
/// Source and fallback details are recorded in docs/service-icons.json.
enum ServiceIconCatalog {
    static let columns = 12
    static let cellSize = 72
    static let indices: [String: Int] = [
'''+''.join(f'        "{e["id"]}": {e["index"]},\n' for e in manifest)+'''    ]
}
''')
(root/'docs').mkdir(exist_ok=True)
(root/'docs/service-icons.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
from collections import Counter
print('Count',len(entries),Counter(x['source'] for x in manifest),'atlas bytes',(out/'ServiceIcons.png').stat().st_size)
print('Branded missing',[(x['id'],x['name']) for x in manifest if x['source']=='monogram'])
