"""Black-box ISO import checks. Fixtures are synthetic, never contain game data."""
from pathlib import Path
import argparse,hashlib,json,os,struct,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('launcher',type=Path);p.add_argument('--real-iso',type=Path);p.add_argument('--expected-profile',default='europe-sles-55605');a=p.parse_args();binary=a.launcher.resolve()
def record(name,sector,size,directory=False):
 n=33+len(name)+(0 if len(name)%2 else 1);b=bytearray(n);b[0]=n
 struct.pack_into('<I',b,2,sector);struct.pack_into('>I',b,6,sector);struct.pack_into('<I',b,10,size);struct.pack_into('>I',b,14,size)
 b[25]=2 if directory else 0;b[28:32]=b'\x01\x00\x00\x01';b[32]=len(name);b[33:33+len(name)]=name;return bytes(b)
def image(serial='SLES_556.05',cycle=False):
 data=bytearray(24*2048);pvd=memoryview(data)[16*2048:17*2048];pvd[:7]=b'\x01CD001\x01';pvd[40:72]=b'SYNTHETIC TEST'.ljust(32,b' ')
 struct.pack_into('<I',pvd,80,24);struct.pack_into('>I',pvd,84,24)
 root=record(b'\0',20,2048,True);pvd[156:156+len(root)]=root
 config=f'BOOT2 = cdrom0:\\{serial};1\r\nVER = 1.00\r\nVMODE = PAL\r\n'.encode();data[21*2048:21*2048+len(config)]=config
 elf=bytearray(64);elf[:6]=b'\x7fELF\x01\x01';elf[18]=8;elf[20]=1;data[22*2048:22*2048+64]=elf
 entries=root+record(b'\1',20,2048,True)+record(b'SYSTEM.CNF;1',21,len(config))+record((serial+';1').encode(),22,64)
 if cycle:entries+=record(b'LOOP',20,2048,True)
 data[20*2048:20*2048+len(entries)]=entries;return data
with tempfile.TemporaryDirectory(prefix='naruto-launcher-iso-')as tmp:
 d=Path(tmp);resources=d/'Resources';resources.mkdir();(resources/'engines.json').write_text('{"schema":1,"profiles":[]}')
 def run(mode,iso):return subprocess.run([str(binary),'--resources',str(resources),mode,str(iso)],text=True,capture_output=True,timeout=20)
 cases=[]
 def check(name,content,expected,mode='--inspect'):
  path=d/(name+'.iso');path.write_bytes(content);r=run(mode,path);assert (r.returncode==0)==expected,(name,r.stdout,r.stderr);cases.append(name);return r
 good=image();r=check('synthetic-european',good,True);j=json.loads(r.stdout);assert j['inspection']['serial']=='SLES_556.05'and j['inspection']['isoSHA256']==hashlib.sha256(good).hexdigest();assert j.get('matchedProfile')is None and not j['originalEuropeanValidated']
 check('same-serial-is-not-authorization',good,False,'--plan')
 check('truncated-image',good[:34000],False)
 broken=good.copy();broken[16*2048+1]=0;check('bad-pvd',broken,False)
 broken=good.copy();broken[16*2048+84]^=1;check('inconsistent-sector-count',broken,False)
 broken=good.copy();broken[20*2048+33+2*len(record(b'\0',20,2048,True))]=255;check('bad-directory-name-length',broken,False)
 check('directory-cycle',image(cycle=True),False)
 def append_root(data,records):
  cursor=20*2048
  while data[cursor]:cursor+=data[cursor]
  data[cursor:cursor+len(records)]=records
  return data
 aliases=record(b'ALIAS-A',23,2048,True)+record(b'ALIAS-B',23,2048,True)
 r=check('directory-extent-reused',append_root(good.copy(),aliases),False)
 assert 'repetido' in r.stderr
 large=good+bytes(4*1024*1024+16*2048)
 children=b''.join(record(f'CHILD-{i}'.encode(),23+i,4*1024*1024,True) for i in range(9))
 r=check('directory-global-read-limit',append_root(large,children),False)
 assert 'limite de leitura' in r.stderr
 fifo=d/'pipe.iso';os.mkfifo(fifo)
 r=run('--inspect',fifo);assert r.returncode!=0 and 'arquivo ISO regular' in r.stderr
 cases.append('special-file-rejected-without-blocking')
 check('other-region-no-profile',image('SLUS_999.99'),False,'--plan')
 broken=good.copy();broken[22*2048+18]=3;check('non-mips-elf',broken,False)
 # An engine profile matching only the disc hash is insufficient: ELF must match.
 (resources/'engines.json').write_text(json.dumps(dict(schema=1,profiles=[dict(id='bad-profile',title='Test',scope='original-european',isoSHA256=hashlib.sha256(good).hexdigest(),elfSHA256='0'*64,engine='missing-engine',engineSHA256='0'*64,libraries={},videoMode='pal',minimumMacOS='15.0',hotKernels=False)])))
 check('elf-profile-mismatch',good,False,'--plan')
 if a.real_iso:
  r=subprocess.run([str(binary),'--inspect',str(a.real_iso.resolve())],capture_output=True,text=True,timeout=60);assert r.returncode==0,r.stderr;j=json.loads(r.stdout);assert j['matchedProfile']==a.expected_profile and j['originalEuropeanValidated'];cases.append('real-reference-fingerprint')
  plans=[]
  for cadence in [None,'pal']:
   command=[str(binary),'--plan',str(a.real_iso.resolve())]+(['--video-mode',cadence]if cadence else[])
   r=subprocess.run(command,capture_output=True,text=True,timeout=60);assert r.returncode==0,r.stderr;plan=json.loads(r.stdout);plans.append(plan)
   assert '--pal' in plan['arguments'] and '--ntsc' not in plan['arguments']
   assert plan['environment']['PS2_PACING']=='original'and plan['environment']['PS2_SCALE']=='1'
   assert 'PS2_EU_NTSC_VIDEO' not in plan['environment']
   cases.append('cadence-plan-'+(cadence or'profile-default'))
  assert plans[0]['arguments']==plans[1]['arguments'];cases.append('explicit-pal-keeps-save-location')
  for cadence in ['ntsc','invalid']:
   r=subprocess.run([str(binary),'--plan',str(a.real_iso.resolve()),'--video-mode',cadence],capture_output=True,text=True,timeout=60)
   assert r.returncode!=0 and 'apenas a cadência PAL' in r.stderr;cases.append(f'{cadence}-cadence-rejected')
 print(json.dumps(dict(passed=len(cases),cases=cases),indent=2))
