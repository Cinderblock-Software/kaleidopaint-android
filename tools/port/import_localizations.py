#!/usr/bin/env python3
# Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
"""Convert upstream translations and Android additions to resources.
macOS plutil parses Apple's .strings files without a lossy custom parser.
"""
from pathlib import Path
import json,subprocess,xml.etree.ElementTree as ET
import sys
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'upstream/Source - SwiftUI/KaleidoPaint/localizations/strings'
RES=ROOT/'app/src/main/res'
MAPPING={
 'new_dot_color':'New dot color','new_line_color':'New line color','new_fill_color':'New fill color',
 'dot_size':'Dot size','line_thickness':'Line thickness','delete_dot':'Delete dot','delete_line':'Delete line','delete_fill':'Delete fill',
 'point_style':'Control point style','rectangle':'Rectangle','image_size':'Image size','transparent_background':'Transparent background',
 'brush_color':'Brush color','help_double_tap':'DoubleTap-tip','realign':'Realign','edit_mode':'EditMode','draw_mode':'DrawMode',
 'make_smooth':'Smooth','make_corner':'Corner','split_point':'Split control point',
 'delete_point':'Delete control point','aspect_ratio':'Aspect ratio','shear':'Shear',
 'export_tile':'Tileable rectangle','symmetry_guides':'Grid','color_by_symmetry':'Color by symmetry',
 'line_smoothing':'Line smoothing','clear':'Clear','fill_color':'Fill color',
 'match_color':'Change everything of same color','match_width':'Change everything of same thickness',
 'delete_matching_color':'Delete everything of same color','brush_width':'Brush thickness','apply':'Apply',
 'help_editor_title':'Editor-HowTo-long','help_control_points':'Control-Points',
 'help_control_drag':'Control-Points-Drag','help_control_tap':'Control-Points-Tap',
 'help_no_arc_taps':'No-Arc-Taps','help_performance':'Performance-Tip',
 'help_bad':'Caption-Bad','help_good':'Caption-Good','help_bad_caption':'Subcaption-Bad',
 'help_good_caption':'Subcaption-Good',
 'notation':'Notation','notation_none':'noNotation','notation_orbifold':'orbifold','notation_crystallographic':'crystallographic','help_tutorials':'Tutorials','help_gallery':'Image Gallery','help_gallery_text':'Image-Gallery-text',
}
REUSED_KEYS={'lock_drawing': 'LockDrawing', 'unlock': 'UnlockDrawing', 'clear_drawing': 'Clear', 'save': 'Save', 'color_grid': 'Grid', 'help_one_finger': 'OneFinger-tip', 'help_two_fingers': 'TwoFingers-tip'}
MAPPING.update(REUSED_KEYS)
LOCALES={'ar':'ar','de':'de','es':'es','fr':'fr','it':'it','ja':'ja','nl':'nl','pt-PT':'pt-rPT',
 'ru':'ru','zh-Hans':'b+zh+Hans','zh-Hant':'b+zh+Hant'}
def upstream(locale):
 shared=ROOT/'upstream/Shared/Geometry Games - Swift/Geometry Games localizable strings'/(locale+'.lproj')/'GeometryGamesLocalizable.strings'
 a=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(shared)]))
 b=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(SOURCE/(locale+'.lproj')/'Localizable.strings')]))
 return {**a,**b}
def quoted(text):
 return '"'+text.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n').replace('\r','')+'"'
def write(path,root):
 ET.indent(root,space='    ')
 path.write_text('<?xml version="1.0" encoding="utf-8"?>\n<!-- KaleidoPaint © Jeff Weeks, GPLv2+; Android port GPLv3+. See upstream for translator credits. -->\n'+ET.tostring(root,encoding='unicode')+'\n')
base_path=RES/'values/strings.xml'
base=ET.parse(base_path).getroot()
english=upstream('en')
# Mapped object placeholders use Android numbered string arguments.
def mapped_value(table,key):
 return table[key].replace('%@','%1$s')
# Add the original illustrated-help captions to the base resource set.
existing={e.attrib.get('name'):e for e in base if e.tag=='string'}
for name,key in MAPPING.items():
 if name not in existing:
  node=ET.SubElement(base,'string',name=name); node.text=quoted(mapped_value(english,key)); existing[name]=node
for name,key in REUSED_KEYS.items(): existing[name].text=quoted(mapped_value(english,key))
required=sorted(name for name,e in existing.items() if e.attrib.get('translatable')!='false' and name not in MAPPING and name!='symmetry_format')
if '--report' in sys.argv:
 print(json.dumps({name:existing[name].text for name in required},ensure_ascii=False,indent=2));sys.exit(0)
# TSV files are the editable source; JSON is a generated review artifact.
extras={locale:{} for locale in LOCALES}
for name in ('android-labels.tsv','android-prose.tsv'):
 lines=(ROOT/'tools/localization'/name).read_text().splitlines()
 languages=[v.strip() for v in lines[0].lstrip('#').split('|')[1:]]
 if set(languages)!=set(LOCALES): raise SystemExit('Invalid language header in '+name)
 for line in lines[1:]:
  if not line.strip() or line.startswith('#'): continue
  key,*values=line.split('|')
  if len(values)!=len(languages): raise SystemExit('Invalid column count for '+key)
  for locale,value in zip(languages,values):
   if key in extras[locale]: raise SystemExit('Duplicate '+key)
   extras[locale][key]=value
(ROOT/'tools/localization/android-strings.json').write_text(json.dumps(extras,ensure_ascii=False,indent=2)+'\n')
for locale,directory in LOCALES.items():
 translated=upstream(locale)
 own=extras[locale]
 missing=set(required)-set(own)
 if missing: raise SystemExit(f'{locale}: missing {sorted(missing)}')
 redundant=set(own)-set(required)
 if redundant: raise SystemExit(f'{locale}: redundant Android translations {sorted(redundant)}')
 out=ET.Element('resources')
 for name in existing:
  if existing[name].attrib.get('translatable')=='false': continue
  if name in MAPPING: value=mapped_value(translated,MAPPING[name])
  elif name=='symmetry_format': value=translated['Symmetry']+' %1$s'
  else: value=own[name]
  # Numbered formatting arguments must match the English contract.
  import re
  expected=set(re.findall(r'%[0-9]+\$[sd]',existing[name].text or ''))
  actual=set(re.findall(r'%[0-9]+\$[sd]',value))
  if expected!=actual: raise SystemExit(f'{locale}/{name}: format mismatch {expected} vs {actual}')
  node=ET.SubElement(out,'string',name=name); node.text=quoted(value)
 folder=RES/('values-'+directory);folder.mkdir(exist_ok=True)
 write(folder/'strings.xml',out)
write(base_path,base)
print(f'Imported {len(MAPPING)} upstream keys and {len(required)} Android strings into {len(LOCALES)} locales')
