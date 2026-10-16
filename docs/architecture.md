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

## Data flow (v1)

```
mic (any format) → AudioRecorder (AVAudioEngine tap)
  → 16 kHz mono Float32 samples                       [AudioResampler]
  → log-mel + CMVN, fp32, I-8 constants               [FeatureExtractor]
  → zero-pad features to 3001 + build masks (R from real length)
  → ModelRunner (CoreML encoder: mel+masks → logits[1,751,2566])
  → slice rows [0,R) → Decoder (greedy CTC)
  → Tokenizer (id → Burmese syllable, space-joined)
  → TextPostProcessor (v1: trim only)
  → TextInserter (pasteboard + synthetic ⌘V, clipboard restored)
```

The deployed Core ML asset is **encoder-only**: the STFT/Mel/CMVN front-end
has no learned weights and runs in Swift in fp32 (`FeatureExtractor`), so the
SPEC §4 pipeline shape is kept exactly. The encoder takes a fixed 30 s mel
input (`Models/BurmeseASR-Encoder-30s.mlpackage`) plus two mask inputs that
reproduce the Python reference's variable-length computation — contract and
rationale in `docs/model-spec.md` §2–§3. This replaces the earlier plan of
baking the front-end into the graph: the fp16 end-to-end conversion was
numerically unstable beyond ~10 s, and the fp32 variant exceeded the 60 MB
bundle target (see `decisions.md`).

The 30 s cap (I-9) shapes `Transcriber`'s validation rules (FR-5/FR-6), and
`R = max(1, ((T_real+1)//2 + 1)//2)` from the real audio length gates both
the mask construction and the logits slice.

## As built (Phase 1)

```
Package.swift                    PyawwCore (library) + PyawwCLI (pyaww-cli), zero deps
Sources/PyawwCore/
  ModelConstants.swift           loads Models/*.json (mel filters, Hann, CMVN, vocab)
  AudioIO.swift                  AudioLoader (AVAudioFile) + AudioResampler (AVAudioConverter)
  FeatureExtractor.swift         fp32 log-mel + CMVN; 400-pt DFT as 2 vDSP mmul against
                                 precomputed cos/sin tables; single mel mmul
  ModelRunner.swift              fixed-30 s encoder; compile-once cache + self-heal
  Tokenizer.swift, Decoder.swift  greedy CTC (argmax, collapse, drop blank 0)
  TextPostProcessor.swift        v1: trim only
  Transcriber.swift              end-to-end samples/URL -> text, 30 s + 0.5 s rules
Sources/PyawwCLI/main.swift      pyaww-cli [--model-dir DIR] file... -> "name<TAB>text"
Tests/PyawwCoreTests/            Swift Testing (CLT has no XCTest); stage tests vs
                                 Tests/Fixtures/intermediates + 6-file end-to-end +
                                 edge cases; model suites .serialized
```

First launch compiles the `.mlpackage` with `MLModel.compileModel` into
`~/Library/Application Support/Pyaww/CompiledModels/` (no `coremlc` with
Command Line Tools); later launches load the cache. The logits output
`var_2170` is FLOAT16 — read it by its declared data type (model-spec.md §3).

One-command Gate 1 check: `scripts/run-parity.sh` (build → transcribe the
golden set with `pyaww-cli` → compare with `scripts/parity_swift.py` → CER
summary + reports).

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
.venv/                          Python 3.11 (uv) — parity/fixtures tooling
scripts/reconvert_coreml.py     checkpoint → Models/BurmeseASR-Encoder-30s.mlpackage
                                (+ fp32 sanity checks vs the reference)
scripts/export_fe_constants.py  I-8 constants → Models/mel_filters.json, hann_window.json
scripts/export_fixtures.py      golden-WAV → expected/*.txt + intermediates
                                (+ --verify-coreml parity report)
scripts/cer.py                  reference output vs gold transcripts → cer_report.tsv
scripts/parity_swift.py         Swift CLI outputs vs Python reference + CER → *_swift_report.tsv
scripts/run-parity.sh           Gate 1 one-command parity (build → run → compare)
scripts/make_golden_from_hf.py  deterministic golden-set builder (HF dataset)
scripts/parity_check.py         legacy probe: original 2 s asset vs torch
```

`myanmar_asr/` (the reference checkout the first three scripts import) was
deleted after Gate 1; re-clone from `huggingface.co/freococo/myanmar_asr` to
regenerate fixtures or the CoreML asset.

Fixtures layout:

```
Tests/Fixtures/audio/           100 golden WAVs (16 kHz mono, 33 MB)
Tests/Fixtures/manifest.tsv     provenance: source row, duration, held-out flag
Tests/Fixtures/transcripts/     gold transcripts (HF dataset text)
Tests/Fixtures/expected/        <stem>.txt Python reference outputs (101 files)
Tests/Fixtures/intermediates/   per-stage tensors for 4 files
Tests/Fixtures/parity_report.tsv  shipped asset vs reference, per clip
Tests/Fixtures/cer_report.tsv     reference vs gold transcripts, per clip
Tests/Fixtures/parity_swift_report.tsv  Swift vs reference (Gate 1 evidence)
Tests/Fixtures/cer_swift_report.tsv     Swift vs gold transcripts
```

Parity compares **Swift output vs Python reference output** (Gate 1), and
CER compares both to the owner's ground-truth transcripts (§5.3).
