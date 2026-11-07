#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

systemctl stop argon-neural-long.service 2>/dev/null || true
pkill -TERM -f 'argon_core.neural_longtrain' 2>/dev/null || true
sleep 1

cat > /srv/ARGON-VC/run-argon-neural-long.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
exec /srv/era-audio/venv/bin/python -u -m argon_core.neural_longtrain   'models/ARGON Neural all voices.txt'   'results/ARGON Neural Base.pt'   'results/ARGON Neural Long 1000.pt'   --epochs 1000   --steps 96   --threads 4   --crop .75   --lr 0.00005   --val-every 5   --patience-checks 1000000   --checkpoint-every 10   > 'results/ARGON Neural long.log' 2>&1
SH
chmod 755 /srv/ARGON-VC/run-argon-neural-long.sh

cat > /etc/systemd/system/argon-neural-long.service <<'UNIT'
[Unit]
Description=ARGON Neural 1000 epoch multispeaker training
After=network.target

[Service]
Type=simple
WorkingDirectory=/srv/ARGON-VC
ExecStart=/srv/ARGON-VC/run-argon-neural-long.sh
User=root
Nice=5
Restart=no
Environment=PYTHONPATH=/srv/ARGON-VC
Environment=OMP_NUM_THREADS=4
Environment=MKL_NUM_THREADS=4
Environment=OPENBLAS_NUM_THREADS=1

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
rm -f 'results/ARGON Neural long.log' 'results/ARGON Neural Long 1000.pt' 'results/ARGON Neural Long 1000 Latest.pt'
systemctl start argon-neural-long.service
sleep 4

echo '=== SERVICE ==='
systemctl --no-pager --full status argon-neural-long.service | sed -n '1,70p' || true
echo '=== PROCESS COUNT ==='
ps -eo args | grep 'argon_core.neural_longtrain' | grep -v grep | wc -l
echo '=== LOG ==='
tail -40 'results/ARGON Neural long.log' 2>/dev/null || true
