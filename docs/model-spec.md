# Pyaww model spec (Phase 0)

Source of truth for the ASR asset used by Pyaww. Everything here was
**measured or extracted from the actual files**, not inferred. Last updated:
Phase 0 (2026-10-16).

## 1. Assets and provenance

| Path | What it is | Size |
| --- | --- | --- |
| `myanmar_asr/model.safetensors` | Owner's PyTorch checkpoint, FP32, 23,753,868 params, Apache-2.0 | 91 MB |
| `myanmar_asr/model.py` | Standalone reference architecture (ConformerASR) | — |
| `myanmar_asr/transcribe.py` | Owner's Python reference inference script (I-6) | — |
| `myanmar_asr/vocab.json` | Token→ID map, 2566 entries (I-5) | — |
| `myanmar_asr/cmvn.json` | Global mel normalization mean/std, 80 values each | — |
| `myanmar_asr/preprocessor_config.json` | Audio front-end spec (I-3) | — |
| `Models/BurmeseASR.mlpackage` | **The Core ML asset the Swift app will load** | 38 MB (fp16 weights) |
| `Models/BurmeseASR.mlmodelc` | Pre-compiled copy of the same model | 38 MB |

The `.mlpackage` was converted from the owner's own checkpoint on
2026-10-12 with coremltools 9.0 (`torch==2.14.1`, TorchScript dialect,
Core ML spec version 7). Original checkpoint is untouched (guardrail #1).

## 2. CoreML model I/O (empirically verified)

The conversion is **end-to-end**: the mel front-end and CMVN live *inside*
the Core ML graph. Swift feeds raw 16 kHz mono audio and CTC logits come out.

### Input

| Field | Value |
| --- | --- |
| Name | `audio` |
| Kind | tensor (multiArray) |
| Dtype | FLOAT32 (function-level input; `spec.description` metadata claims FLOAT16 — the description is stale, runtime accepts Float32) |
| Shape | `[1, 32000]` — **fixed**, exactly 2.00 s at 16 kHz |
| Layout | batch × samples, mono |

MLMultiArray provided as Float32 `[1, 32000]` was accepted by the
runtime in our probe. There are no flexible ranks or range constraints.

### Output

| Field | Value |
| --- | --- |
| Name | `var_2116` (C TC logits) |
| Dtype | FLOAT16 per description; **runtime returns Float32** |
| Shape | `[1, 51, 2566]` for a full 32000-sample input |
| Meaning | `[batch, CTC_frame, vocab]` unnormalized logits |

`spec.description` also declares no `.default` value for the output shape;
frames = 51 = `calc_subsampled_lens(201)` where 201 = `floor(32000/160) + 1`
mel frames (center=True).

### Operations inside the graph (2000 ops)

cast fp16 → expand dims → pad (±200, STFT center) → conv (STFT windows) →
power spectrum → mel matmul (80 filters baked in) → clip → log → CMVN
(baked-in constants) → transpose → ConvSubsampling (2×2 convs → 256-d) →
12 × Conformer block (RoPE attention) → encoder LayerNorm → `ctc_fc`
Linear(256 → 2566).

No attention-decoder ops are present in the graph: the deployment path
is CTC-greedy only, matching the owner's reference script.

## 3. Front-end spec (I-3) as encoded in the owner's reference

The Python reference (`transcribe.py`) + `preprocessor_config.json` imply:

| Parameter | Value | Source |
| --- | --- | --- |
| Sample rate | 16 000 | config |
| Channels | mono (mean downmix) | `transcribe.py` |
| Feature | log-mel, 80 bins | config |
| n_fft / win | 400 / 400 | config |
| hop_length | 160 (10 ms) | config |
| Center | true (default), pad_mode reflect | torchaudio default |
| Window | Hann | torchaudio default |
| f_min / f_max | 0 / 8000 (sr/2 when null) | config + torchaudio default |
| Power | 2.0 | config |
| mel_scale / norm | htk / None | torchaudio defaults |
| Log | `log(clamp(mel, min=1e-5))` | `transcribe.py` |
| Normalization | global CMVN with baked-in constants: `(mel-mean)/(std+1e-9)` | `cmvn.json` |
| Pre-emphasis / dither | none | absent from reference |

The same values are baked into the Core ML graph (as fp16 constants), so the
Swift side does **not** re-implement feature extraction for the current
asset. (I-8 `.npy` exports of mel filterbank/window are therefore only
needed if the owner later re-exports the model with a mel-input interface.)

## 4. Decoder and tokenizer (I-4 / I-5)

- **Decoder:** greedy CTC — per-frame argmax over 2566 logits, collapse
  consecutive repeats, drop class 0. (Reference: `transcribe.py` lines 100-111.)
- **Vocabulary:** `vocab.json`, 2566 tokens. `0 = <blank>`, `1 = <unk>`.
  IDs 2..2565 are Burmese syllables (2,564 tokens contain Myanmar-block
  characters); **there are no ASCII digits or Latin tokens in the vocab** —
  the only pure-ASCII tokens are `<blank>` and `<unk>`.
- **Tokens→text:** space-joined syllables, e.g.
  `စစ် ကောင် စီ အ တွက် ...` (Note: Burmese spaces separate syllable tokens,
  which the post-processor may later normalize. v1 default: leave as-is.)
- Unknown IDs cannot crash: decode filters to `0 <= id < 2566` and non-empty
  tokens, matching the reference.

## 5. Length constraints (I-9) — **decision needed**

- The shipped asset accepts **exactly 32000 samples (2.00 s)**.
- Longer audio must currently be **truncated to 2 s** (verified in the
  parity probe), which silently loses everything past the 2 s mark.
- Training used batches of "180 s / 90 clips" (~2 s average) but that does
  not prove a 2 s max.
- **Open question for the owner:** keep 2 s, or re-convert (from the
  untouched checkpoint) to a longer fixed input, e.g. 10/20/30 s?
  FR-6 demands a hard cap today; 2 s dictation is very short for
  push-to-talk usage.

## 6. Numerics and parity evidence (Phase 0 probe)

Comparing the current Core ML asset against the FP32 PyTorch reference on
`myanmar_asr/example.mp3` (16 kHz mono, zero-padded to 2 s):

| Metric | Value |
| --- | --- |
| argmax (per-frame label) agreement | 100 % (51/51 frames) |
| Decoded text | **identical strings** |
| max abs logit diff | 0.0246 |
| mean abs logit diff | 0.0034 |

Implication: FP16 conversion drift is small on this clip, but argmax flips
near ties are possible; **Gate 1** must measure string parity + SER delta on
the full golden set (I-7), not extrapolate from a single clip.

Silence behaviour: an all-zero input yields argmax `<blank>` (id 0)
everywhere → decode → `""` (safe: no paste on silent clips, per FR-5).

## 7. Performance snapshot (coremltools Python runtime, Apple Silicon)

2-second real speech, 10 warm predicts after an explicit first warm-up:

| computeUnits | build/load ms | median ms | p90 ms |
| --- | --- | --- | --- |
| `.all` | 1463 | 5.8 | 8.6 |
| `.cpuAndNeuralEngine` | 4985 | 3.6 | 3.8 |
| `.cpuOnly` | 477 | 4.3 | 5.2 |
| `.cpuAndGPU` | 746 | 38.5 | 42.5 |

All configs are far under the 300 ms end-to-end target; the GPU is the
worst compute unit. Numbers to be re-measured from Swift with the real app
runner in Phase 3 (spec 6.1 demands measurement, not assumption).
Note `.cpuAndNeuralEngine` also has the slowest first-load (~5 s) — the app
must warm up before the first dictation.

## 8. Toolchain facts

- This Mac has **Command Line Tools only**; `xcrun --find coremlc` fails.
  → Swift code must handle the **first-launch model compile fallback**
  (`MLModel.compileModel(at:)`, cached in Application Support) per spec
  §3 "Build and release". Install full Xcode only if blocked.
- Swift 6.4 (CLT) is available and supports Package-only builds.
- Dev-time analysis runs in `.venv/` (uv-managed CPython 3.11, torch
  2.14.1 + torchaudio 2.11.0 + coremltools 9.0). This venv is for the
  parity harness / fixtures only — the **Swift app itself has zero
  third-party dependencies** (spec §3 Dependency rule).
- torchaudio 2.11's file loader needs `torchcodec`, which is not installed;
  the parity tooling uses `soundfile` for deterministic file reading
  instead (documented in decisions.md).

## 9. Attention decoder in the checkpoint

`model.safetensors` also contains a 2-layer attention decoder with its own
embedding and heads (part of the archived training setup). The Core ML
conversion contains **none** of those ops, and the owner's inference script
never uses them. v1 app behaviour is unaffected; simply note the size
difference (91 MB fp32 checkpoint vs 39.5 MB fp16 deployment model).
