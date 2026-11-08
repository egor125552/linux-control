#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
PUB='/srv/era-audio/argon-neural-v2-ab'
ZIP="$PUB/ARGON Neural 2 A-B тесты.zip"

echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true

echo '=== V2 PROCESS ==='
PID=$(systemctl show -p MainPID --value argon-neural-v2.service)
ps -p "$PID" -o pid,etime,%cpu,%mem,rss,stat,args || true

echo '=== SPEED / PROGRESS ==='
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import json,re,statistics,torch
p=Path('results/ARGON Neural 2 long.log')
rows=[]
for line in p.read_text(errors='ignore').splitlines():
    if 'ARGON_V2_EPOCH ' not in line: continue
    try:
        rows.append(json.loads(line.split('ARGON_V2_EPOCH ',1)[1]))
    except Exception:
        pass
print('EPOCH_ROWS',len(rows))
if rows:
    last=rows[-1]
    print('CURRENT_EPOCH',last.get('epoch'))
    print('CURRENT_G',last.get('g'))
    print('CURRENT_NATURAL',last.get('natural'))
    vals=[r for r in rows if 'val' in r]
    if vals:
        best=min(vals,key=lambda r:r['val'])
        print('BEST_EPOCH',best.get('epoch'))
        print('BEST_VAL',best.get('val'))
        print('BEST_EXPERIMENTAL',best.get('val_by_speaker',{}).get('experimental'))
        print('LATEST_VAL',vals[-1].get('val'))
        print('LATEST_EXPERIMENTAL',vals[-1].get('val_by_speaker',{}).get('experimental'))
    tail=rows[-12:]
    times=[float(r.get('seconds',0)) for r in tail if r.get('seconds') is not None]
    epochs=[int(r['epoch']) for r in tail]
    if len(times)>=2 and epochs[-1]>epochs[0]:
        sec_per_epoch=(times[-1]-times[0])/(epochs[-1]-epochs[0])
        print('SECONDS_PER_EPOCH',round(sec_per_epoch,3))
        print('EPOCHS_PER_HOUR',round(3600/sec_per_epoch,2))
        print('STEPS_PER_SECOND_APPROX',round(48/sec_per_epoch,3))
    print('LAST_ROWS')
    for r in rows[-8:]:
        print(json.dumps(r,ensure_ascii=False))
for ck in ['results/ARGON Neural 2 Long.pt','results/ARGON Neural 2 Long Latest.pt']:
    if Path(ck).exists():
        o=torch.load(ck,map_location='cpu',weights_only=True)
        m=o.get('metadata',{})
        print('CHECKPOINT',ck,'epoch',m.get('epoch'),'best_epoch',m.get('best_epoch'),'best_val',m.get('best_val'))
PY

echo '=== PACKAGE WAV FILES ==='
rm -f "$ZIP"
STATUS="$PUB/Состояние обучения.txt"
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import json,torch
log=Path('/srv/ARGON-VC/results/ARGON Neural 2 long.log')
rows=[]
for line in log.read_text(errors='ignore').splitlines():
    if 'ARGON_V2_EPOCH ' in line:
        try: rows.append(json.loads(line.split('ARGON_V2_EPOCH ',1)[1]))
        except: pass
out=Path('/srv/era-audio/argon-neural-v2-ab/Состояние обучения.txt')
lines=['ARGON Neural 2','']
if rows:
    last=rows[-1]
    vals=[r for r in rows if 'val' in r]
    lines.append(f'Текущая эпоха: {last.get("epoch")}')
    lines.append(f'Текущая ошибка обучения: {last.get("g")}')
    if vals:
        best=min(vals,key=lambda r:r["val"])
        lines.append(f'Лучшая контрольная эпоха: {best.get("epoch")}')
        lines.append(f'Лучшая контрольная ошибка: {best.get("val")}')
        lines.append(f'Экспериментальный голос на лучшей эпохе: {best.get("val_by_speaker",{}).get("experimental")}')
lines.append('')
lines.append('В ZIP лежат все текущие WAV для A/B прослушивания.')
out.write_text('\n'.join(lines),encoding='utf-8')
PY
cd "$PUB"
zip -9 -q "ARGON Neural 2 A-B тесты.zip" ./*.wav "./Состояние обучения.txt"
ls -lh "$ZIP"
echo WAV_COUNT=$(find "$PUB" -maxdepth 1 -type f -name '*.wav' | wc -l)
echo '=== ZIP CONTENTS ==='
unzip -l "$ZIP" | sed -n '1,80p'

echo '=== HTTP ==='
URL='https://169-58-224-216.sslip.io/era-audio/argon-neural-v2-ab/ARGON%20Neural%202%20A-B%20%D1%82%D0%B5%D1%81%D1%82%D1%8B.zip'
curl -ksS -o /dev/null -w 'ZIP_HTTP %{http_code} %{size_download}\n' "$URL"
