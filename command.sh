#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
PUB=/srv/era-audio/argon-neural-v2-vocos-hd
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import torch
import torch.nn.functional as F
from argon_core.audio import read_audio
from argon_neural_v2.vocos_engine import ArgonStudioVC

pub=Path('/srv/era-audio/argon-neural-v2-vocos-hd')
ck=torch.load(pub/'ARGON Vocos HD v1.2.pt',map_location='cpu',weights_only=False)
m=ArgonStudioVC('cpu')
m.net.load_state_dict(ck['net'])
m.bank_keys=ck['bank_keys']
m.bank_mels=ck['bank_mels']
m.target_f0_median=float(ck['target_f0_median'])
m.target_mel_mean=ck['target_mel_mean']
m.target_mel_std=ck['target_mel_std']
m.net.eval()

target=read_audio('/srv/ARGON-VC/data/ARGON uploads/Экспериментальный голос.mp3',24000)
# Positions deliberately different from the 24 evenly spaced training starts.
starts=[31,87,143,311]
knn_losses=[];net_losses=[]
with torch.inference_mode():
    for sec in starts:
        clip=target[int(sec*24000):int((sec+4)*24000)]
        d=m.extract_features(clip)
        k=m.kNN_match(d['wavlm'],top_k=16,temp=.12)
        p=m.net(d['wavlm'],k,d['f0'],d['energy'],d['voiced'])
        tgt=d['mel']
        def score(x):
            l1=F.l1_loss(x,tgt)
            dd=F.l1_loss(x[:,:,1:]-x[:,:,:-1],tgt[:,:,1:]-tgt[:,:,:-1])
            return float((l1+.8*dd).item())
        knn_losses.append(score(k));net_losses.append(score(p))
        print('clip',sec,'knn',round(knn_losses[-1],5),'net',round(net_losses[-1],5))
print('MEAN_KNN',sum(knn_losses)/len(knn_losses))
print('MEAN_NET',sum(net_losses)/len(net_losses))
print('NET_IMPROVEMENT_PERCENT',(sum(knn_losses)-sum(net_losses))/sum(knn_losses)*100)
print('BANK_FRAMES',m.bank_keys.shape[0])
PY
echo '=== HTTP ==='
for f in "ARGON Vocos HD v1.2 фраза.wav" "A-B Виктор и ARGON Vocos HD v1.2.wav" "Сравнение старый Vocos и HD v1.2.wav"; do
  u="https://169-58-224-216.sslip.io/era-audio/argon-neural-v2-vocos-hd/$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$f")"
  printf '%s ' "$f"
  curl -ksS -o /dev/null -w '%{http_code} %{size_download}\n' "$u"
done
