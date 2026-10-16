# Spec: Pyaww (ပြော), Myanmar Dictation for macOS (Native Swift)

*Spec-driven development brief for an AI coding agent. Version 1.0.*

## 0. How to use this document

You are an AI coding agent building a small native macOS app. This document is the source of truth. Rules:

1. Read the whole document before writing code.
2. Work **phase by phase** (Section 7). Do not start a phase until the previous phase's gate has passed.
3. If something is marked **\[INPUT NEEDED\]** or is ambiguous, **stop and ask the owner**. Never invent model hyperparameters, vocabulary, or normalization values.
4. At the end of every phase, report using the template in Section 14.
5. If this spec conflicts with your instinct, follow the spec and raise the conflict.

The owner is new to Swift. Prefer simple, readable, well-commented code over clever code. Explain non-obvious decisions in short comments and in the phase report.

## 1. Product summary

**One sentence:** Hold a hotkey, speak Myanmar, release, and the recognized Myanmar text is pasted into whatever app is focused.

**What it is:** A lightweight, offline, menu bar dictation app for Apple Silicon Macs, powered by the owner's own Myanmar Conformer ASR model (CoreML, about 39 MB).

**Who it is for:** Primarily the owner (personal use). Keep the design clean enough that it could be shared later, but do not add features for hypothetical users.

### Goals

- Fast: transcription of a typical 5 second clip feels instant (targets in Section 5).
- Small: tiny disk, memory, and idle CPU footprint.
- Private: fully offline. Audio and text never leave the machine.
- Correct: Swift output matches the owner's Python reference output.
- Maintainable by a beginner with an AI agent: simple architecture, strong tests.

### Non-goals (do NOT build in v1)

- Streaming / live partial results
- Meeting or long-form file transcription
- Multiple languages, language auto-detect
- Cloud APIs, accounts, sync, telemetry, analytics, auto-update
- AI rewriting or summarizing of text
- iOS / iPadOS / Intel Mac support
- Mac App Store distribution
- Transcription history UI

If you believe a non-goal is needed, ask first.

### Name and identifiers

