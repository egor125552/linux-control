#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
PUB='/srv/era-audio/argon-neural-v2-ab'

echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true
PID=$(systemctl show -p MainPID --value argon-neural-v2.service)
ps -p "$PID" -o pid,etime,%cpu,%mem,rss,stat,args || true

echo '=== CURRENT LOG / NAN CHECK ==='
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import json,math,torch
p=Path('results/ARGON Neural 2 long.log')
rows=[]
for line in p.read_text(errors='ignore').splitlines():
    if 'ARGON_V2_EPOCH ' not in line: continue
    try: rows.append(json.loads(line.split('ARGON_V2_EPOCH ',1)[1]))
    except: pass
print('ROWS',len(rows))
for r in rows[-12:]:
    print(json.dumps(r,ensure_ascii=False))
if rows:
    print('CURRENT_EPOCH',rows[-1].get('epoch'))
    finite_train=[r for r in rows if isinstance(r.get('g'),(int,float)) and math.isfinite(float(r['g']))]
    print('LATEST_FINITE_TRAIN_EPOCH',finite_train[-1].get('epoch') if finite_train else None)
    vals=[r for r in rows if isinstance(r.get('val'),(int,float)) and math.isfinite(float(r['val']))]
    if vals:
        best=min(vals,key=lambda r:float(r['val']))
        print('BEST_FINITE_VAL_EPOCH',best.get('epoch'),'BEST_FINITE_VAL',best.get('val'))
        print('BEST_EXPERIMENTAL',best.get('val_by_speaker',{}).get('experimental'))
    first_bad=next((r for r in rows if isinstance(r.get('val'),float) and not math.isfinite(r['val'])),None)
    print('FIRST_NONFINITE_VAL_EPOCH',first_bad.get('epoch') if first_bad else None)

for ck in ['results/ARGON Neural 2 Long.pt','results/ARGON Neural 2 Long Latest.pt']:
    if not Path(ck).exists(): continue
    o=torch.load(ck,map_location='cpu',weights_only=True)
    bad=[]
    total=0
    for k,v in o.get('state',{}).items():
        if torch.is_tensor(v):
            total+=v.numel()
            if not torch.isfinite(v).all():
                bad.append((k,int((~torch.isfinite(v)).sum())))
    m=o.get('metadata',{})
    print('CHECKPOINT',ck,'epoch',m.get('epoch'),'best_epoch',m.get('best_epoch'),'best_val',m.get('best_val'),'BAD_TENSORS',bad[:20],'TOTAL_PARAMS',total)
PY

echo '=== BUILD ZIP WITH PYTHON ==='
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import zipfile,json,math
pub=Path('/srv/era-audio/argon-neural-v2-ab')
log=Path('/srv/ARGON-VC/results/ARGON Neural 2 long.log')
rows=[]
for line in log.read_text(errors='ignore').splitlines():
    if 'ARGON_V2_EPOCH ' in line:
        try: rows.append(json.loads(line.split('ARGON_V2_EPOCH ',1)[1]))
        except: pass
status=pub/'Состояние обучения.txt'
lines=['ARGON Neural 2','']
if rows:
    last=rows[-1]
    vals=[r for r in rows if isinstance(r.get('val'),(int,float)) and math.isfinite(float(r['val']))]
    lines += [
        f'Текущая эпоха: {last.get("epoch")}',
        f'Текущая ошибка обучения: {last.get("g")}',
    ]
    if vals:
        best=min(vals,key=lambda r:float(r['val']))
        lines += [
            f'Лучшая контрольная эпоха: {best.get("epoch")}',
            f'Лучшая контрольная ошибка: {best.get("val")}',
            f'Экспериментальный голос на лучшей эпохе: {best.get("val_by_speaker",{}).get("experimental")}',
        ]
    bad=[r for r in rows if isinstance(r.get('val'),float) and not math.isfinite(r['val'])]
    if bad:
        lines.append(f'Первая нечисловая контрольная ошибка: эпоха {bad[0].get("epoch")}')
lines += ['','В архиве лежат все текущие WAV для сравнения.']
status.write_text('\n'.join(lines),encoding='utf-8')

zip_path=pub/'ARGON Neural 2 A-B тесты.zip'
if zip_path.exists(): zip_path.unlink()
files=sorted(pub.glob('*.wav'))+[status]
with zipfile.ZipFile(zip_path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for f in files:
        z.write(f,arcname=f.name)
print('ZIP',zip_path,zip_path.stat().st_size,'FILES',len(files))
for f in files:
    print('INZIP',f.name,f.stat().st_size)
PY

echo '=== HTTP ==='
URL='https://169-58-224-216.sslip.io/era-audio/argon-neural-v2-ab/ARGON%20Neural%202%20A-B%20%D1%82%D0%B5%D1%81%D1%82%D1%8B.zip'
curl -ksS -o /dev/null -w 'ZIP_HTTP %{http_code} %{size_download}\n' "$URL"
