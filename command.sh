#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== V1 STAYS ACTIVE ==='
systemctl is-active argon-neural-long.service || true

echo '=== FREEZE CURRENT V2 CONTROL BRANCH ==='
systemctl stop argon-neural-v2.service || true
mkdir -p 'results/ARGON Neural 2 shortcut branch backup'
cp -f argon_neural_v2/*.py 'results/ARGON Neural 2 shortcut branch backup/' 2>/dev/null || true
cp -f 'results/ARGON Neural 2 Long.pt' 'results/ARGON Neural 2 shortcut branch backup/' 2>/dev/null || true
cp -f 'results/ARGON Neural 2 Long Latest.pt' 'results/ARGON Neural 2 shortcut branch backup/' 2>/dev/null || true
cp -f 'results/ARGON Neural 2 long.log' 'results/ARGON Neural 2 shortcut branch backup/' 2>/dev/null || true

cat > tests/test_neural_v2_generative.py <<'PY'
import inspect,unittest,torch
from pathlib import Path

class GenerativeArchitectureRequirements(unittest.TestCase):
    def test_tract_has_no_raw_source_wav_input(self):
        from argon_neural_v2.tract import DeepVocalTract
        params=inspect.signature(DeepVocalTract.forward).parameters
        self.assertNotIn('source_wav',params)

    def test_engine_accepts_separate_content_audio(self):
        from argon_neural_v2.engine import ArgonNeuralV2
        params=inspect.signature(ArgonNeuralV2.forward).parameters
        self.assertIn('content_wav',params)

    def test_training_has_timbre_perturbation(self):
        from argon_neural_v2.train import perturb_timbre
        torch.manual_seed(2)
        x=torch.randn(1,12000)*.03
        y=perturb_timbre(x,24000,seed=123)
        self.assertEqual(y.shape,x.shape)
        self.assertTrue(torch.isfinite(y).all())
        self.assertGreater(float((x-y).abs().mean()),1e-4)

    def test_micro_critic_accepts_8192_samples(self):
        from argon_neural_v2.critic import MicroVoiceCritic
        c=MicroVoiceCritic()
        x=torch.randn(1,8192)*.02
        logits,features=c(x)
        self.assertTrue(logits)
        self.assertTrue(features)
        self.assertTrue(all(torch.isfinite(z).all() for z in logits))

    def test_no_source_wav_shortcut_literal_in_tract(self):
        text=Path('/srv/ARGON-VC/argon_neural_v2/tract.py').read_text()
        self.assertNotIn('source_wav',text)
        self.assertNotIn('Z_src',text)

if __name__=='__main__':unittest.main()
PY

echo '=== EXPECTED RED TEST ==='
set +e
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest tests.test_neural_v2_generative -v
RC=$?
set -e
echo EXPECTED_FAILURE_RC=$RC
if [ "$RC" -eq 0 ]; then
  echo 'ERROR: old shortcut architecture unexpectedly passed new requirements'
  exit 1
fi

echo '=== V2 FROZEN, V1 ACTIVE ==='
systemctl is-active argon-neural-v2.service || true
systemctl is-active argon-neural-long.service || true