- **App name:** Pyaww. Burmese: ပြော ("to speak"). Pronounced "p-yaw", IPA /pjɔ̀/. The double w is a stylistic choice and does not change the sound. Show the Burmese spelling ပြော in the UI and README.
- **Bundle ID:** `com.yourname.pyaww` \[INPUT NEEDED: owner's reverse-domain prefix\]. Set it once and never change it. macOS ties Microphone and Accessibility permissions to the bundle ID and signing identity, so changing either resets them.
- **Names in code:** core library `PyawwCore`, command line tool `pyaww-cli`, app target `Pyaww`, test target `PyawwCoreTests`, menu bar title "Pyaww".
- **Name check:** before Phase 4, the owner searches GitHub, the web, and trademark databases for collisions with "Pyaww".

## 2. Inputs the owner must provide

The agent cannot proceed past Phase 0 without these. Ask for any that are missing.

| # | Input | Status |
| --- | --- | --- |
| I-1 | The `.mlpackage` / `.mlmodel` file(s) | \[INPUT NEEDED\] |
| I-2 | Model I/O spec: input names, shapes, dtypes; output names, shapes, dtypes (from Xcode's model viewer or `coremltools`) | \[INPUT NEEDED\] |
| I-3 | Audio front-end spec: sample rate, channels, normalization, and if features are used: feature type, n\_mels, n\_fft, win\_length, hop\_length, window type, fmin/fmax, log type and floor, dither, pre-emphasis, per-utterance or global normalization | \[INPUT NEEDED\] |
| I-4 | Decoder type: CTC, RNN-T/transducer, or attention. If multiple CoreML models (encoder / decoder / joiner), their wiring | \[INPUT NEEDED\] |
| I-5 | Tokenizer/vocabulary file and how tokens map to text (SentencePiece, characters, blank/pad/unk IDs, word-boundary markers) | \[INPUT NEEDED\] |
| I-6 | Python reference inference script that produces correct text from a WAV | \[INPUT NEEDED\] |
| I-7 | At least 50 test WAVs with ground-truth transcripts (see Section 9) | \[INPUT NEEDED\] |
| I-8 | Mel filterbank and window exported from Python as raw `.bin` or `.npy` (so Swift loads them instead of recomputing) | \[INPUT NEEDED\] |
| I-9 | Maximum audio length the model supports, and whether input shape is fixed or flexible | \[INPUT NEEDED\] |

## 3. Target platform and tooling

- **Hardware:** Apple Silicon only (arm64).
- **OS:** macOS 14 (Sonoma) or later. \[Owner may change.\]
- **Language:** Swift (latest stable toolchain), Swift concurrency (`async/await`, actors) for new code.
- **UI:** SwiftUI with `MenuBarExtra`. Use AppKit only where SwiftUI cannot do the job (global hotkey, key events, pasting).
- **ML:** Core ML. Audio: `AVAudioEngine`. DSP: `Accelerate` (vDSP).
- **Build:** Swift Package Manager plus the build script in "Build and release". An Xcode project is optional.
- **Dependencies:** **None** third-party by default. Apple frameworks only. Any third-party package requires owner approval, with a stated reason, license, and size.
- **Network:** The app must not use the network. Do not add the network client entitlement.

### Build and release

- **Where v1 is built:** locally on the owner's Mac (Apple Silicon M2, 8 GB RAM). No CI is needed for v1. The build must succeed within 8 GB of RAM.
- **Toolchain:** start with Command Line Tools only (`xcode-select --install`) and build with SwiftPM (`swift build -c release`). Install full Xcode only if blocked, and tell the owner why. Check `xcrun --find coremlc`: if it is missing, compile the model on first launch with `MLModel.compileModel(at:)` and cache the compiled model in Application Support.
- **One build script:** `scripts/build-app.sh` builds in release mode, assembles `Pyaww.app` (Info.plist with `LSUIElement` and usage descriptions, the model resource, the icon) and signs it. Local builds and any later CI use this same script.
- **Signing:** use one stable identity locally (a free personal development certificate or a self-signed one) and record which in `docs/decisions.md`. Never change it between builds, or macOS resets the Microphone and Accessibility permissions.
- **CI is optional and belongs to Phase 5:** a GitHub Actions macOS runner can run the same script to build, sign, notarize and attach a release. That needs a paid Apple Developer account and signing secrets stored as repository secrets. Do not set it up unless the owner asks.

## 4. Architecture

Separate the app into a **UI-free core library** and a thin app shell. This makes everything testable from the command line.

```
Pyaww/
  Package.swift
  Sources/
    PyawwCore/               <- no UI, no AppKit. Fully unit-testable.
      AudioResampler.swift   - any input format -> 16 kHz mono Float32 (verify against I-3)
      FeatureExtractor.swift - log-mel via Accelerate, loads I-8 constants
      ModelRunner.swift      - loads CoreML model once, runs prediction
      Decoder.swift          - CTC or transducer decode (per I-4)
      Tokenizer.swift        - token IDs -> Myanmar text (per I-5)
      TextPostProcessor.swift- spacing, punctuation, Unicode checks
      Transcriber.swift      - public API: transcribe(samples) async throws -> String
    pyaww-cli/               <- command line tool: WAV in, text out
  Tests/
    PyawwCoreTests/          <- unit + parity tests + golden WAVs
  App/
    PyawwApp.swift           - MenuBarExtra entry
    AudioRecorder.swift      - mic capture (AVAudioEngine)
    HotkeyManager.swift      - push-to-talk key down/up
    TextInserter.swift       - paste into focused app
    PermissionsManager.swift - mic + accessibility status and guidance
    SettingsStore.swift      - UserDefaults-backed settings
    AppState.swift           - state machine: idle, recording, transcribing, error
```

### Rules

- `PyawwCore` must not import AppKit or SwiftUI.
- The public interface of `Transcriber` is a single async function. The app shell never touches CoreML directly.
- Use **protocols** at the boundaries (`AudioRecording`, `TextInserting`, `Transcribing`) so tests can use fakes.
- Keep files under about 300 lines. One responsibility per file.
- No global mutable state. Use actors or `@MainActor` for shared state.

### Data flow

```
hotkey down -> start recording -> hotkey up -> stop recording
 -> samples (16 kHz mono Float32)
 -> FeatureExtractor -> ModelRunner (CoreML) -> Decoder -> Tokenizer
 -> TextPostProcessor -> TextInserter (paste) -> idle
```

## 5. Requirements

### 5.1 Functional

| ID | Requirement |
| --- | --- |
| FR-1 | Menu bar app with no Dock icon (`LSUIElement`). Menu shows status, settings, and Quit. |
| FR-2 | Push-to-talk: recording runs while the hotkey is held. Default hotkey is configurable (suggest a modifier key such as Right Option, or a key combination). |
| FR-3 | On release, transcribe and paste the text at the cursor in the focused app. |
| FR-4 | Pressing Esc while recording cancels with no paste. |
| FR-5 | Ignore recordings shorter than a minimum (default 0.3 s) or silent clips. Do not paste empty or garbage text. |
| FR-6 | Enforce a maximum recording length derived from I-9. At the limit, stop recording and warn. Never feed the model out-of-range input. |
| FR-7 | Restore the user's previous clipboard contents after pasting (see 6.5). |
| FR-8 | Clear visual state in the menu bar icon: idle, recording, transcribing, error. |
| FR-9 | First-run guidance for Microphone and Accessibility permissions, with a deep link to the correct System Settings pane. The app keeps working in a degraded, clearly explained state if a permission is missing. |
| FR-10 | Settings: hotkey, minimum/maximum duration, launch at login, restore-clipboard on/off, optional sound cue. |
| FR-11 | Launch at login via `SMAppService`. |

### 5.2 Non-functional (targets, to be measured and confirmed in Phase 3)

These are initial targets. Measure on the owner's Mac and report real numbers. If a target is unrealistic, report it and propose a revised one, do not silently relax it.

| Metric | Target |
| --- | --- |
| Transcription latency, 5 s clip, after warm-up | under 300 ms from key release to paste |
| Cold start to ready | under 2 s |
| Idle CPU | about 0% |
| Resident memory, idle | under 150 MB |
| App bundle size | under 60 MB (model plus app) |
| Crashes during 100 consecutive dictations | 0 |

### 5.3 Accuracy

- **Parity (hard gate):** Swift decoded text must equal the Python reference text on every golden file (exact string match), or differ only by a documented, owner-approved tolerance.
- **Quality (tracked):** Report CER on the golden set for both Python and Swift. Swift must not be worse than Python by more than 0.1% absolute CER.

## 6. Implementation guidance and best practices

### 6.1 Core ML

- Load the model **once** at launch, off the main thread, and keep it for the app's lifetime.
- Run a **warm-up inference** on a short silent buffer right after loading so the first real dictation is fast.
- Start with `MLModelConfiguration.computeUnits = .cpuAndNeuralEngine`. Benchmark `.all` and `.cpuOnly` too and report which is fastest. Do not assume.
- Use the compiled model (`.mlmodelc`) produced by Xcode when Xcode is available. Without Xcode, compile once on first launch and cache the result (see "Build and release").
- Prefer reusing preallocated `MLMultiArray` buffers over allocating per call, where practical.
- Check the model's precision (Float16 vs Float32) and match input dtypes exactly.
- If the model has fixed input length, pad/chunk in the app according to I-9, and make sure padding is masked or handled as in the Python reference.
- Measure before optimizing: use your own timing benchmark, plus Xcode's Core ML performance report and Instruments if Xcode is installed. Never optimize by guess.

### 6.2 Audio capture and front-end

- Capture with `AVAudioEngine` input tap. Convert to the model's expected format (I-3, typically 16 kHz mono Float32) with `AVAudioConverter`. Do not assume the hardware sample rate.
- Do audio callbacks on the audio thread only for copying buffers. No allocation-heavy work, no locks that can block, no UI work in the tap.
- Keep audio **in memory only**. Do not write recordings to disk unless a debug flag is on, and that flag is off by default.
- **Feature extraction must reproduce the Python front-end exactly.** Load the window and mel filterbank from the exported files (I-8) instead of regenerating them. Match padding mode, frame count formula, log floor, and normalization from I-3.
- Implement the STFT with `vDSP` (FFT setup created once and reused).
- Save intermediate tensors from Python (raw samples, mel features, encoder output, token IDs) for a few files, and test Swift against each stage. When output diverges, the first stage that disagrees is the bug.

### 6.3 Decoding and tokenizer

- Implement exactly the decoder in I-4. For CTC: argmax per frame, collapse repeats, remove blanks. For transducers: follow the Python reference loop precisely, including max symbols per frame.
- Tokenizer must handle special tokens (blank, pad, unk, boundary markers) exactly per I-5. Unknown IDs must not crash: skip and log at debug level.

### 6.4 Myanmar text handling (important)

- Output must be **Unicode** Myanmar text. **Zawgyi is out of scope** unless the owner says otherwise.
- **Do not blindly apply** NFC/NFKC or other normalization that could reorder or alter Myanmar combining characters. If normalization is needed, it must be defined by the owner, implemented as an explicit, tested function, and covered by golden tests.
- Sentence punctuation (the section sign `။` and little section `၊`) and spacing rules, if any, live in `TextPostProcessor` as small, documented, individually testable rules. Default in v1: **no post-processing** beyond trimming leading/trailing whitespace, unless the owner specifies rules.
- Validate that output contains only expected Unicode ranges (Myanmar block, Myanmar Extended-A/B if needed, ASCII digits/punctuation, spaces). If unexpected characters appear, log in debug and still paste unless the owner decides otherwise.
- Test rendering of pasted text in the app matrix in Section 9.3.

### 6.5 Hotkey and text insertion

This is where macOS permission rules bite. Evaluate and **document your choice** in the Phase 2 report.

- **Hotkey:** Push-to-talk needs both key-down and key-up. Options: a global monitor or event tap for `flagsChanged` (modifier-only keys) or key events. These require Accessibility and/or Input Monitoring permission. Choose the simplest approach that is reliable and explain why.
- **Insertion:** Default method: write text to `NSPasteboard`, post a synthetic Cmd+V with `CGEvent`, then restore the previous clipboard contents after a short delay (preserve all pasteboard types, not just plain text). Requires Accessibility permission.
- Handle failure: if paste cannot be performed (no permission, secure input field), leave the text on the clipboard and show a small notification saying so. Never lose the user's transcription silently.
- Respect secure input: do not attempt to defeat password-field protection.
- Never log transcribed text in release builds.

### 6.6 Concurrency and responsiveness

- Main thread for UI only. Recording, feature extraction, inference, and decoding run off the main thread.
- Model the app as an explicit state machine (`idle`, `recording`, `transcribing`, `error`). Ignore a new hotkey press while transcribing, or queue exactly one. Define the behavior and test it.
- Make long operations cancellable (Esc, app quit).
- Use Swift 6 strict concurrency checking where feasible. Resolve warnings, do not suppress them.

### 6.7 Error handling

- Use typed errors (`enum ASRError: Error`) with human-readable messages.
- Forbidden in app code: `try!`, force unwraps (`!`) outside tests, `fatalError` for recoverable conditions.
- Every failure shows a short message in the menu and does not crash. Examples: model failed to load, mic permission denied, no input device, inference failed, paste failed.

### 6.8 Privacy and security

- No network code, no analytics, no crash-reporter SDKs.
- No audio or transcript persistence by default.
- Logs use `os.Logger`. Transcripts and audio are never logged at `info` level or above. Mark any debug-only text logging with `#if DEBUG`.
- Request only the permissions needed: Microphone, Accessibility (and Input Monitoring only if the hotkey approach requires it). Provide accurate usage description strings in `Info.plist`.
- Do **not** enable App Sandbox if it prevents synthetic paste. Document the resulting entitlements list in the repo.

### 6.9 Code quality

- Follow Swift API Design Guidelines. Add `///` doc comments on all public types and functions.
- Add `swift-format` or SwiftLint configuration only if the owner approves a dev-time tool.
- Commit in small, reviewable steps with clear messages. One logical change per commit.
- No dead code, no commented-out blocks, no TODOs without an issue note in `docs/TODO.md`.

## 7. Delivery plan with gates

Do not skip gates. At each gate, stop, report, and wait for owner confirmation.

### Phase 0: Ground truth and model inspection

- Collect inputs I-1 to I-9. Ask for anything missing.
- Inspect the model: write `docs/model-spec.md` summarizing inputs, outputs, shapes, dtypes, compute precision.
- Run the Python reference on every golden WAV and store outputs as `Tests/Fixtures/expected/*.txt` plus intermediate tensors for 3 to 5 files.
- **Gate 0:** `model-spec.md` reviewed and approved by owner; golden set and expected outputs in the repo.

### Phase 1: Core library and CLI (no UI)

- Implement `PyawwCore and pyaww-cli (pyaww``-cli file.wav` prints text).
- Build stage by stage: resample, features, model, decoder, tokenizer. Add a stage test for each, comparing against saved Python tensors.
- **Gate 1 (critical):** Swift output exactly matches Python on all golden files, via an automated test that runs with one command. CER report generated. Feature tensors match Python within a documented tolerance (suggest max absolute error 1e-3 for Float32 features, adjust and justify if the front-end differs).

### Phase 2: Menu bar app

- Implement recorder, hotkey, permissions, text inserter, state machine, menu UI.
- **Gate 2:** End-to-end dictation works in Notes, Safari, Chrome, VS Code, Terminal, and Telegram or Messages. All FR items 1 to 9 demonstrated.

### Phase 3: Performance and robustness

- Measure the non-functional targets in 5.2 and report real numbers. Benchmark compute units. Fix hot spots using Instruments.
- Run a soak test (100 consecutive dictations) with memory tracked.
- **Gate 3:** Targets met or revised targets approved. No memory growth trend. No crashes.

### Phase 4: Polish and packaging (personal use)

- Settings, launch at login, icon, error messages, first-run onboarding.
- Sign with a **stable** signing identity (a free personal Apple development identity is enough for personal use). Note: changing the signing identity makes macOS reset Accessibility and Microphone grants, so keep it consistent.
- Provide `README.md` with build, install, permissions, and troubleshooting steps.
- **Gate 4:** Clean install on the owner's Mac works from the README alone.

### Phase 5 (optional, only if owner asks)

Developer ID signing and notarization for sharing; a GitHub Actions build and release workflow that runs scripts/build-app.sh; additional features from the non-goals list.

## 8. Guardrails: what the agent must never do

1. Never modify, re-export, quantize, or "optimize" the model files. Treat them as read-only.
2. Never guess audio front-end parameters, vocabulary, or normalization. Ask.
3. Never add third-party dependencies, network access, telemetry, or auto-update without explicit approval.
4. Never write recordings or transcripts to disk by default.
5. Never disable tests or loosen tolerances to make a gate pass. If a test fails, find the cause or escalate.
6. Never claim a gate passed without showing the command run and its output.
7. Never use `try!`, force unwrap, or `fatalError` for recoverable errors in app code.
8. Never block the main thread with audio, ML, or file work.
9. Never rewrite working modules wholesale for style. Make targeted changes.
10. Never copy code from other projects (Hex, FluidAudio, WhisperKit, others) verbatim. You may read them for ideas and patterns. If you adopt anything substantial, tell the owner and check the license.
11. Never change Xcode signing, entitlements, bundle identifier, or deployment target without telling the owner first.
12. Never apply Unicode normalization to Myanmar output unless this spec defines it.
13. Stop and ask when blocked for more than two attempts on the same problem.

## 9. Testing strategy

### 9.1 Golden set (owner-provided, I-7)

- Minimum 50 clips, aiming for 100. Store under `Tests/Fixtures/audio/` with transcripts in `Tests/Fixtures/expected/`.
- Must include: short (1 to 2 s) and long (near max length) utterances, numbers, names, Myanmar-English mixed speech, noisy rooms, different speakers and speeds, and clips recorded with the Mac's built-in microphone through the app itself (not only clean dataset audio).
- Keep a **held-out** subset that the agent does not tune against.

### 9.2 Automated tests

| Type | What |
| --- | --- |
| Unit | Resampler, feature extractor against known inputs, decoder on synthetic logits, tokenizer round trips, post-processor rules |
| Stage parity | Each pipeline stage vs saved Python tensors |
| End-to-end parity | WAV to text, exact match on the golden set |
| Edge cases | Empty audio, silence, 0.1 s clip, clip over max length, NaN-free output, unknown token IDs |
| State machine | Rapid repeated hotkey presses, cancel, permission revoked mid-session |

Provide one command to run everything (for example `swift test` and a `scripts/run-parity.sh`).

### 9.3 Manual app matrix (Phase 2 and 4)

Test paste and Myanmar rendering in: Notes, Safari, Chrome, VS Code, Terminal, Telegram or Messages, Word or Pages. Record pass/fail and any rendering problems in `docs/manual-test-log.md`.

### 9.4 Performance tests

Automated benchmark in the CLI: run N=50 inferences on 5 s audio, report median and p95 latency. Track memory across 100 dictations.

## 10. Observability (local only)

- `os.Logger` with categories: `audio`, `model`, `hotkey`, `paste`, `state`.
- Log timings per stage (capture length, features ms, inference ms, decode ms, paste ms) at `debug` level. No content.
- A hidden debug menu (behind a flag) may show last-run timings. No transcript storage.

## 11. Documentation to deliver

- `README.md`: what it is, requirements, build and install, permissions, troubleshooting.
- `docs/model-spec.md`: model I/O and front-end spec.
- `docs/architecture.md`: the module diagram and data flow, kept current.
- `docs/decisions.md`: short log of decisions (hotkey method, compute units, insertion method) with reasons.
- `docs/manual-test-log.md` and the latest benchmark results.

## 12. Definition of done (v1)

- [ ] Parity gate passes on the full golden set with one command.
- [ ] End-to-end dictation works in the full app matrix.
- [ ] Performance targets met or revised and approved.
- [ ] 100-dictation soak test: no crash, no memory growth.
- [ ] No network usage (verify with a network monitor during a session).
- [ ] No audio or transcripts persisted.
- [ ] Permissions flow tested from a clean state (reset with `tccutil`).
- [ ] README lets the owner rebuild and reinstall from scratch.

## 13. Reference material (read-only inspiration)

- **Hex** (kitlangton/Hex): Swift menu bar dictation app. Look at how it handles hotkeys, permissions, paste, and settings. It uses The Composable Architecture, which this project deliberately does not.
- **FluidAudio** and **WhisperKit**: Swift packages that run speech models through Core ML. Look at audio preprocessing, model loading, and decoding patterns.
- Apple documentation: Core ML, `AVAudioEngine`, `Accelerate`/vDSP, `MenuBarExtra`, `SMAppService`, `NSPasteboard`, `CGEvent`.

Verify licenses before reusing any code. Prefer understanding and re-implementing.

## 14. Phase report template

At the end of each phase, reply with:

1. **Summary:** what was built, in 3 to 5 lines.
2. **Gate status:** pass or fail, with the exact commands run and their output.
3. **Metrics:** parity result, CER, latency, memory (as relevant).
4. **Decisions made:** and why.
5. **Deviations from spec:** none, or list with justification.
6. **Open questions / blockers** for the owner.
7. **Proposed next step.**

## 15. Starter prompt for the agent

> You are building Pyaww, the app described in `SPEC.md`. Read it fully. Start with Phase 0 only. List which inputs (I-1 to I-9) you have and which are missing, then ask me for the missing ones. Do not write app code until Gate 0 is approved. Follow the guardrails in Section 8 and report using Section 14.
