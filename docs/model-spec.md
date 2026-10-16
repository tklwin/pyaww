# Pyaww model spec (Phase 0)

Source of truth for the ASR asset used by Pyaww. Everything here is
**measured or extracted from the actual files**, not inferred. Last updated:
2026-10-16 (encoder-only deployment asset, 30 s fixed input).

## 1. Assets and provenance

| Path | What it is | Size |
| --- | --- | --- |
| `myanmar_asr/model.safetensors` | Owner's PyTorch checkpoint, FP32, 23,753,868 params, Apache-2.0 | 91 MB |
| `myanmar_asr/model.py` | Standalone reference architecture (ConformerASR) | — |
| `myanmar_asr/transcribe.py` | Owner's Python reference inference script (I-6) | — |
| `myanmar_asr/vocab.json` | Token→ID map, 2566 entries (I-5) | — |
| `myanmar_asr/cmvn.json` | Global mel normalization mean/std, 80 values each | — |
| `myanmar_asr/preprocessor_config.json` | Audio front-end spec (I-3) | — |
| `myanmar_asr/example.mp3` | Reference sample clip | — |
| `Models/BurmeseASR-Encoder-30s.mlpackage` | **The Core ML asset the Swift app loads.** Encoder-only, fixed 30 s mel input, `w16` precision (fp16 weights for linear/conv ops, fp32 activations). Converted 2026-10-16 with coremltools 9.0 (`torch==2.14.1`, TorchScript dialect, Core ML spec v7) by `scripts/reconvert_coreml.py` (default `--precision w16`). | 39.4 MB |
| `Models/BurmeseASR.mlpackage` (+ `.mlmodelc`) | Original end-to-end 2 s asset (raw audio → logits). Kept read-only as provenance/reference; the app does not use it. | 38 MB |
| `Models/cmvn.json` | 80 means + 80 stds, equal to the reference values (verified by `scripts/export_fe_constants.py`) | — |
| `Models/vocab.json` | Identical to `myanmar_asr/vocab.json` (verified) | — |
| `Models/mel_filters.json` | (80, 201) mel filterbank, **regenerated 2026-10-16 to match the reference** (torchaudio `mel_scale='htk', norm=None`). The pre-existing file was Slaney-normalized and did not match the reference pipeline; preserved as `mel_filters.slaney.json`. Flagged to the owner. | 87 KB |
| `Models/hann_window.json` | (400,) periodic Hann window (`torch.hann_window(400)`) as used by the reference STFT | 8 KB |
| `Models/mel_filters.slaney.json` | Legacy copy of the previous (non-matching) filterbank, kept for provenance | 87 KB |

The owner's checkpoint is untouched (guardrail #1): the conversion reads it
plus the owner's own `model.py` / `transcribe.py`.

## 2. Why encoder-only

The first attempt — one end-to-end Core ML model with raw audio input
(`Models/BurmeseASR-30s.mlpackage`, withdrawn) — worked in fp32, but its
fp16 conversion is **numerically unstable beyond ~10 s**: the fp16
STFT/mel front-end chain overflows to `inf` (244,938 `inf` values measured
in the graph; decoded text collapsed to empty on 15/30 s probes). The fp32
end-to-end variant is 95 MB and breaks the 60 MB bundle target (SPEC §5.2).
The front-end has no learned weights, so it moved into Swift
(`FeatureExtractor`, fp32, driven by the I-8 constants) and Core ML hosts
the encoder only. This restores the SPEC §4 pipeline shape
(AudioResampler → FeatureExtractor → ModelRunner).

## 3. Core ML model I/O (encoder-only, empirically verified)

### Inputs (all FLOAT32)

