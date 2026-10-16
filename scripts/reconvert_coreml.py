# Re-export the owner's ASR as a Core ML ENCODER-ONLY package with a fixed
# 30 s mel input (owner-approved I-9 decision, 2026-10-16).
#
# Architecture (see docs/model-spec.md, docs/decisions.md):
#   Swift FeatureExtractor (fp32, I-8 constants) : audio -> CMVN'd log-mel
#   this package                                 : mel + masks -> CTC logits
#
# Why encoder-only: the full e2e fp16 (raw audio in) conversion is numerically
# unstable beyond ~10 s on this toolchain (fp16 STFT/mel path overflows to inf).
# The encoder alone is numerically sound at 3001 mel frames.
#
# Precision (default --precision w16): fp16 for weight-carrying ops only
# (linear/conv); all activation math (attention matmuls, softmax, norms,
# residuals) stays fp32. Measured against the fp32 reference on the 101-file
# fixture set: fp16-everywhere 93/101 exact text (21 clips with argmax flips),
# attn32 100/101 (4 clips), attn32ln 100/101 (1 clip), w16 100/101 (1 clip,
# max|diff| <= 0.07 typical), fp32 101/101 (max|diff| <= 4e-4, 77.8 MB).
# w16 = 39.4 MB, meets the 60 MB bundle target. The single w16 mismatch
# (g2063) is a knife-edge frame: fp32 margin 0.0122 vs w16 diff 0.0119.
# The shipped precision is w16 pending owner sign-off of that tolerance;
# fp32 is available via --precision fp32 (regenerate on demand).
#
# Inputs (all fp32):
#   'mel'         (1, 3001, 80)  CMVN'd log-mel, zero-padded after T_real
#   'frame_bias'  (1, 751)       0 for CTC rows < R, PAD_BIAS after
#   'conv1_bias'  (1, 1501)      0 for frontend conv1 rows < l1, PAD_BIAS after
# with R  = calc_subsampled_lens(T_real) = max(1, ((T_real+1)//2+1)//2)
#      l1 = (T_real+1)//2
#
# Why the masks: the fixed 3001-frame input contains pad rows for shorter
# recordings. To make valid rows EXACTLY equal to the owner's variable-length
# reference computation (verified in fp32 below), three zero-sources in the
# reference must be reproduced:
#   1. attention keys at CTC rows >= R         -> masked (frame_bias)
#   2. frontend conv1 rows >= l1               -> zeroed (conv1_bias): the
#      owner's conv2d zero-pads the missing conv1 row(s); with an even T_real
#      the first extra conv1 row would otherwise inherit real mel data.
#   3. ConformerConvModule GLU output at rows
#      >= R                                   -> zeroed (keep = exp(frame_bias)),
#      reproducing the reference's zero padding of the depthwise conv.
# The mel pad rows themselves MUST be zeros (the last valid CTC row's frontend
# receptive field reaches past T_real; the owner's conv2d zero-pads there).
#
# Conversion recipe mirrors the owner's proven old_export_coreml.py
# (FixedConvSubsampling flatten, precomputed RoPE buffers, macOS13 target).
#
# Output: Models/BurmeseASR-Encoder-30s.mlpackage  (spec v7, ~39 MB)
#   output 'logits' (1, 751, 2566); Swift decodes rows [0, R).
# Usage:  .venv/bin/python scripts/reconvert_coreml.py
#           [--precision {w16,fp16,attn32,attn32ln,fp32}] [--out PATH]
import argparse
import copy
import json
import sys
import warnings
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "myanmar_asr"))
from transcribe import BurmeseASR  # noqa: E402  (owner's reference code)
from model import calc_subsampled_lens  # noqa: E402

MEL_FRAMES = 3001                      # floor(480000 / 160) + 1
CONV1_FRAMES = 1501                    # (MEL_FRAMES + 1) // 2
ENC_FRAMES = int(calc_subsampled_lens(torch.tensor([MEL_FRAMES]))[0])  # 751
PAD_BIAS = -10000.0                    # additive bias; keep = exp(bias)
OUT_PATH = REPO / "Models/BurmeseASR-Encoder-30s.mlpackage"


class CoreMLRoPE(torch.nn.Module):
    """Verbatim from the owner's old_export_coreml.py (RoPE precomputed)."""

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


