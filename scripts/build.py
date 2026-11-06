#!/usr/bin/env python3
"""Build the native launcher. No game files are included by default."""
from pathlib import Path
import argparse,hashlib,json,os,plistlib,re,shutil,subprocess
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=ROOT/'build/Naruto Native Launcher.app');p.add_argument('--european-manifest',type=Path);p.add_argument('--sdl',type=Path);a=p.parse_args()
assert bool(a.european_manifest)==bool(a.sdl),'Provide the European manifest and SDL together.'
game_iso=None
if a.european_manifest:
 manifest=json.loads(a.european_manifest.read_text());assert manifest['validated']is True and manifest['video_mode']=='pal','Validate the European engine before packaging.'
 game_iso=Path(manifest['iso']);game_engine=a.european_manifest.resolve().parents[1]/manifest['binary'];assert game_engine.is_file()
app=a.output.resolve();assert not app.exists(),'Use a fresh output path to preserve existing builds.'
mac=app/'Contents/MacOS';res=app/'Contents/Resources';fw=app/'Contents/Frameworks';mac.mkdir(parents=True);res.mkdir();fw.mkdir()
cache=ROOT/'build/module-cache';cache.mkdir(parents=True,exist_ok=True)
subprocess.run(['xcrun','swiftc','-swift-version','5','-O','-target','arm64-apple-macosx15.0','-module-cache-path',str(cache),str(ROOT/'Sources/Core.swift'),str(ROOT/'Sources/main.swift'),'-o',str(mac/'NarutoLauncher'),'-framework','AppKit','-framework','CryptoKit'],check=True)
subprocess.run(['strip','-S',str(mac/'NarutoLauncher')],check=True)
catalog={'schema':1,'profiles':[]};(res/'engines.json').write_text(json.dumps(catalog,indent=2)+'\n')
minimum='15.0';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
if game_iso:
 inspection=json.loads(subprocess.check_output([str(mac/'NarutoLauncher'),'--resources',str(res),'--inspect',str(game_iso.resolve())],text=True))['inspection']
 assert inspection['serial']=='SLES_556.05'
 profile_id='europe-sles-55605'
 assert inspection['isoSHA256']==manifest['iso_sha256']and inspection['elfSHA256']==manifest['elf_sha256'];assert sha(game_engine)==manifest['binary_sha256']
 engine=res/f'Engines/{profile_id}/ps2run';engine.parent.mkdir(parents=True);shutil.copy2(game_engine,engine)
 library=res/'Libraries/libSDL2-2.0.0.dylib';library.parent.mkdir();shutil.copy2(a.sdl,library)
 old='/opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib'
 deps=subprocess.check_output(['otool','-L',str(engine)],text=True);assert old in deps,'Inspect SDL dependencies before changing the build recipe.'
 subprocess.run(['install_name_tool','-change',old,'@executable_path/../../Libraries/libSDL2-2.0.0.dylib',str(engine)],check=True)
 load_commands=subprocess.check_output(['otool','-l',str(engine)],text=True)
 for rpath in re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset \d+\)',load_commands):
  if rpath.startswith('/opt/homebrew/'):
   subprocess.run(['install_name_tool','-delete_rpath',rpath,str(engine)],check=True)
 subprocess.run(['install_name_tool','-id','@rpath/libSDL2-2.0.0.dylib',str(library)],check=True)
 for binary in [library,engine]:
  binary.chmod(binary.stat().st_mode | 0o200)
  subprocess.run(['strip','-S',str(binary)],check=True)
  subprocess.run(['codesign','--force','--sign','-',str(binary)],check=True)
 deps='\n'.join(subprocess.check_output(['otool','-L',str(engine)],text=True).splitlines()[1:]);assert '/opt/homebrew'not in deps and '/Users/'not in deps
 load_commands=subprocess.check_output(['otool','-l',str(engine)],text=True)
 assert all(rpath.startswith(('@','/usr/lib','/System/Library/')) for rpath in re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset \d+\)',load_commands))
 catalog['profiles'].append(dict(id=profile_id,title='Ultimate Ninja 5 — Europa',scope='original-european',isoSHA256=inspection['isoSHA256'],elfSHA256=inspection['elfSHA256'],engine=str(engine.relative_to(res)),engineSHA256=sha(engine),libraries={str(library.relative_to(res)):sha(library)},videoMode='pal',minimumMacOS='26.0',hotKernels=True,frameCounter='617afc,194'))
 (res/'engines.json').write_text(json.dumps(catalog,indent=2)+'\n');minimum='26.0'
 licenses=res/'Licenses';licenses.mkdir();runtime_license=ROOT.parent/'ps2-web-recomp-eval/LICENSE'
 if runtime_license.exists():shutil.copy2(runtime_license,licenses/'ps2-web-recomp-MIT.txt')
 play_notice=runtime_license.parent/'runtime/src/ipu/NOTICE'
 if play_notice.is_file():shutil.copy2(play_notice,licenses/'Play-BSD-2-Clause.txt')
 candidates=[Path('/opt/homebrew/opt/sdl2/share/licenses/sdl2/LICENSE.txt'),Path('/opt/homebrew/opt/sdl2/LICENSE.txt'),Path('/opt/homebrew/opt/sdl2/LICENSE')]
 for candidate in candidates:
  if candidate.exists():shutil.copy2(candidate,licenses/'SDL2.txt');break
info={'CFBundleExecutable':'NarutoLauncher','CFBundleIdentifier':'org.narutonative.launcher','CFBundleName':'Naruto Native Launcher','CFBundleDisplayName':'Naruto Native Launcher','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.1.7','CFBundleVersion':'2180','LSMinimumSystemVersion':minimum,'NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication'}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info));subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(json.dumps({'app':str(app),'profile_count':len(catalog['profiles']),'original_european_validated':bool(a.european_manifest)},indent=2))