| Name | Shape | Meaning |
| --- | --- | --- |
| `mel` | `[1, 3001, 80]` | CMVN'd log-mel for a 30 s buffer. `T_real = floor(n/160)+1` real frames for `n` input samples at 16 kHz; **rows `T_real..3000` must be exactly ZERO** (the reference conv2d zero-pads there; see the mask contract below). |
| `frame_bias` | `[1, 751]` | `0.0` for CTC rows `< R`, `-10000.0` for rows `>= R`. `R = max(1, ((T_real+1)//2 + 1)//2)` (the owner's `calc_subsampled_lens`). Masks attention keys past the real length and zeroes the conformer-conv GLU output there (`keep = exp(frame_bias)`). |
| `conv1_bias` | `[1, 1501]` | `0.0` for frontend conv1 rows `< l1`, `-10000.0` for `>= l1` with `l1 = (T_real+1)//2`. Zeroes the conv1 row(s) the reference computation does not have (see below). |

### Output

| Field | Value |
| --- | --- |
| Name | function output `[0]` (currently `var_2170`; always read it from the model description, never hardcode) |
| Dtype | FLOAT32 returned by the runtime (weights/graph are fp16/fp32 mixed per `w16`) |
| Shape | `[1, 751, 2566]` |
| Meaning | `[batch, CTC frame, vocab]` unnormalized logits. **Decode only rows `[0, R)`** — `R` is derived from the real audio length, never from 751. |

### Mask contract

The owner's reference computes over exactly the real audio length. With a
fixed 30 s buffer, three zero-sources in the reference are reproduced inside
the converted model so that the valid rows are **decoupled from pad content**:

1. attention keys at CTC rows `>= R` are masked (`frame_bias` additive bias);
2. frontend conv1 rows `>= l1` are zeroed (`conv1_bias`) — the reference's
   conv2d zero-pads the missing conv1 row(s); with even `T_real` the first
   extra conv1 row would otherwise inherit real mel data (this single row was
   the cause of the last-token drops found while debugging);
3. `ConformerConvModule` GLU output at CTC rows `>= R` is zeroed
   (`keep = exp(frame_bias)`), reproducing the reference's zero padding of the
   31-tap depthwise conv at the sequence end.

Verified in fp32 against the unpadded reference: `max|diff| <= 4.6e-05`
(fp32 noise) across 12 probe clips including the even-length edge cases
(`scripts/reconvert_coreml.py`, `sanity2` block). Without the masks, short
clips lose trailing tokens (the decoder samples a diluted attention context).

## 4. Front-end spec (I-3) and I-8 constants

The reference front-end (`transcribe.py` + `preprocessor_config.json`):

| Parameter | Value | Source |
| --- | --- | --- |
| Sample rate | 16 000 | config |
| Channels | mono (mean downmix) | `transcribe.py` |
| Feature | log-mel, 80 bins | config |
| n_fft / win_length | 400 / 400 | config |
| hop_length | 160 (10 ms) | config |
| Center | true, pad_mode reflect (±200 samples) | torchaudio default |
| Window | Hann, periodic (400) | torchaudio default |
| f_min / f_max | 0 / 8000 (sr/2 when null) | config + torchaudio default |
| Power | 2.0 (power spectrum, onesided, 201 bins) | config |
| mel_scale / norm | htk / None | torchaudio defaults |
| Log | `log(clamp(mel, min=1e-5))` | `transcribe.py` |
| Normalization | CMVN `(mel - mean) / (std + 1e-9)`, global constants | `cmvn.json` |
| Pre-emphasis / dither | none | absent from reference |

Exported constants (I-8) by `scripts/export_fe_constants.py`:
`Models/mel_filters.json` (80×201), `Models/hann_window.json` (400), and the
verified `Models/cmvn.json` / `Models/vocab.json`. SPEC I-8 suggested raw
`.bin`/`.npy`; JSON was chosen to match the owner's existing constant-file
convention (negligible size, trivial parse) — flagged in the Phase 0 report.

Swift `FeatureExtractor` must reproduce:
- frame count `T = floor(n/160) + 1` (center=True), reflect-pad 200 samples
  on both sides, then Hann-windowed DFT (400 points, no zero-padding);
- power spectrum `|rfft|^2`, bins 0..200 → mel = fbank(80×201) × power →
  `log(clamp(min=1e-5))` → CMVN; keep everything Float32 end-to-end;
- zero-pad feature rows to 3001 and build `frame_bias` / `conv1_bias` per §3.

If any later re-export changes the front-end, this table and the exported
constants are the contract.

## 5. Length constraints (I-9) — resolved

- **Fixed 30 s model input** (owner-approved 2026-10-16): `mel` is always
  3001 frames; the app records at most 30 s (FR-6) and never feeds
  out-of-range input.
- The reference returns `""` below 0.5 s (8,000 samples); the app also
  applies FR-5 (minimum duration + silence guard) before calling the model.
- Length math: `n` samples (16 kHz mono) → `T_real = n//160 + 1` →
  `R = max(1, ((T_real+1)//2 + 1)//2)`. Decode `logits[0, :R]`.
  Examples: 1.20 s → T=121, R=31; 3.13 s → T=314, R=79; 30 s → T=3001, R=751.

## 6. Numerics and parity evidence (final, Phase 0)

### fp32 decoupling (wrapper sanity, before conversion)

`sanity1`: full-length wrapper vs the owner's forward, `max|diff| 1.5e-05`.
`sanity2`: padded + masks vs the unpadded reference on 12 probe clips,
`max|diff| <= 4.6e-05`. The conversion recipe is equivalent to the
reference in exact arithmetic on valid rows.

### Conversion precision vs the fp32 Python reference

101 files = `example.mp3` + 100 golden WAVs. "Exact text" = decoded string
identical to the reference; "flips" = clips with >= 1 argmax-head flip:

| Variant | What | Size | Exact text | Clips w/ flips | max\|diff\| (valid rows) |
| --- | --- | --- | --- | --- | --- |
| `fp16` | fp16 everywhere | 37.0 MB | 93/101 | 21 | up to 15.3 |
| `attn32` | fp16 + attention matmul/softmax fp32 | 39.1 MB | 100/101 | 4 | up to ~0.7 |
| `attn32ln` | attn32 + layer_norm fp32 | ~39 MB | 100/101 | 1 | <= ~0.27 |
| `w16` (**shipped**) | fp16 only for linear/conv weights; all activation math fp32 | 39.4 MB | 100/101 | 1 | <= ~0.07 typical |
| `fp32` | everything fp32 | 77.8 MB | 101/101 | 0 | <= 4e-04 |

Every mismatching frame across all variants is a knife-edge near-tie: at the
flipped frames the fp32 reference's top-1/top-2 margin is 0.012–0.118
(measured per frame), so any sub-fp32 arithmetic flips them. The single
`w16` mismatch is `g2063.wav` (10.4 s): frame 71/262, reference margin
0.0122, w16 local diff 0.0119 → one token differs (`နမ်း` → `ဒန်`) out of 28.

`w16` is the default because it (a) meets the 60 MB bundle target at
39.4 MB, (b) has the smallest measured drift of the size-compliant variants,
(c) reaches 100/101 exact text. **The g2063 tolerance needs owner sign-off**
(SPEC §5.3 allows a documented, owner-approved tolerance). The exact
alternative is `scripts/reconvert_coreml.py --precision fp32` (77.8 MB,
near-exact, but violates the bundle target). Per-clip results for the
shipped asset: `Tests/Fixtures/parity_report.tsv`.

### Silence / FR-5

All-zero and near-silence inputs decode to `""` at every tested duration
(0.5/1/5/30 s → R = 13/26/126/751, 100 % blank frames). Safe: no paste on
silent clips.

### Reference-vs-ground-truth quality (tracked, SPEC §5.3)

CER of the Python reference outputs vs the HF dataset transcripts (all
whitespace stripped, no Unicode normalization; `scripts/cer.py`):
**corpus 12.74 %** (1,388 edits / 10,896 ref chars); mean clip 10.7 %,
median 5.9 %, p90 27.3 %, worst 103.1 % (`g3097`, a long noisy clip;
`g0003` is a 23-char English-garble transcript). This is the model + dataset
baseline; Gate 1 requires Swift <= Python + 0.1 pp.
Report: `Tests/Fixtures/cer_report.tsv`.

## 7. Performance snapshot

### Shipped encoder-only asset (Python coremltools runtime, default `.all`)

Full golden-set run (101 files, 0.7–25.5 s audio): `predict()` median
**35.5 ms**, p90 **48.4 ms**, max 338 ms (a first-call/compile artifact on
one clip). Python runtime overhead included. Swift numbers come from
`pyaww-cli` in Phase 1/3 (SPEC §6.1 demands measurement with the real
runner).

### Original 2 s end-to-end asset (compute-unit comparison, indicative)

2 s real speech, 10 warm predicts after an explicit warm-up:

| computeUnits | build/load ms | median ms | p90 ms |
| --- | --- | --- | --- |
| `.all` | 1463 | 5.8 | 8.6 |
| `.cpuAndNeuralEngine` | 4985 | 3.6 | 3.8 |
| `.cpuOnly` | 477 | 4.3 | 5.2 |
| `.cpuAndGPU` | 746 | 38.5 | 42.5 |

The GPU was the worst compute unit on the small asset; Phase 3 re-benchmarks
all compute units for the 30 s encoder asset. `.cpuAndNeuralEngine` also had
the slowest first load — the app must warm up before the first dictation
(SPEC §6.1).

## 8. Toolchain facts

- This Mac has **Command Line Tools only**; `xcrun --find coremlc` fails.
  → Swift code must handle the **first-launch model compile fallback**
  (`MLModel.compileModel(at:)`, cached in Application Support) per spec §3.
  Install full Xcode only if blocked.
- Swift 6.x (CLT) supports Package-only builds.
- Dev-time analysis runs in `.venv/` (uv-managed CPython 3.11, torch 2.14.1
  + torchaudio 2.11.0 + coremltools 9.0). The venv is for the parity
  harness/fixtures only — the **Swift app itself has zero third-party
  dependencies** (SPEC §3).
- torchaudio 2.11's file loader needs `torchcodec`, which is not installed;
  the parity tooling loads audio with `soundfile` instead (deterministic,
  same 16 kHz mono Float32 result — see decisions.md).
- `coremltools.convert(compute_precision=ct.transform.FP16ComputePrecision(
  op_selector=...))` is what produces `w16`: fp16 for `linear`/`conv` weights,
  fp32 everywhere else (`ct.transform.FP16ComputePrecision` does not provide
  an op-exclusion list at convert time; the selector is the supported path).

## 9. Attention decoder in the checkpoint

`model.safetensors` also contains an unused 2-layer attention decoder (part
of the archived training setup). The Core ML conversion contains none of
those ops and the owner's inference script never uses them. v1 behaviour is
unaffected; size context: 91 MB fp32 checkpoint → 39.4 MB deployment model.
