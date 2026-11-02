from pathlib import Path
import hashlib
root=Path(__file__).resolve().parent.parent
count=0
for line in (root/'SHA256SUMS').read_text(encoding='utf-8').splitlines():
    digest,name=line.split('  ',1)
    rel=Path(name)
    if rel.is_absolute() or '..' in rel.parts:raise SystemExit('Invalid path: '+name)
    p=root/rel
    if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=digest:raise SystemExit('Mismatch: '+name)
    count+=1
print('SOURCE_INTEGRITY=PASS',count,'files')
