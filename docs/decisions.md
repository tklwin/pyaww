# Pyaww decisions log

One line per decision: what, why, when. Newest at the bottom.
Decisions flagged **[OWNER]** are awaiting the owner's answer before they
become final.

## Phase 0 (2026-10-16)

- **Python 3.11 venv via `uv` at `.venv/` for analysis/parity tooling.**
  The system Python is 3.14 (no torch wheels for it yet); the owner's
  reference needs torch/torchaudio/coremltools. This venv is dev-time only;
  the Swift app keeps zero third-party dependencies. The reference project's
  own `requirements.txt` is the source of the pinned deps.
- **Parity tooling loads audio with `soundfile`.** torchaudio 2.11 routes
  `load()` through `torchcodec`, which isn't installed; `soundfile`
  (libsndfile) reads WAV/FLAC/MP3 deterministically and is already a
  dependency of the owner's reference project. Same 16 kHz mono Float32
  result, documented instead of silently different loaders.
- **Core ML probe feeds Float32 `[1, 32000]` into input `audio`.**
  The mlpackage's `spec.description` metadata claims the input is FLOAT16,
  but the mlProgram function input is FLOAT32 and the runtime accepted a
  Float32 array. Documented in model-spec.md §2 rather than guessed around.
- **No Swift-side feature extraction for the current asset.** The converted
  graph bakes the STFT/Mel/CMVN front-end inside itself, so Pyaww's Swift
  pipeline only needs resample→pad→ModelRunner. `FeatureExtractor.swift`
  stays in the plan only if the owner re-exports the model with a
  mel-input interface. (See model-spec.md §3.)
- **Compute-unit benchmark snapshot recorded** (model-spec.md §7):
  `.cpuAndNeuralEngine` 3.6 ms median, `.all` 5.8 ms, `.cpuOnly` 4.3 ms,
  `.cpuAndGPU` 38.5 ms for a 2 s real-speech clip. Final decision belongs to
  Phase 3 with the real Swift runner; GPU is already ruled out as slowest.
- **Naming of probe scripts:** `scripts/inspect_coreml.py`,
  `scripts/dump_mlprogram.py`, `scripts/parity_check.py`,
  `scripts/export_fixtures.py`. They are AI/agent analysis tools, not app
  code, and are excluded from any app bundle.
- **First-launch model compile fallback required** — confirmed `xcrun
  coremlc` is unavailable with Command Line Tools only (spec's
  `MLModel.compileModel` + Application Support cache plan stands).
- **[OWNER] Signing identity for stable local builds** is not yet decided
  (free Apple Development certificate vs self-signed). Record here once
  chosen, before Phase 4 — changing it resets TCC permissions.
