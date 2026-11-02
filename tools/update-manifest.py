from pathlib import Path
import hashlib
root=Path(__file__).resolve().parent.parent
def excluded(p):
    rel=p.relative_to(root)
    return any(x in {'.git','__pycache__','Build-Output','Releases','_build','build'} for x in rel.parts) or p.name in {'SHA256SUMS','bundle-path.txt','.DS_Store','ridgekey-biostore-check','ridgekey-biostore-reader'} or p.name.startswith(('Build-20','Finish-20','Keychain-20','Collect-20','Persistence-20','.script-fix')) or p.suffix in {'.pyc','.print','.keychain','.keychain-db','.p12','.pem'}
lines=[]
for p in sorted(root.rglob('*')):
    if p.is_file() and not excluded(p):lines.append(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(root).as_posix()+'\n')
(root/'SHA256SUMS').write_bytes(''.join(lines).encode('utf-8'))
print('Updated',len(lines),'manifest entries; review changes before committing.')
