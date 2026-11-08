#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

OUTDIR='/srv/era-audio/argon-neural-export'
TXT="$OUTDIR/ARGON Neural 2 вся логика.txt"
ZIP="$OUTDIR/ARGON Neural 2 вся логика.zip"
mkdir -p "$OUTDIR"
rm -f "$TXT" "$ZIP"

FILES=(
  'argon_neural_v2/__init__.py'
  'argon_neural_v2/features.py'
  'argon_neural_v2/source.py'
  'argon_neural_v2/content.py'
  'argon_neural_v2/tract.py'
  'argon_neural_v2/postfilter.py'
  'argon_neural_v2/critic.py'
  'argon_neural_v2/losses.py'
  'argon_neural_v2/engine.py'
  'argon_neural_v2/train.py'
  'argon_core/__init__.py'
  'argon_core/audio.py'
  'argon_core/corpus.py'
  'argon_core/neural_features.py'
  'argon_core/source.py'
  'argon_core/bottleneck.py'
  'argon_core/filter.py'
  'argon_core/losses.py'
  'argon_core/neural_engine.py'
  'argon_core/neural_train.py'
  'argon_core/neural_pretrain.py'
  'argon_core/neural_longtrain.py'
)

{
  printf 'ARGON Neural 2\n'
  printf 'Полная логика текущей ветки на момент экспорта.\n'
  printf 'Без тестов, весов, журналов и результатов обучения.\n\n'
  printf 'Файлов: %s\n\n' "${#FILES[@]}"
  for f in "${FILES[@]}"; do
    if [ ! -f "$f" ]; then
      echo "MISSING $f" >&2
      exit 1
    fi
    printf '\n================================================================================\n'
    printf 'ФАЙЛ: %s\n' "$f"
    printf '================================================================================\n\n'
    cat "$f"
    printf '\n'
  done
} > "$TXT"

python3 - <<'PY'
from pathlib import Path
import zipfile
out=Path('/srv/era-audio/argon-neural-export')
txt=out/'ARGON Neural 2 вся логика.txt'
zip_path=out/'ARGON Neural 2 вся логика.zip'
with zipfile.ZipFile(zip_path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    z.write(txt,arcname=txt.name)
with zipfile.ZipFile(zip_path) as z:
    assert z.namelist()==[txt.name]
print('TXT_BYTES',txt.stat().st_size)
print('ZIP_BYTES',zip_path.stat().st_size)
print('ZIP_CONTENTS',zipfile.ZipFile(zip_path).namelist())
PY

echo '=== INCLUDED FILES ==='
printf '%s\n' "${FILES[@]}"

echo '=== VERIFY ==='
python3 - <<'PY'
from pathlib import Path
p=Path('/srv/era-audio/argon-neural-export/ARGON Neural 2 вся логика.txt')
text=p.read_text(encoding='utf-8')
assert 'tests/' not in text
assert '\nФАЙЛ: tests/' not in text
print('NO_TEST_FILES_INCLUDED')
print('FILE_HEADERS',text.count('ФАЙЛ: '))
PY

echo '=== TRAINING STILL ACTIVE ==='
systemctl is-active argon-neural-long.service || true

echo '=== HTTP ==='
curl -ksS -o /dev/null -w 'txt %{http_code} %{size_download}\n'   'https://169-58-224-216.sslip.io/era-audio/argon-neural-export/ARGON%20Neural%202%20%D0%B2%D1%81%D1%8F%20%D0%BB%D0%BE%D0%B3%D0%B8%D0%BA%D0%B0.txt'
curl -ksS -o /dev/null -w 'zip %{http_code} %{size_download}\n'   'https://169-58-224-216.sslip.io/era-audio/argon-neural-export/ARGON%20Neural%202%20%D0%B2%D1%81%D1%8F%20%D0%BB%D0%BE%D0%B3%D0%B8%D0%BA%D0%B0.zip'