class MaskedConvSubsampling(torch.nn.Module):
    """ConvSubsampling with conv1 output rows >= l1 zeroed (conv1_bias)."""

    def __init__(self, orig):
        super().__init__()
        self.conv1 = orig.conv[0]
        self.relu1 = orig.conv[1]
        self.conv2 = orig.conv[2]
        self.relu2 = orig.conv[3]
        self.proj = orig.proj

    def forward(self, x, keep1):          # x (B, T, 80); keep1 (B, 1, l1, 1)
        x = x.unsqueeze(1)
        x = self.relu1(self.conv1(x))
        x = x * keep1
        x = self.relu2(self.conv2(x))
        x = x.transpose(1, 2).flatten(2)
        return self.proj(x)


class ExplicitAttn(torch.nn.Module):
    """The owner's AttentionWithRoPE math (q/k/v split, RoPE, scaled dot
    product, out proj) with an additive frame_bias instead of a bool mask.
    fp32-equivalent to the owner's forward: max|diff| ~1e-5 (checked)."""

    def __init__(self, orig):
        super().__init__()
        self.qkv = orig.qkv
        self.out = orig.out
        self.rope = orig.rope
        self.n_heads = orig.n_heads
        self.head_dim = orig.head_dim

    def forward(self, x, frame_bias):
        B, T, D = x.shape
        qkv = self.qkv(x).reshape(B, T, 3, self.n_heads, self.head_dim)
        q, k, v = qkv.unbind(dim=2)
        q = q.transpose(1, 2)
        k = k.transpose(1, 2)
        v = v.transpose(1, 2)
        q, k = self.rope(q, k)
        scores = torch.matmul(q, k.transpose(-1, -2)) * (self.head_dim ** -0.5)
        scores = scores + frame_bias[:, None, None, :]
        attn = torch.softmax(scores, dim=-1)
        out = torch.matmul(attn, v)
        out = out.transpose(1, 2).reshape(B, T, D)
        return self.out(out)


class ConvWrap(torch.nn.Module):
    """ConformerConvModule with the GLU output zeroed at masked rows
    (keep = exp(frame_bias)), exactly matching the reference's zero padding
    of the depthwise conv at the sequence end."""

    def __init__(self, orig):
        super().__init__()
        self.pw1 = orig.pw1
        self.dw = orig.dw
        self.norm = orig.norm
        self.pw2 = orig.pw2

    def forward(self, x, keep):          # x (B, T, D); keep (B, 1, T)
        x = x.transpose(1, 2)
        x = self.pw1(x)
        x = F.glu(x, dim=1)
        x = x * keep
        x = self.dw(x)
        x = x.transpose(1, 2)
        x = self.norm(x)
        x = x.transpose(1, 2)
        x = F.silu(x)
        x = self.pw2(x)
        return x.transpose(1, 2)


class BlockWrap(torch.nn.Module):
    """The owner's ConformerBlock.forward with ExplicitAttn/ConvWrap."""

    def __init__(self, orig):
        super().__init__()
        self.ff1 = orig.ff1
        self.ff2 = orig.ff2
        self.norm_ff1 = orig.norm_ff1
        self.norm_ff2 = orig.norm_ff2
        self.norm_attn = orig.norm_attn
        self.norm_conv = orig.norm_conv
        self.norm_out = orig.norm_out
        self.attn = ExplicitAttn(orig.attn)
        self.conv = ConvWrap(orig.conv)

    def forward(self, x, frame_bias, keep):
        x = x + 0.5 * self.ff1(self.norm_ff1(x))
        x = x + self.attn(self.norm_attn(x), frame_bias)
        x = x + self.conv(self.norm_conv(x), keep)
        x = x + 0.5 * self.ff2(self.norm_ff2(x))
        return self.norm_out(x)


class MaskedEncoder(torch.nn.Module):
    """mel + masks -> CTC logits (fixed 3001-frame input)."""

    def __init__(self, conformer):
        super().__init__()
        self.frontend = MaskedConvSubsampling(conformer.frontend)
        self.blocks = torch.nn.ModuleList(
            [BlockWrap(b) for b in conformer.blocks])
        self.enc_norm = conformer.enc_norm
        self.ctc_fc = conformer.ctc_fc
        for blk in self.blocks:
            blk.attn.rope = CoreMLRoPE(blk.attn.head_dim, max_len=2048)

    def forward(self, mel, frame_bias, conv1_bias):
        keep1 = torch.exp(conv1_bias).view(1, 1, -1, 1)   # (B, 1, l1, 1)
        keep = torch.exp(frame_bias).unsqueeze(1)         # (B, 1, T') 1/0
        x = self.frontend(mel, keep1)
        for blk in self.blocks:
            x = blk(x, frame_bias, keep)
        return self.ctc_fc(self.enc_norm(x))


