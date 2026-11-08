#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== CRITIC SMOKE ==='
rm -f 'results/ARGON Neural 2 Smoke.pt' 'results/ARGON Neural 2 Smoke Latest.pt'
OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -u -m argon_neural_v2.train  'models/ARGON Neural 2 smoke.txt' 'results/ARGON Neural 2 Smoke.pt'  --epochs 1 --steps 2 --threads 1 --crop .35 --lr 0.00008 --critic-start 1  --val-every 1 --checkpoint-every 1
test -s 'results/ARGON Neural 2 Smoke Latest.pt'

echo '=== LIMIT V1 TO ONE CPU, KEEP IT RUNNING ==='
systemctl set-property argon-neural-long.service CPUQuota=100%
systemctl is-active argon-neural-long.service || true

echo '=== CREATE V2 SERVICE ==='
systemctl stop argon-neural-v2.service 2>/dev/null || true
pkill -TERM -f 'argon_neural_v2.train.*ARGON Neural 2' 2>/dev/null || true
sleep 1

cat > /srv/ARGON-VC/run-argon-neural-v2.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
exec /srv/era-audio/venv/bin/python -u -m argon_neural_v2.train   'models/ARGON Neural all voices.txt'   'results/ARGON Neural 2 Long.pt'   --epochs 50000   --steps 48   --threads 3   --crop .5   --lr 0.00008   --critic-start 20   --val-every 2   --checkpoint-every 5   --seed-speaker-checkpoint 'results/ARGON Neural Continuous 50000.pt'   > 'results/ARGON Neural 2 long.log' 2>&1
SH
chmod 755 /srv/ARGON-VC/run-argon-neural-v2.sh

cat > /etc/systemd/system/argon-neural-v2.service <<'UNIT'
[Unit]
Description=ARGON Neural 2 long multispeaker training
After=network.target argon-neural-long.service

[Service]
Type=simple
WorkingDirectory=/srv/ARGON-VC
ExecStart=/srv/ARGON-VC/run-argon-neural-v2.sh
User=root
Nice=0
Restart=on-failure
RestartSec=5
CPUQuota=300%
Environment=PYTHONPATH=/srv/ARGON-VC
Environment=OMP_NUM_THREADS=3
Environment=MKL_NUM_THREADS=3
Environment=OPENBLAS_NUM_THREADS=1

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable argon-neural-v2.service >/dev/null
rm -f 'results/ARGON Neural 2 Long.pt' 'results/ARGON Neural 2 Long Latest.pt' 'results/ARGON Neural 2 long.log'
systemctl start argon-neural-v2.service
sleep 4

echo '=== STATUS ==='
systemctl --no-pager --full status argon-neural-long.service | sed -n '1,25p' || true
systemctl --no-pager --full status argon-neural-v2.service | sed -n '1,35p' || true
echo '=== CPU PROCESSES ==='
ps -eo pid,etime,%cpu,%mem,rss,stat,args | grep -E 'argon_core.neural_continue|argon_neural_v2.train' | grep -v grep || true
echo '=== V2 LOG ==='
tail -30 'results/ARGON Neural 2 long.log' 2>/dev/null || true
