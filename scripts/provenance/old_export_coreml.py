#!/usr/bin/env python3
"""
export_coreml.py — Export End-to-End Burmese Conformer ASR to Apple CoreML (.mlpackage)

Option 2 Architecture (End-to-End CoreML):
- Embeds Hann-windowed 400-point STFT as Conv1d frontend inside the CoreML graph
- Applies Torchaudio-identical Mel filterbank matrix multiplication (80 mels)
- Applies Log-clamp and CMVN normalization
- Utilizes precomputed RoPE buffer for rotary positional embeddings
- Exports dynamic audio length RangeDim (8000 to 480000 samples, 0.5s to 30s)
- Direct input: Raw 16kHz audio [1, N]
- Direct output: CTC syllable logits [1, T, 70]
- Eliminates all audio DSP math and extra JSON files from the Swift codebase.
"""

import sys
import copy
import math
from pathlib import Path

import torch
import numpy as np
import coremltools as ct

MODEL_DIR = "/tmp/model"
sys.path.insert(0, MODEL_DIR)
from transcribe import BurmeseASR, load_audio, BLANK_ID


class CoreMLRoPE(torch.nn.Module):
    """Precomputed RoPE buffer to avoid dynamic outer ops."""
    def __init__(self, dim, max_len=2048, base=10000.0):
        super().__init__()
        inv = 1.0 / (base ** (torch.arange(0, dim, 2).float() / dim))
        t = torch.arange(max_len, dtype=torch.float32)
        freqs = torch.outer(t, inv)
        emb = torch.cat([freqs, freqs], dim=-1)
        self.register_buffer("cos", emb.cos()[None, None, :, :])
        self.register_buffer("sin", emb.sin()[None, None, :, :])

    def _rotate_half(self, x):
        x1, x2 = x.chunk(2, dim=-1)
        return torch.cat([-x2, x1], dim=-1)

    def forward(self, q, k):
        T = q.shape[2]
        cos = self.cos[:, :, :T, :]
        sin = self.sin[:, :, :T, :]
        return (q * cos + self._rotate_half(q) * sin,
                k * cos + self._rotate_half(k) * sin)


class FixedConvSubsampling(torch.nn.Module):
    def __init__(self, orig):
        super().__init__()
        self.conv = orig.conv
        self.proj = orig.proj

    def forward(self, x):
        x = x.unsqueeze(1)
        x = self.conv(x)
        x = x.transpose(1, 2).flatten(2)
        return self.proj(x)


class EndToEndConformerASR(torch.nn.Module):
    """End-to-End model: Raw 16kHz audio -> Mel STFT + CMVN -> Conformer -> CTC logits"""
    def __init__(self, conformer, mel_fbanks, cmvn_mean, cmvn_std):
        super().__init__()
        n_fft = 400
        n_freqs = 201
        window = torch.hann_window(n_fft)
        n = torch.arange(n_fft).float()
        k = torch.arange(n_freqs).float().unsqueeze(1)
        cos_basis = torch.cos(2 * math.pi * k * n / n_fft) * window
        sin_basis = -torch.sin(2 * math.pi * k * n / n_fft) * window
        stft_weight = torch.cat([cos_basis, sin_basis], dim=0).unsqueeze(1)

        self.register_buffer("stft_weight", stft_weight)
        self.register_buffer("mel_fbanks_t", mel_fbanks.t())        # (80, 201)
        self.register_buffer("cmvn_mean", cmvn_mean.unsqueeze(-1))  # (80, 1)
        self.register_buffer("cmvn_std", cmvn_std.unsqueeze(-1))    # (80, 1)

        self.frontend = FixedConvSubsampling(conformer.frontend)
        self.blocks = conformer.blocks
        self.enc_norm = conformer.enc_norm
        self.ctc_fc = conformer.ctc_fc

    def forward(self, audio):
        # audio: (1, N)
        # Torchaudio default reflect pad: 200 samples on both sides
        x = audio.unsqueeze(1)
        x = torch.nn.functional.pad(x, (200, 200), mode="reflect")
        conv_out = torch.nn.functional.conv1d(x, self.stft_weight, stride=160)
        real = conv_out[:, :201, :]
        imag = conv_out[:, 201:, :]
        power_spec = real ** 2 + imag ** 2

        # Mel filterbank: (80, 201) x (1, 201, T) -> (1, 80, T)
        mel = torch.matmul(self.mel_fbanks_t, power_spec)
        mel = torch.log(torch.clamp(mel, min=1e-5))
        mel = (mel - self.cmvn_mean) / (self.cmvn_std + 1e-9)
        mel = mel.transpose(1, 2) # (1, T, 80)

        # Conformer Encoder
        h = self.frontend(mel)
        for blk in self.blocks:
            h = blk(h, key_pad_mask=None)
        h = self.enc_norm(h)
        logits = self.ctc_fc(h)
        return logits


def export(output_path="BurmeseASR.mlpackage"):
    print("⏳ Loading PyTorch Conformer ASR model...")
    asr = BurmeseASR(model_dir=MODEL_DIR, device="cpu")
    model = asr.model.eval()

    # Clone & inject precomputed RoPE
    model_export = copy.deepcopy(model)
    for blk in model_export.blocks:
        blk.attn.rope = CoreMLRoPE(blk.attn.head_dim, max_len=2048)

    e2e_model = EndToEndConformerASR(
        model_export,
        asr.mel.mel_scale.fb,
        asr.cmvn_mean,
        asr.cmvn_std
    ).eval()

    dummy_audio = torch.randn(1, 32000)
    print("⏳ Tracing End-to-End model with TorchScript...")
    traced = torch.jit.trace(e2e_model, dummy_audio)

    print("⏳ Converting to Apple CoreML (.mlpackage)...")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="audio", shape=[1, ct.RangeDim(8000, 480000, 32000)], dtype=float)],
        minimum_deployment_target=ct.target.macOS13,
        compute_precision=ct.precision.FLOAT16
    )

    out_file = Path(output_path)
    if out_file.exists():
        import shutil
        if out_file.is_dir():
            shutil.rmtree(out_file)
        else:
            out_file.unlink()

    mlmodel.save(str(out_file))
    print(f"✅ Saved End-to-End CoreML model to: {out_file}")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "BurmeseASR.mlpackage"
    export(out)