def features_of(asr_api, wav: np.ndarray) -> torch.Tensor:
    cmvn_mean = asr_api.cmvn_mean.view(1, -1, 1)
    cmvn_std = asr_api.cmvn_std.view(1, -1, 1)
    with torch.inference_mode():
        f = torch.log(asr_api.mel(torch.from_numpy(wav).unsqueeze(0)).clamp(min=1e-5))
        f = (f - cmvn_mean) / (cmvn_std + 1e-9)
        return f.transpose(1, 2)            # (1, T, 80)


def make_inputs(feats: torch.Tensor):
    """Zero-pad features to 3001 frames; build both bias inputs for T_real."""
    T_real = feats.shape[1]
    R = int(calc_subsampled_lens(torch.tensor([T_real]))[0])
    l1 = (T_real + 1) // 2
    padded = torch.zeros(1, MEL_FRAMES, 80)
    padded[:, :T_real] = feats
    frame_bias = torch.zeros(1, ENC_FRAMES)
    frame_bias[:, R:] = PAD_BIAS
    conv1_bias = torch.zeros(1, CONV1_FRAMES)
    conv1_bias[:, l1:] = PAD_BIAS
    return padded, frame_bias, conv1_bias, R


def decode(logits: torch.Tensor, id2tok, vocab_size: int) -> str:
    ids, out, prev = logits.argmax(-1).tolist(), [], -1
    for i in ids:
        if i != prev and i != 0:
            out.append(i)
        prev = i
    return " ".join(id2tok[i] for i in out if 0 <= i < vocab_size and id2tok[i])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--precision", choices=["w16", "fp16", "fp32", "attn32", "attn32ln"],
                    default="w16",
                    help="w16 (default, shipped): fp16 only for linear/conv "
                         "weights, all activation math fp32; fp16 = fp16 "
                         "everywhere (older, rejected: 93/101); fp32 = exact "
                         "but ~78 MB; attn32/attn32ln = 100/101 variants")
    ap.add_argument("--out", default=str(OUT_PATH))
    args = ap.parse_args()
    out_path = Path(args.out)

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        import coremltools as ct
        import soundfile as sf

        asr_api = BurmeseASR(model_dir=str(REPO / "myanmar_asr"), device="cpu")
        asr_ref = asr_api.model.eval()

        id2tok = {v: k for k, v in json.loads(
            (REPO / "myanmar_asr/vocab.json").read_text(encoding="utf-8")
        ).items()}
        V = len(id2tok)

        model_export = MaskedEncoder(copy.deepcopy(asr_ref)).eval()

        # ---- fp32 sanity 1: unmasked path == owner forward ----
        torch.manual_seed(0)
        dummy = torch.tanh(torch.randn(1, MEL_FRAMES, 80)) * 2.0
        with torch.inference_mode():
            out = model_export(dummy, torch.zeros(1, ENC_FRAMES),
                               torch.zeros(1, CONV1_FRAMES))
            logits_ref, enc_lens = asr_ref(dummy)
        d1 = (out - logits_ref).abs().max().item()
        assert int(enc_lens[0]) == ENC_FRAMES, f"enc {int(enc_lens[0])}"
        assert d1 < 1e-4, f"wrapper deviates from owner's forward: {d1}"
        print(f"sanity1: full-length wrapper vs owner forward max|diff| {d1:.2e}")

        # ---- fp32 sanity 2: padded + masks == unpadded reference ----
        # probe the exact parity samples from the manifest (2 per bucket)
        probe_files = [REPO / "myanmar_asr/example.mp3"]
        seen_buckets = {}
        for line in (REPO / "Tests/Fixtures/manifest.tsv").read_text().splitlines()[1:]:
            parts = line.split("\t")
            bucket = int(parts[1])
            if seen_buckets.get(bucket, 0) < 2:
                seen_buckets[bucket] = seen_buckets.get(bucket, 0) + 1
                probe_files.append(REPO / f"Tests/Fixtures/audio/{parts[0]}.wav")

        def read_wav(path):
            data, sr = sf.read(str(path), dtype="float32", always_2d=True)
            wav = data.mean(axis=1) if data.shape[1] > 1 else data[:, 0]
            return np.asarray(wav, dtype=np.float32)

        for path in probe_files:
            feats = features_of(asr_api, read_wav(path))
            padded, fb, cb, R = make_inputs(feats)
            with torch.inference_mode():
                logits_nat, _ = asr_ref(feats)
                logits_pad = model_export(padded, fb, cb)[:, :R]
            d2 = (logits_pad - logits_nat).abs().max().item()
            flag = "OK  " if d2 < 1e-4 else "BAD "
            print(f"sanity2: {flag} {path.name[:20]:22} T={feats.shape[1]:4}"
                  f" R={R:3} l1={(feats.shape[1]+1)//2:4} max|diff| {d2:.2e}")
            assert d2 < 1e-4, f"padding not decoupled for {path.name}: {d2}"

        # ---- convert ----
        trace_mel = padded  # last probe's padded input (realistic values)
        with torch.inference_mode():
            traced = torch.jit.trace(model_export, (trace_mel, fb, cb))
        if out_path.exists():
            print(f"deleting existing {out_path}")
            import shutil
            shutil.rmtree(out_path)
        converter_kwargs = dict(
            inputs=[ct.TensorType(name="mel", shape=(1, MEL_FRAMES, 80),
                                  dtype=np.float32),
                    ct.TensorType(name="frame_bias", shape=(1, ENC_FRAMES),
                                  dtype=np.float32),
                    ct.TensorType(name="conv1_bias", shape=(1, CONV1_FRAMES),
                                  dtype=np.float32)],
            minimum_deployment_target=ct.target.macOS13,
        )
        if args.precision == "fp16":
            mlmodel = ct.convert(traced,
                                 compute_precision=ct.precision.FLOAT16,
                                 **converter_kwargs)
        elif args.precision == "fp32":
            mlmodel = ct.convert(traced,
                                 compute_precision=ct.precision.FLOAT32,
                                 **converter_kwargs)
        else:  # attention math (and optionally norms) kept in fp32
            keep_fp32 = {"matmul", "softmax"}
            if args.precision == "attn32ln":
                keep_fp32 |= {"layer_norm"}
            elif args.precision == "w16":
                # fp16 ONLY for weight-carrying ops; all activations fp32
                keep_fp32 = None  # marker: selector defined below
            if keep_fp32 is None:
                fp16_ops = {"linear", "conv"}
                selector = lambda op: op.op_type in fp16_ops       # noqa: E731
            else:
                selector = lambda op: op.op_type not in keep_fp32  # noqa: E731
            mlmodel = ct.convert(
                traced,
                compute_precision=ct.transform.FP16ComputePrecision(
                    op_selector=selector),
                **converter_kwargs)
        if args.precision != "fp16":
            from collections import Counter
            blk = list(mlmodel.get_spec().mlProgram.functions[
                "main"].block_specializations.values())[0]
            print("op types:", Counter(o.type for o in blk.operations)
                  .most_common(10))
        mlmodel.user_defined_metadata["pyaww.precision"] = args.precision
        mlmodel.user_defined_metadata["pyaww.contract"] = (
            "mel(1,3001,80)+frame_bias(1,751)+conv1_bias(1,1501) fp32; "
            "decode rows [0,R), R=((T_real+1)//2+1)//2, l1=(T_real+1)//2; "
            "scripts/reconvert_coreml.py")
        mlmodel.save(str(out_path))
        size_mb = sum(f.stat().st_size for f in out_path.rglob("*")
                      if f.is_file()) / 1e6
        spec = mlmodel.get_spec()
        print(f"saved: {out_path} ({size_mb:.1f} MB) | precision {args.precision}"
              f" | spec v {spec.specificationVersion}"
              f" | outputs: {[o.name for o in spec.description.output]}"
              f" | metadata: {dict(mlmodel.user_defined_metadata)}")

        # ---- probe: converted vs owner's Python reference ----
        coreml = ct.models.MLModel(str(out_path))
        out_name = spec.description.output[0].name

        n_match = 0
        for path in probe_files:
            feats = features_of(asr_api, read_wav(path))
            with torch.inference_mode():
                logits_ref, _ = asr_ref(feats)
            text_ref = decode(logits_ref[0], id2tok, V)
            padded, fb, cb, R = make_inputs(feats)
            arr = np.asarray(coreml.predict(
                {"mel": padded.numpy(),
                 "frame_bias": fb.numpy(),
                 "conv1_bias": cb.numpy()})[out_name])
            valid = arr[0, :R].astype(np.float64)
            ref = logits_ref[0].float().numpy().astype(np.float64)
            maxd = float(np.abs(valid - ref).max())
            agree = float((valid.argmax(-1) == ref.argmax(-1)).mean())
            text_cm = decode(torch.from_numpy(arr[0, :R]), id2tok, V)
            ok = text_ref == text_cm
            n_match += ok
            dur = read_wav(path).shape[0] / 16000
            print(f"{'MATCH   ' if ok else 'MISMATCH'} {path.name[:20]:22}"
                  f" {dur:6.2f}s R={R:3} max|d| {maxd:.4f} agree {agree:.4f}")
            if not ok:
                print(f"    ref: {text_ref[:96]}\n    cml: {text_cm[:96]}")
        print(f"parity: {n_match}/{len(probe_files)} text matches")


if __name__ == "__main__":
    main()
