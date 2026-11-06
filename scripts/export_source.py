#!/usr/bin/env python3
"""Export only audited source, with reproducible ZIP metadata and no xattrs."""
from pathlib import Path
import argparse,hashlib,json,zipfile
from check_privacy import PUBLIC_FILES,audit
def export(root,destination):
 root=Path(root).resolve();destination=Path(destination).resolve()
 if destination.exists():raise ValueError('Destination already exists; choose a new file.')
 snapshot={}
 result=audit(root,snapshot=snapshot)
 if not result['passed']:raise ValueError('Privacy audit failed; run scripts/check_privacy.py for redacted findings.')
 destination.parent.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(destination,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=9)as archive:
  for relative in sorted(PUBLIC_FILES):
   item=zipfile.ZipInfo('naruto-native-launcher/'+relative,date_time=(1980,1,1,0,0,0));item.create_system=3;item.external_attr=0o100644<<16;item.extra=b'';item.comment=b'';archive.writestr(item,snapshot[relative],compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
 with zipfile.ZipFile(destination)as archive:
  assert sorted(archive.namelist())==sorted('naruto-native-launcher/'+n for n in PUBLIC_FILES)
  assert all(not i.extra and not i.comment for i in archive.infolist())
 return dict(file=destination.name,files=len(PUBLIC_FILES),sha256=hashlib.sha256(destination.read_bytes()).hexdigest(),audit_passed=True)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('destination',type=Path);p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);a=p.parse_args();print(json.dumps(export(a.root,a.destination),indent=2))
