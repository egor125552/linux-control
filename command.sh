#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== OLD PROCESS ==='
PID=$(cat 'results/ARGON Neural base.pid' 2>/dev/null || true)
if [ -n "${PID}" ]; then ps -o pid,etime,%cpu,rss,stat,args -p "${PID}" || true; fi
tail -20 'results/ARGON Neural base.log' 2>/dev/null || true

cat > /srv/ARGON-VC/run-argon-neural-base.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
exec /srv/era-audio/venv/bin/python -u -m argon_core.neural_pretrain   'models/ARGON Neural corpus.txt' 'results/ARGON Neural Base.pt'   --epochs 1 --threads 4 --crop .75 --lr 0.00015   > 'results/ARGON Neural base.log' 2>&1
SH
chmod 755 /srv/ARGON-VC/run-argon-neural-base.sh

systemctl stop argon-neural-base.service 2>/dev/null || true
rm -f /etc/systemd/system/argon-neural-base.service
cat > /etc/systemd/system/argon-neural-base.service <<'UNIT'
[Unit]
Description=ARGON Neural base pretraining

[Service]
Type=simple
WorkingDirectory=/srv/ARGON-VC
ExecStart=/srv/ARGON-VC/run-argon-neural-base.sh
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
rm -f 'results/ARGON Neural Base.pt' 'results/ARGON Neural base.log'
systemctl start argon-neural-base.service
sleep 3
echo '=== SERVICE ==='
systemctl --no-pager --full status argon-neural-base.service | sed -n '1,70p' || true
echo '=== LOG ==='
tail -30 'results/ARGON Neural base.log' 2>/dev/null || true
