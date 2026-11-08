#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
mkdir -p argon_v2

cat > tests/test_argon_v2_source.py <<'PY'
import unittest,torch
from argon_v2.source import HarmonicExcitation

class V2SourceTests(unittest.TestCase):
    def test_harmonic_source_shape_and_gradient(self):
        torch.manual_seed(1)
        m=HarmonicExcitation(sample_rate=24000,hop=240,harmonics=32)
        f0=torch.full((1,12),140.)
        energy=torch.full((1,12),.2)
        carrier=torch.sin(torch.linspace(0,700,12*240))[None]
        y,aux=m(f0,energy,carrier)
        self.assertEqual(tuple(y.shape),(1,2880))
        self.assertEqual(aux['harmonic_amplitudes'].shape[1],32)
        self.assertTrue(torch.isfinite(y).all())
        y.square().mean().backward()
        self.assertTrue(any(p.grad is not None for p in m.parameters()))

    def test_no_carrier_means_no_random_unvoiced_noise(self):
        m=HarmonicExcitation(sample_rate=24000,hop=240,harmonics=32).eval()
        f0=torch.zeros(1,8);energy=torch.ones(1,8)*.3
        a,_=m(f0,energy,None);b,_=m(f0,energy,None)
        self.assertTrue(torch.equal(a,b))
        self.assertLess(float(a.abs().max()),1e-6)
PY

cat > tests/test_argon_v2_content.py <<'PY'
import unittest,torch
from argon_v2.content import DeepContentEncoder

class V2ContentTests(unittest.TestCase):
    def test_deep_content_and_six_books(self):
        torch.manual_seed(2)
        m=DeepContentEncoder(sample_rate=24000,hop=240,dim=256,books=6,book_size=1024)
        x=torch.randn(1,7200)*.02
        z,idx,vq,stats=m(x)
        self.assertEqual(z.shape[1],256)
        self.assertEqual(idx.shape[1],6)
        self.assertGreater(z.shape[-1],20)
        self.assertTrue(torch.isfinite(vq))
        self.assertIn('usage',stats)
PY

cat > tests/test_argon_v2_tract.py <<'PY'
import unittest,torch
from argon_v2.tract import DeepVocalTract
from argon_v2.postfilter import WaveformRefiner

class V2TractTests(unittest.TestCase):
    def test_two_stage_dynamic_tract_and_refiner(self):
        torch.manual_seed(3)
        tract=DeepVocalTract(dim=256,speaker_dim=192,hop=240,long_taps=129,short_taps=31)
        ref=WaveformRefiner(content_dim=256,speaker_dim=192,channels=64,hop=240)
        codes=torch.randn(1,256,16)
        spk=torch.randn(1,192)
        exc=torch.randn(1,3840)*.02
        carrier=torch.randn_like(exc)*.01
        coarse,aux=tract(exc,codes,spk)
        y=ref(coarse,exc,carrier,codes,spk)
        self.assertEqual(y.shape,exc.shape)
        self.assertEqual(aux['long_ir'].shape[1],129)
        self.assertEqual(aux['short_ir'].shape[1],31)
        self.assertTrue(torch.isfinite(y).all())
PY

cat > tests/test_argon_v2_losses.py <<'PY'
import unittest,torch
from argon_v2.losses import naturalness_loss
from argon_v2.critic import MultiPeriodCritic,critic_hinge_loss,generator_hinge_loss

class V2LossTests(unittest.TestCase):
    def test_multiresolution_loss_prefers_identical(self):
        torch.manual_seed(4)
        x=torch.randn(1,12000)*.03
        a=naturalness_loss(x,x,24000)['total']
        b=naturalness_loss(torch.randn_like(x)*.03,x,24000)['total']
        self.assertLess(float(a),float(b))

    def test_critic_and_hinge_losses_are_finite(self):
        c=MultiPeriodCritic(periods=(2,3,5))
        real=torch.randn(1,6000)*.03
        fake=torch.randn_like(real)*.03
        rr,rf=c(real);fr,ff=c(fake)
        dl=critic_hinge_loss(rr,fr)
        gl=generator_hinge_loss(fr)
        self.assertTrue(torch.isfinite(dl))
        self.assertTrue(torch.isfinite(gl))
        self.assertEqual(len(rr),3)
PY

cat > tests/test_argon_v2_engine.py <<'PY'
import tempfile,unittest,torch
from pathlib import Path
from argon_v2.engine import ArgonNeuralV2

class V2EngineTests(unittest.TestCase):
    def test_forward_checkpoint_and_parameter_count(self):
        torch.manual_seed(5)
        m=ArgonNeuralV2()
        x=torch.randn(1,7200)*.02
        y,aux=m(x)
        self.assertEqual(y.shape,x.shape)
        self.assertEqual(aux['indices'].shape[1],6)
        self.assertGreater(sum(p.numel() for p in m.parameters()),3_000_000)
        self.assertTrue(torch.isfinite(y).all())
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'v2.pt'
            m.save(p,{'epoch':1})
            n,meta=ArgonNeuralV2.load(p,'cpu')
            self.assertEqual(meta['epoch'],1)
            self.assertEqual(n.sample_rate,24000)
PY

echo '=== EXPECTED RED PHASE ==='
set +e
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest  tests.test_argon_v2_source tests.test_argon_v2_content tests.test_argon_v2_tract  tests.test_argon_v2_losses tests.test_argon_v2_engine -v
RC=$?
set -e
echo RED_PHASE_EXIT=$RC
test "$RC" -ne 0
echo 'RED PHASE CONFIRMED'
