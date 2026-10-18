# Pyaww architecture

Status: **as built at v0.1.0** — Phase 0 inspection, Phase 1 core, Phase 2
shell, Phase 3 measurements and Phase 4 panel/packaging are recorded below.
The authoritative spec is `SPEC.md` §4; this doc holds the as-built
decisions and the changes that inspection and the build revealed.

## Product shape

- **PyawwCore** — UI-free Swift package library: audio handling, model
  runner, decoder, tokenizer, post-processing, public `Transcriber` API.
  No AppKit/SwiftUI imports, fully unit-testable.
- **pyaww-cli** — thin executable: `pyaww-cli file.wav` → prints text.
  Same pipeline, CLI front-end, also the parity/benchmark harness.
- **Pyaww app** — AppKit `NSStatusItem` + hosted SwiftUI popover: recorder,
  hotkey, text inserter, permissions, one panel (settings included), state
  machine.

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

- `Transcribing` — `transcribe(samples:) async throws -> String` (Sendable)
- `AudioRecording` — `startRecording()`, `stopRecording() async`,
  `cancelRecording()`; mic capture, so tests can supply synthetic audio
- `TextInserting` — `insert(_:restoreClipboard:) async -> InsertionOutcome`;
  paste insertion, so tests can fake insertion

The app shell must never touch Core ML directly: only `PyawwCore`.

## Concurrency model

- Menu bar UI on `@MainActor`.
- Recording/ML/decoding off the main thread: `Transcriber` is an **actor**;
  the model loads in a detached task (+1 s silence warm-up) so launch never
  blocks the UI; recording stop resamples in a detached task; the audio tap
  only appends to a preallocated, lock-protected buffer.
- Explicit state machine in `AppState`: `idle → recording → transcribing
  → idle`, `error` recoverable; a press while busy is ignored (as-built),
  max duration auto-stops with a notice.
- Esc cancels recording synchronously (`cancelRecording` discards samples)
  and abandons in-flight transcription; app quit ends everything.

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

## App shell (Phase 2, as-built)

*Historical: the menu and the Settings window were retired in Phase 4 —
the current shell is in "Phase 3–4 as built" below.*

```
App/
  PyawwApp.swift           @main + MenuBarExtra/Settings scenes + AppModel (composition root)
  AppState.swift           state machine: idle/recording/transcribing/error (+ notice)
  AudioRecorder.swift      AVAudioEngine tap → preallocated buffer → 16 kHz mono on stop
  HotkeyManager.swift      NSEvent global+local monitors; PushToTalkKey (Right Option default)
  TextInserter.swift       pasteboard snapshot → ⌘V CGEvent → restore; secure-input aware
  PermissionsManager.swift mic + Accessibility status, prompts, System Settings deep links
  SettingsStore.swift      UserDefaults settings (+ SMAppService launch-at-login)
  MenuBarView.swift        menu content + state icon (FR-8)
  SettingsView.swift       settings form (FR-10)
  Info.plist               LSUIElement, com.tklwin.pyaww, microphone usage string
```

- Bundle assembled by `scripts/make-app.sh` (no Xcode on this machine):
  release binary + `Resources/Models/` (mlpackage + JSON constants) + plist,
  signed with "Pyaww Local" if the certificate exists, else ad-hoc.
- No SwiftUI property-wrapper macros are available in the CLT toolchain
  (`SwiftUIMacros` plugin absent); the app uses Observation (`@Observable`,
  `@Bindable`) and plain properties — SwiftUI tracks observable reads in
  `body` directly.
- `AppState` is protocol-driven (`AudioRecording`, `Transcribing`,
  `TextInserting`) and covered by `Tests/PyawwAppTests` with fakes.

## Phase 3–4 as built

**Performance and robustness (Phase 3).** Measured on the owner's M2:
median key-release → paste ~30 ms (target < 300 ms), cold start 0.57 s,
idle CPU 0.0 %, idle memory 77–88 MB (Activity Monitor footprint; strict
RSS is higher and documented), 38 MB bundle, zero crashes across the 100-
and 300-dictation soaks. Compute units stay `.all`: 27.5 ms p50 vs 58.5 ms
`.cpuOnly` and 82.0 ms `.cpuAndNeuralEngine`. The soak caught a Core ML
autorelease leak; `ModelRunner` now wraps each prediction in an
`autoreleasepool` and memory plateaus (~107.5 MB). Evidence:
`docs/performance.md`.

**One panel, own status item (Phase 4).** The menu and the Settings window
were retired: `MenuBarExtra(.window)` pinned its square window to the
screen corner, so `MenuBarController` hosts an `NSPopover` on an
`NSStatusItem` and macOS anchors the rounded panel under the wave. Both
mouse buttons toggle it; a same-click reopen after a transient close is
guarded. Current shell:

```
App/
  PyawwApp.swift           @main PyawwAppDelegate + AppModel (composition root)
  MenuBarController.swift  NSStatusItem + NSPopover (both buttons toggle)
  MenuBarIcon.swift        the icon's wave drawn at runtime: template idle/
                           transcribing, red while recording
  MenuPanelView.swift      one card panel: header; Permissions; Dictation;
                           Pasting; Feedback; Model; footer (version, GitHub, Quit)
  PanelComponents.swift    shared card/row/button styles
  AppState.swift           state machine: idle/recording/transcribing/error (+ notice)
  AudioRecorder.swift      AVAudioEngine tap → preallocated buffer → 16 kHz mono on stop
  HotkeyManager.swift      NSEvent global+local monitors; PushToTalkKey (Right Option default)
  TextInserter.swift       pasteboard snapshot → ⌘V CGEvent → restore; secure-input aware
  PermissionsManager.swift mic + Accessibility status, prompts, System Settings deep links
  SettingsStore.swift      UserDefaults settings (+ SMAppService launch-at-login)
  Info.plist               LSUIElement, com.tklwin.pyaww, microphone usage string
```

**Myanmar word segmentation.** A Swift port of `mmdt-tokenizer` 0.1.3 lives
in `Sources/PyawwCore/Segmentation/`; `AppState` applies it after
transcription and before pasting (toggle in the Dictation card, default
on; `pyaww-cli --segment` for inspection).

**Packaging and release.** `scripts/make-app.sh` assembles and signs the
bundle ("Apple Development: thein.kyawlwin@icloud.com", 8V26KMJK68);
`scripts/make-dmg.sh` builds the 600 × 400 installer window and
`scripts/patch-ds-store.py` fixes the stored icon positions for Finder.
v0.1.0 shipped as a non-notarized DMG on GitHub Releases
with the README's Gatekeeper steps; the landing page is documented in
`docs/website.md`.
