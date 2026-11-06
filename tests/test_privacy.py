"""Privacy regressions: source export and deleted historical secrets."""
from pathlib import Path
import json,os,shutil,subprocess,sys,tempfile,zipfile
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from check_privacy import PUBLIC_FILES,audit,git_audit
from export_source import export
cases=[]
assert audit(ROOT)['passed'],audit(ROOT);cases.append('clean-source')
with tempfile.TemporaryDirectory(prefix='launcher-privacy-test-')as tmp:
 d=Path(tmp);source=d/'source';source.mkdir()
 for relative in PUBLIC_FILES:
  p=source/relative;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/relative,p)
 secret='ghp_'+'a'*36
 (source/'.env').write_text('TOKEN='+secret)
 result=export(source,d/'source.zip')
 with zipfile.ZipFile(d/'source.zip')as archive:
  assert len(archive.infolist())==len(PUBLIC_FILES)
  assert all(i.date_time==(1980,1,1,0,0,0)and not i.extra and not i.comment for i in archive.infolist())
  assert all(not name.endswith('.env')and'__MACOSX'not in name for name in archive.namelist())
 cases.append('allowlist-archive-excludes-extra-secrets-and-metadata')
 file=source/'README.md';original=file.read_bytes()
 file.write_bytes(original+b'\n'+secret.encode());r=audit(source);assert not r['passed']and secret not in json.dumps(r)
 try:export(source,d/'rejected.zip');raise AssertionError('Secret exported')
 except ValueError:pass
 assert not(d/'rejected.zip').exists();cases.append('secret-blocked-without-value-disclosure')
 file.write_bytes(original+b'\n/'+b'Users/'+b'private-user/Documents/example.txt');assert any(x['category']=='private-home-path'for x in audit(source)['findings']);cases.append('private-path-blocked')
 file.write_bytes(original+b'\0');assert any(x['category']=='binary-data-in-source'for x in audit(source)['findings']);cases.append('binary-in-source-blocked')
 file.unlink();file.symlink_to(ROOT/'README.md');assert any(x['category']=='symlink-or-path-escape'for x in audit(source)['findings']);file.unlink();file.write_bytes(original);cases.append('symlink-blocked')
 env=dict(os.environ,GIT_CONFIG_GLOBAL=os.devnull,GIT_CONFIG_NOSYSTEM='1',GIT_AUTHOR_NAME='Audit Fixture',GIT_COMMITTER_NAME='Audit Fixture',GIT_AUTHOR_EMAIL='fixture@users.noreply.github.com',GIT_COMMITTER_EMAIL='fixture@users.noreply.github.com')
 def git(*args):return subprocess.run(['git','-C',str(source),*args],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True)
 git('init','-q');assert any(x['category']=='explicit-repository-identity-required'for x in git_audit(source));cases.append('implicit-git-identity-blocked')
 git('config','--local','user.name','Audit Fixture');git('config','--local','user.email','fixture@users.noreply.github.com')
 file.write_bytes(original+b'\n'+secret.encode());git('add','README.md');file.write_bytes(original)
 r=git_audit(source);assert any(x['category']=='index-credential-prefix'for x in r)and secret not in json.dumps(r)
 cases.append('staged-secret-detected-after-working-copy-restored')
 git('add',*PUBLIC_FILES);git('commit','-qm','Clean source fixture');assert not git_audit(source),git_audit(source);cases.append('explicit-noreply-git-history-accepted')
 old=os.environ.get('GIT_AUTHOR_EMAIL')
 try:
  os.environ['GIT_AUTHOR_EMAIL']='fixture@'+'example.invalid'
  assert any(x['category']=='effective-noreply-identity-required'for x in git_audit(source))
 finally:
  if old is None:os.environ.pop('GIT_AUTHOR_EMAIL',None)
  else:os.environ['GIT_AUTHOR_EMAIL']=old
 cases.append('environment-author-identity-checked')
 file=source/'README.md';file.write_text('Removed fixture: '+secret);git('add','README.md');git('commit','-qm','Synthetic secret fixture');file.write_bytes(original);git('add','README.md');git('commit','-qm','Restore clean source')
 r=git_audit(source);assert any(x['category']=='history-credential-prefix'for x in r)and secret not in json.dumps(r);cases.append('deleted-historical-secret-detected')
print(json.dumps(dict(passed=len(cases),cases=cases),indent=2))
