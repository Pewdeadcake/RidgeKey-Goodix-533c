"""Export only checksum-listed source files; exclude local logs and state."""
from pathlib import Path
import hashlib, stat, zipfile
root=Path(__file__).resolve().parent.parent
entries=[]
for line in (root/'SHA256SUMS').read_text(encoding='utf-8').splitlines():
    digest,name=line.split('  ',1)
    rel=Path(name)
    if rel.is_absolute() or '..' in rel.parts:raise SystemExit('Invalid path: '+name)
    p=root/rel
    if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=digest:raise SystemExit('Mismatch: '+name)
    entries.append(p)
entries.append(root/'SHA256SUMS')
out=root/'Releases';out.mkdir(exist_ok=True)
archive=out/'RidgeKey-Goodix-533c-source.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in entries:
        info=zipfile.ZipInfo.from_file(p,('RidgeKey-Goodix-533c/'+p.relative_to(root).as_posix()))
        info.create_system=3
        executable=p.read_bytes().startswith(b'#!') or p.name in {'ridgekey-biostore-check','ridgekey-biostore-reader'}
        info.external_attr=(stat.S_IFREG|(0o755 if executable else 0o644))<<16
        info.compress_type=zipfile.ZIP_DEFLATED
        z.writestr(info,p.read_bytes())
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
digest=hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix('.zip.sha256').write_text(digest+'  '+archive.name+'\n',encoding='utf-8')
print(archive)
print(digest)
