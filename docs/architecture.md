# Pyaww architecture

Status: **initial, written at Phase 0** — it records what we know after
inspecting the real model asset. It will be kept current as phases land.
The authoritative spec is `SPEC.md` §4; this doc adds the as-built
decisions and changes that inspection revealed.

## Product shape

- **PyawwCore** — UI-free Swift package library: audio handling, model
  runner, decoder, tokenizer, post-processing, public `Transcriber` API.
  No AppKit/SwiftUI imports, fully unit-testable.
- **pyaww-cli** — thin executable: `pyaww-cli file.wav` → prints text.
  Same pipeline, CLI front-end, also the parity/benchmark harness.
- **Pyaww app** — SwiftUI `MenuBarExtra` shell: recorder, hotkey, text
  inserter, permissions, settings, state machine.

## Data flow (v1, with the current end-to-end Core ML asset)

```
mic (any format) → AudioRecorder (AVAudioEngine tap)
  → 16 kHz mono Float32 samples                       [AudioResampler]
  → ModelRunner (CoreML: audio[1,32000] → logits[1,51,2566])   ← USB of truth: specs in docs/model-spec.md
  → Decoder (greedy CTC: argmax, collapse repeats, drop blank)
  → Tokenizer (id → Burmese syllable, space-joined)
  → TextPostProcessor (v1: trim only)
  → TextInserter (pasteboard + synthetic ⌘V, clipboard restored)
```

**Important:** the deployed Core ML asset has the STFT/Mel/CMVN front-end
*inside the graph* (fp16). Unlike the generic plan in SPEC.md §4, the Swift
side does **not** implement the log-mel feature extraction for this
asset — there is no `FeatureExtractor` stage in the v1 pipeline above
(kept as a contingency only; see `decisions.md`). The spec's
`AudioResampler` → 16 kHz mono Float32 stage is still required (input
`audio` is fixed-shape 16 kHz mono), and the model's exact 2.00 s cap
shapes `Transcriber`'s validation rules (FR-5/FR-6).

## Boundaries (protocols)

- `Transcribing` — `transcribe(samples:) async throws -> String`
- `AudioRecording` — mic capture, so tests can supply synthetic audio
- `TextInserting` — paste insertion, so tests can fake insertion

The app shell must never touch Core ML directly: only `PyawwCore`.

## Concurrency model

- Menu bar UI on `@MainActor`.
- Recording/ML/decoding off the main thread (Swift concurrency, actors).
- Explicit state machine in `AppState`: `idle → recording → transcribing
  → idle`, `error` recoverable; rapid hotkey behavior defined in Phase 2.
- Esc cancels recording; app quit cancels in-flight work.

## Privacy posture

- No network code, no analytics, no transcript/audio persistence.
- `os.Logger` categories: `audio`, `model`, `hotkey`, `paste`, `state`.
- Transcripts/audio never at `info` level or above; debug-only logging
  behind `#if DEBUG`.

## Dev-time analysis tooling (not app code)

```
.venv/                     Python 3.11 (uv) — parity/fixtures tooling
scripts/inspect_coreml.py  dump mlpackage I/O spec → model-spec.md
scripts/dump_mlprogram.py  dump mlProgram ops histogram
scripts/parity_check.py    torch reference vs CoreML on example.mp3
scripts/export_fixtures.py golden-WAV → expected/*.txt + intermediates
```

Fixtures layout when golden WAVs arrive (I-7):

```
Tests/Fixtures/audio/       WAVs (16 kHz mono)
Tests/Fixtures/expected/    <stem>.txt reference outputs (Python, full audio)
Tests/Fixtures/intermediates/  per-stage tensors for 3-5 files
```

Parity compares **Swift output vs Python reference output** (Gate 1), and
SER/CER compares both to the owner's ground-truth transcripts (§5.3).
