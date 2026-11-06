#!/usr/bin/env python3
"""Fail-closed source export audit. Findings never print matched values."""
from pathlib import Path
import argparse,json,re,subprocess

PUBLIC_FILES=(
 '.gitignore','LICENSE','README.md','PRIVACY.md',
 'Sources/Core.swift','Sources/main.swift','scripts/build.py',
 'scripts/check_privacy.py','scripts/export_source.py',
 'tests/test_import.py','tests/test_privacy.py',
)
PATTERNS={
 'private-home-path':re.compile(rb'/'+rb'Users/[^\s\x00<>"\'\[\]]+|/'+rb'home/[^\s\x00<>"\'\[\]]+|[A-Z]:\\Users\\[^\s\x00<>"\']+'),
 'temporary-user-path':re.compile(rb'/'+rb'(?:private/)?var/folders/[a-z0-9_/.-]{8,}',re.I),
 'credential-prefix':re.compile(rb'(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})'),
 'private-key':re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'),
 'credential-assignment':re.compile(rb'''(?im)(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[=:]\s*["']([A-Za-z0-9_+/=-]{16,})["']'''),
 'email-address':re.compile(rb'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'),
 'private-network-address':re.compile(rb'\b(?:192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3})\b'),
}

def scan(data):
 for category,pattern in PATTERNS.items():
  for match in pattern.finditer(data):
   if category=='email-address' and match.group().lower().endswith(b'@users.noreply.github.com'):continue
   yield category,match.start()

def audit(root, *, snapshot=None):
 root=Path(root).resolve();findings=[];files=[]
 for relative in PUBLIC_FILES:
  path=root/relative
  if not path.is_file():findings.append(dict(file=relative,category='required-file-missing'));continue
  if any(p.is_symlink()for p in [path,*path.parents]if p!=root and root in p.parents)or not path.resolve().is_relative_to(root):
   findings.append(dict(file=relative,category='symlink-or-path-escape'));continue
  data=path.read_bytes()
  try:data.decode('utf-8')
  except UnicodeDecodeError:findings.append(dict(file=relative,category='non-text-file'));continue
  if b'\0'in data:findings.append(dict(file=relative,category='binary-data-in-source'));continue
  files.append(relative)
  if snapshot is not None:snapshot[relative]=data
  for category,offset in scan(data):
   findings.append(dict(file=relative,line=data[:offset].count(b'\n')+1,category=category))
 return dict(scope='explicit-source-allowlist',checked_files=files,findings=findings,passed=not findings)
def git_audit(root):
 root=Path(root).resolve();findings=[]
 def git(*args):return subprocess.run(['git','--no-replace-objects','-C',str(root),*args],capture_output=True)
 check=git('rev-parse','--show-toplevel')
 if check.returncode or Path(check.stdout.decode().strip()).resolve()!=root:return [dict(category='dedicated-repository-required')]
 shallow=git('rev-parse','--is-shallow-repository')
 if shallow.returncode or shallow.stdout.strip()!=b'false':findings.append(dict(category='complete-git-history-required'))
 for key in ['user.name','user.email']:
  value=git('config','--local','--get',key).stdout.strip()
  if not value:findings.append(dict(category='explicit-repository-identity-required',field=key))
  elif key=='user.email'and not value.lower().endswith(b'@users.noreply.github.com'):findings.append(dict(category='github-noreply-email-required',field=key))
 for role in ('AUTHOR','COMMITTER'):
  identity=git('var',f'GIT_{role}_IDENT')
  match=re.match(rb'^(.*?) <([^<>]+)> ',identity.stdout)
  if identity.returncode or not match or not match[2].lower().endswith(b'@users.noreply.github.com'):
   findings.append(dict(category='effective-noreply-identity-required',field=role.lower()))
  elif match[1].decode(errors='replace').casefold()==Path.home().name.casefold() or any(scan(match[1])):
   findings.append(dict(category='private-effective-git-name',field=role.lower()))
 index=git('ls-files','--stage','-z')
 if index.returncode:
  findings.append(dict(category='git-index-unreadable'))
 for raw in filter(None,index.stdout.split(b'\0')):
  header,path=raw.split(b'\t',1)
  mode,oid,stage=header.decode().split()
  relative=path.decode(errors='replace')
  if relative not in PUBLIC_FILES:
   findings.append(dict(category='unexpected-tracked-file',file=relative));continue
  if stage!='0' or mode not in ('100644','100755'):
   findings.append(dict(category='unsafe-git-index-entry',file=relative));continue
  size=git('cat-file','-s',oid)
  if size.returncode or not size.stdout.strip().isdigit() or int(size.stdout)>4*1024*1024:
   findings.append(dict(category='unreadable-or-large-index-blob',file=relative));continue
  blob=git('cat-file','blob',oid)
  if blob.returncode or b'\0' in blob.stdout or not is_utf8(blob.stdout):
   findings.append(dict(category='non-text-index-blob',file=relative));continue
  for category,offset in scan(blob.stdout):
   findings.append(dict(category='index-'+category,file=relative,line=blob.stdout[:offset].count(b'\n')+1))
 log=git('log','--all','--format=%H%x00%an%x00%ae%x00%cn%x00%ce%x00%B%x00%x1e')
 if log.returncode:findings.append(dict(category='git-history-unreadable'))
 if log.returncode==0:
  for record in log.stdout.split(b'\x1e'):
   fields=record.strip().split(b'\0')
   if len(fields)<6:continue
   commit=fields[0].decode(errors='replace')
   if any(fields[i].decode(errors='replace').casefold()==Path.home().name.casefold() for i in (1,3)):
    findings.append(dict(category='private-history-git-name',commit=commit))
   for index,label in [(2,'author'),(4,'committer')]:
    if not fields[index].lower().endswith(b'@users.noreply.github.com'):findings.append(dict(category='non-noreply-commit-email',commit=commit,field=label))
   for category,pattern in PATTERNS.items():
    if any(pattern.search(value)for value in [fields[1],fields[3],*fields[5:]]):findings.append(dict(category='history-'+category,commit=commit))
  # Search every historical blob, including files removed from the current tree.
  objects=git('rev-list','--objects','--all')
  if objects.returncode:findings.append(dict(category='git-history-objects-unreadable'))
  for row in objects.stdout.splitlines():
   oid=row.split(b' ',1)[0].decode();kind=git('cat-file','-t',oid)
   if kind.returncode:findings.append(dict(category='git-history-object-unreadable',object=oid));continue
   if kind.stdout.strip()!=b'blob':continue
   size=git('cat-file','-s',oid)
   if size.returncode or not size.stdout.strip().isdigit() or int(size.stdout)>4*1024*1024:findings.append(dict(category='large-or-unreadable-history-blob',object=oid));continue
   blob=git('cat-file','blob',oid)
   if blob.returncode or b'\0' in blob.stdout or not is_utf8(blob.stdout):
    findings.append(dict(category='non-text-history-blob',object=oid));continue
   for category in sorted({category for category,_ in scan(blob.stdout)}):
    findings.append(dict(category='history-'+category,object=oid))
 return findings

def is_utf8(data):
 try:data.decode('utf-8');return True
 except UnicodeDecodeError:return False
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('root',nargs='?',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--git',action='store_true');a=p.parse_args();result=audit(a.root)
 if a.git:result['findings']+=git_audit(a.root);result['passed']=not result['findings']
 print(json.dumps(result,indent=2));raise SystemExit(0 if result['passed']else 1)
