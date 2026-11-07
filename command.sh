#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

cat > tests/test_neural_source.py <<'PY'
import unittest,torch
from argon_core.source import GlottalExcitationNet

class SourceTests(unittest.TestCase):
    def test_shape_and_gradient_with_real_carrier(self):
        m=GlottalExcitationNet(sample_rate=24000,hop=240)
        f0=torch.tensor([[120.,122.,0.,125.,124.]])
        e=torch.ones_like(f0)*.3
        carrier=torch.linspace(-1,1,5*240)[None]
        y=m(f0,e,aperiodic=carrier)
        self.assertEqual(tuple(y.shape),(1,1200))
        self.assertTrue(torch.isfinite(y).all())
        y.square().mean().backward()
        self.assertTrue(any(p.grad is not None and torch.isfinite(p.grad).all() for p in m.parameters()))

    def test_unvoiced_is_silent_without_real_carrier(self):
        m=GlottalExcitationNet(sample_rate=24000,hop=240)
        y=m(torch.zeros(1,8),torch.ones(1,8)*.5)
        self.assertLess(float(y.detach().abs().max()),1e-7)

    def test_unvoiced_uses_real_carrier_when_present(self):
        m=GlottalExcitationNet(sample_rate=24000,hop=240)
        carrier=torch.sin(torch.linspace(0,300,8*240))[None]
        y=m(torch.zeros(1,8),torch.ones(1,8)*.5,aperiodic=carrier)
        self.assertGreater(float(y.detach().std()),1e-3)

if __name__=='__main__':unittest.main()
PY

PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest  tests.test_neural_source tests.test_neural_bottleneck tests.test_neural_filter tests.test_neural_losses  tests.test_neural_engine tests.test_neural_split tests.test_neural_real_aperiodic tests.test_neural_rvq_stability -v

echo '=== GAME DIRECTORIES ==='
find '/srv/Zombie Horror Game' -maxdepth 4 -type d 2>/dev/null | grep -Ei 'voice|dialog|speech|replic|реплик|голос|tts|character|персонаж|audio' | head -250 || true

echo '=== LARGE SPEECH-LIKE FILES ==='
find '/srv/Zombie Horror Game' -type f \( -iname '*.wav' -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.flac' \) -size +100k 2>/dev/null  | grep -Ei 'voice|dialog|speech|replic|реплик|голос|tts|виктор|александр|уч[её]н|bandit|диктор|scientist|victor|alexander'  | head -400 || true
