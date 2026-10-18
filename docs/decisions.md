# Pyaww decisions log

One line per decision: what, why, when. Newest at the bottom.
Decisions flagged **[OWNER]** are awaiting the owner's answer before they
become final.

Entries are append-only: supersede a decision with a new entry rather than
rewriting the record.

## Index

- [Phase 0 (2026-10-16)](#phase-0-2026-10-16)
- [Phase 1 (2026-10-16)](#phase-1-2026-10-16)
- [Phase 2 (2026-10-17)](#phase-2-2026-10-17)
- [Phase 3 (2026-10-17)](#phase-3-2026-10-17)
- [Phase 4 (approved additions, 2026-10-17)](#phase-4-approved-additions-2026-10-17)
- [Phase 4 close-out continued (2026-10-17)](#phase-4-close-out-continued-2026-10-17)
- [Popover rework (2026-10-18)](#popover-rework-2026-10-18)
- [Marketing site (2026-10-18)](#marketing-site-2026-10-18)

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
- **Probe scripts live in `scripts/`, not the app.** Analysis tools are
  AI/agent tooling, not app code, and are excluded from any app bundle.
  *(2026-10-16: consolidated — `inspect_coreml.py`/`dump_mlprogram.py` were
  folded into the surviving scripts and deleted; see the cleanup entry below.)*
- **First-launch model compile fallback required** — confirmed `xcrun
  coremlc` is unavailable with Command Line Tools only (spec's
  `MLModel.compileModel` + Application Support cache plan stands).
- **[OWNER] Signing identity for stable local builds** is not yet decided
  (free Apple Development certificate vs self-signed). Record here once
  chosen, before Phase 4 — changing it resets TCC permissions.

- **[OWNER, approved 2026-10-16] Bundle ID = `com.tklwin.pyaww`.** Set once
  in Phase 2 (app target + Info.plist) and never changed afterwards.

- **[OWNER, approved 2026-10-16] Audio input re-conversion to 30 s.**
  The shipped asset's fixed 2 s input is too short for dictation. I will
  re-export from the owner's untouched checkpoint using their own
  architecture code + conversion recipe (coremltools), producing
  `Models/BurmeseASR-30s.mlpackage`. The original 2 s asset stays on disk
  untouched as provenance/reference. *(Superseded 2026-10-16: the end-to-end
  30 s fp16 asset was withdrawn as numerically unstable; final asset is
  `Models/BurmeseASR-Encoder-30s.mlpackage` — see the encoder-only entry
  below.)*

- **[OWNER, approved 2026-10-16] Golden test set source =
  chuuhtetnaing/myanmar-speech-dataset-for-asr** (HuggingFace). Select a
  representative subset (≥50 clips, varied durations/conditions) with
  ground-truth transcripts; reference outputs are generated from the
  owner's Python pipeline by `scripts/export_fixtures.py`.

- **[OWNER] Do not push to origin yet.** Model-spec reviewed and approved
  2026-10-16; pushing still awaits the owner's explicit go-ahead.

- **Encoder-only deployment split (2026-10-16).** The end-to-end fp16
  re-conversion is numerically unstable at long lengths (the fp16 STFT/mel
  chain overflows to `inf` beyond ~10 s; 244,938 `inf` values measured; fp32
  end-to-end is 95 MB > 60 MB bundle target). The front-end has no learned
  weights, so Swift computes features (fp32, I-8 constants) and Core ML hosts
  the encoder with a fixed 3001-frame mel input
  (`Models/BurmeseASR-Encoder-30s.mlpackage`, 39.4 MB). Restores the SPEC §4
  pipeline (AudioResampler → FeatureExtractor → ModelRunner). Details:
  model-spec.md §2.

- **Mask contract for the fixed 30 s input (2026-10-16).** The `frame_bias`
  and `conv1_bias` model inputs reproduce the reference's variable-length
  computation exactly on valid rows: attention-key masking past `R`, conv1
  row zeroing past `l1` (even-`T_real` edge case), and conformer-conv GLU
  zeroing past `R` (the 31-tap depthwise-conv boundary). Without them, pad
  rows leak into valid rows and short clips lose trailing tokens. fp32 sanity:
  `max|diff| <= 4.6e-05` vs the unpadded reference on 12 probe clips.
  Contract: model-spec.md §3.

- **Shipped precision = `w16` (fp16 linear/conv weights, fp32 activations),
  39.4 MB (2026-10-16).** Measured vs the fp32 reference on 101 files:
  fp16 93/101 exact, attn32 100/101, attn32ln 100/101, w16 100/101,
  fp32 101/101 (77.8 MB). All mismatches are single-frame knife-edge flips
  (fp32 top-1/top-2 margin 0.012–0.118 at the flipped frames). w16 has the
  smallest drift of the size-compliant variants; its one miss (g2063) is a
  frame with margin 0.0122 vs w16 diff 0.0119 → one token differs.
  `scripts/reconvert_coreml.py` defaults to w16; `--precision fp32`
  regenerates the exact variant. **[OWNER, approved 2026-10-16]** — the
  g2063 tolerance is accepted (SPEC §5.3 documented-tolerance clause).

- **Constant format = JSON, not .bin/.npy (2026-10-16).** SPEC I-8 suggested
  raw `.bin`/`.npy`; the owner's existing `Models/cmvn.json` +
  `Models/vocab.json` set the convention, so `scripts/export_fe_constants.py`
  exports `mel_filters.json` (80×201) and `hann_window.json` (400) in JSON
  too. Negligible parse cost, human-inspectable. **[OWNER, approved
  2026-10-16]** — keep JSON.

- **`Models/mel_filters.json` regenerated (2026-10-16).** The file in the
  repo was Slaney-normalized (`torchaudio norm='slaney'`), which does NOT
  match the reference pipeline (`transcribe.py` + `preprocessor_config.json`
  use torchaudio defaults, `mel_scale='htk', norm=None`). Parity requires the
  reference matrix, so `mel_filters.json` is now the verified
  reference-correct one; the previous content is preserved as
  `Models/mel_filters.slaney.json`. **[OWNER, confirmed 2026-10-16].**

- **Fixtures schema (2026-10-16).** `Tests/Fixtures/expected/*.txt` = Python
  reference output for 101 files (example.mp3 + 100 golden WAVs);
  `Tests/Fixtures/intermediates/` (4 files: example, g0001–g0003) now holds
  `samples_full.npy`, `mel_cmvn_full.npy`, `mel_cmvn_padded.npy`,
  `frame_bias.npy`, `conv1_bias.npy`, `logits_full.npy`, `meta.json` (the
  2 s-era `samples_padded.npy` was dropped). `parity_report.tsv` (shipped
  asset vs reference per clip) and `cer_report.tsv` live alongside.

- **Debug scripts deleted (2026-10-16).** `debug_*`, `dump_*`,
  `inspect_coreml.py`, `bisect_convert.py`, `length_sweep.py` removed; their
  findings live in this log + model-spec.md. Kept:
  `reconvert_coreml.py`, `export_fe_constants.py`, `export_fixtures.py`,
  `cer.py`, `parity_check.py` (legacy 2 s asset probe), `make_golden_from_hf.py`.

- **[OWNER, approved 2026-10-16] Gate 0 closed.** `docs/model-spec.md`
  approved as-is; all pending decision items above resolved; Phase 1 may
  start.

- **[OWNER, approved 2026-10-16] Model-file git tracking.** Commit the
  deployment asset `Models/BurmeseASR-Encoder-30s.mlpackage` (39.4 MB) + the
  JSON constants; keep the 91 MB checkpoint (`myanmar_asr/`, the owner's own
  nested repository) and the legacy 38 MB 2 s asset out of git
  (`.gitignore`). No LFS for now.

## Phase 1 (2026-10-16)

- **Swift tests use Swift Testing (`import Testing`), not XCTest.** This
  machine has Command Line Tools only: XCTest is unavailable, while the
  toolchain ships `Testing.framework` + its macro plugin. Command unchanged:
  `swift test`. Suites that load the model are `.serialized` to keep the
  8 GB machine calm.
- **`var_2170` is FLOAT16 in the model description; the native `MLModel`
  API returns it as Float16.** Phase 0 had recorded FLOAT32 because the
  coremltools Python `predict()` upcasts. `ModelRunner` now reads the output
  by its declared data type. (First test run produced 5.5e8 garbage diffs by
  reinterpreting fp16 bytes as fp32 — fixed by the dtype-aware reader.)
- **ModelRunner compile cache hardened.** Compile-once into
  `~/Library/Application Support/Pyaww/CompiledModels` stays, plus: a
  process-wide lock (parallel test suites raced to write the cache on the
  first run and produced a half-written `.mlmodelc`) and self-healing — an
  unloadable cache entry is deleted and recompiled once.
- **Gate 1 parity policy: 100/100 exact; `g2063` stays allowlisted.**
  `scripts/run-parity.sh` is the one command (build + golden-set run +
  compare + CER). On the owner's machine the Swift path (`.all` compute
  units) reproduced the reference text exactly on all 100 golden files —
  including `g2063`, where the Phase 0 coremltools CPU check had flipped one
  knife-edge frame. The allowlist entry remains as documented tolerance in
  case another compute path flips it. Reports:
  `Tests/Fixtures/parity_swift_report.tsv`, `Tests/Fixtures/cer_swift_report.tsv`.
- **Python reference checkout removed after Gate 1 (owner-approved).**
  `myanmar_asr/` (91 MB, gitignored) deleted; re-clone with
  `git clone https://huggingface.co/freococo/myanmar_asr myanmar_asr` before
  running `scripts/reconvert_coreml.py`, `scripts/export_fixtures.py`, or
  `scripts/parity_check.py`. Swift no longer needs it for parity.

## Phase 2 (2026-10-17)

- **[OWNER] Phase 2 kickoff decisions.** Default hotkey: **Right Option**.
  Signing: create a local self-signed **"Pyaww Local"** code-signing
  certificate (one-time guide in `docs/build-release.md`) so Microphone/Accessibility
  grants survive rebuilds. Phase 1 pushed to `origin/main` (approved).
- **App = SPM executable target `App/` + hand-assembled bundle**
  (`scripts/make-app.sh`): this machine has Command Line Tools only (no
  `xcodebuild`). The script builds release, copies `App/Info.plist`
  (`LSUIElement`, `com.tklwin.pyaww`, mic usage string) and the tracked
  `Models/` resources (mlpackage + 4 JSON constants), then signs with
  "Pyaww Local" when present, else ad-hoc with a warning. Bundle ≈ 38 MB
  (budget 60 MB). No sandbox, no entitlements file, hardened runtime off.
- **No SwiftUI property-wrapper macros.** The CLT toolchain ships
  `libObservationMacros` but not `SwiftUIMacros`, so `@State`/`@Environment`
  cannot compile here. The app keeps SPEC §4's SwiftUI `MenuBarExtra` design
  but uses plain stored properties + Observation (`@Observable`,
  `@Bindable`); SwiftUI's observation tracking re-renders the menu bar.
- **Hotkey = NSEvent global + local monitors** (`flagsChanged` for Right
  Option / Right Command, `keyDown` for Esc). SPEC §6.5's "simplest reliable"
  option; a `CGEventTap` would need the same Accessibility permission with
  more machinery. Input Monitoring is not required.
- **Insertion (SPEC §6.5, FR-3/FR-7)**: snapshot **all** pasteboard items
  and types → set the transcript → synthetic ⌘V (`CGEvent`) → restore the
  snapshot 0.4 s later, only if the user has not copied something else
  (`changeCount` check). Without Accessibility, or under secure input, the
  transcript stays on the clipboard and the menu shows a reason — text is
  never lost.
- **State machine behaviors (SPEC §6.6, covered by tests):** a press while
  recording/transcribing is **ignored** (nothing queued); Esc cancels a
  recording synchronously (`cancelRecording` discards samples) and abandons
  an in-flight transcription (paste skipped at the cancellation check; the
  Core ML `predict` itself cannot be interrupted); at the maximum duration
  the recorder stops itself, transcribes what was captured, and shows a 6 s
  notice. Silent clips (peak < 1e-4, ≈ −80 dBFS) are dropped before
  inference (FR-5).
- **`Transcriber` is now an actor** implementing `Transcribing` (SPEC §4's
  single async function). The app loads it in a detached task and runs a
  1 s-silence warm-up inference (SPEC §6.1); hotkey presses before ready get
  a clear "still loading" error instead of a silent no-op.
- **Boundary protocols (SPEC §4)**: `Transcribing` (Sendable, async),
  `@MainActor AudioRecording` (`startRecording` / async `stopRecording` /
  sync `cancelRecording`), `@MainActor TextInserting`
  (`insert(_:restoreClipboard:) -> InsertionOutcome`). Fakes + 9 app-state
  tests live in `PyawwAppTests`; `swift test` = 11 core + 9 app tests.
- **Recorder choices (SPEC §6.2)**: capture at the hardware format into a
  preallocated buffer — the audio thread only appends (`OSAllocatedUnfairLock`
  around a bounded memcpy; no allocation in the steady path) — then downmix
  to mono and resample to 16 kHz once, off the main thread, on stop.
- **First-run guidance (FR-9)**: microphone prompt at first launch, then the
  Accessibility prompt; menu and Settings show live status with System
  Settings deep links plus a Refresh button (Accessibility state can change
  while the app runs). Sound cue defaults **off** (FR-10).

## Phase 3 (2026-10-17)

- **[OWNER] Gate 2 passed.** Owner ran the manual matrix in
  `docs/evidence/manual-test-log.md`: paste ✅ and clipboard restore ✅ in Notes,
  Safari, Chrome, VS Code, Terminal, Messages/Telegram; FR-1…FR-10 all ✅
  (FR-4 confirmed on retest). Two edge cases were unreachable by hand
  because transcription finished "too fast" — both are covered by unit
  tests (`pressWhileTranscribingIsIgnored`, `escapeCancelsRecording`).
  Owner confirmed the hotkey set stays Right Option (default) + Right
  Command.
- **[OWNER] Signing: Apple Development identity.** `scripts/make-app.sh`
  now signs with the first *Apple Development* identity
  ("Apple Development: thein.kyawlwin@icloud.com"), falling back to
  "Pyaww Local" then ad-hoc. Grants now persist across rebuilds; the switch
  from the previously ad-hoc bundle requires a one-time re-grant
  (checklist in `docs/evidence/manual-test-log.md`).
- **Compute units: keep `.all`** (benchmarked per SPEC 6.1, not assumed):
  27.5 ms p50 vs 58.5 ms cpuOnly vs 82.0 ms cpuAndNeuralEngine on a 4.95 s
  clip. Numbers: `docs/evidence/performance.md`.
- **Memory bug found by the Phase 3 soak and fixed:** Core ML autoreleased
  objects accumulated ~4.7 MB per dictation (98.8 → 572.2 MB over 100
  clips) because the actor executor has no run-loop drain. Explicit
  `autoreleasepool` per prediction → 300-clip soak plateaus ~107.5 MB with
  no growth trend. Parity re-verified 100/100 exact afterwards.
- **Cold start measured 573 ms** in-app (exec → ready ≈ 0.61 s) — target
  < 2 s.
- **"Resident memory" definition:** read as Activity Monitor
  `phys_footprint` (77–88 MB idle; target < 150 MB met). Strict RSS is
  175–187 MB (shared framework pages included) — owner confirms the
  reading when approving Gate 3.
- **[OWNER] Gate 3 passed (2026-10-17).** Owner reviewed
  `docs/evidence/performance.md` with "resident memory" = Activity Monitor footprint
  (77–88 MB idle; strict RSS 175–187 MB noted) and ticked the Phase 3
  re-verify table in `docs/evidence/manual-test-log.md`: microphone + Accessibility
  grants after the signing switch, menu bar green, one dictation pasted,
  clean quit.

## Phase 4 (approved additions, 2026-10-17)

- **[OWNER] Word segmentation: approved, default ON.** Owner accepts the
  de-space + mmdt segmentation style as the natural national style ("more
  natural and similar to human instinct"). It ships as a **Swift port** of
  `mmdt-tokenizer` (MIT, Myanmar Data Tech) inside the SPEC §6
  `TextPostProcessor` hook, with a Settings toggle (default on; turning it
  off pastes the raw model text). This is the first Phase 4 work item.
  Evaluation: boundary F1 vs human gold 0.27 → 0.33 (64/99 clips better),
  0/100 clips corrupted, ~1 ms/clip; full numbers in TODO/parking-lot
  record and git history.
- **Word-segmentation port landed (2026-10-17, local commit).**
  `Sources/PyawwCore/Segmentation/`: `MMDTConfig` (generated by
  `scripts/generate_mmdt_config.py` from mmdt 0.1.3 sources),
  `MyanmarSyllables`, `MMDTLexicon`, `MMDTSegmenter` (preprocess →
  syllabify → tag → merges/cleans → patched collapse → join/attach) and
  `PyawwCoreResources` (resource lookup without SwiftPM's `Bundle.module`,
  whose generated accessor `fatalError`s when the bundle is missing).
  Fidelity: **209/209 exact** vs Python-generated vectors
  (`Tests/Fixtures/segmentation/vectors.tsv`), plus idempotence and
  character-preservation tests. Adaptations as approved: de-space between
  Myanmar word characters first; punctuation kept and attached (upstream
  drops `,` `?` `!` `၊` from its token stream). One upstream quirk is
  deliberately **not** replicated: CPython's `str.split()/strip()` treat
  U+001C–U+001F as whitespace, which can split a protection placeholder
  apart at ≥12 protected entities; the port uses Unicode White_Space only
  (documented in `MMDTSegmenter.swift`).
- **Wiring (2026-10-17):** Settings toggle "Segment Myanmar words" (default
  on, persisted in UserDefaults); `AppState` applies segmentation after
  transcription, before the paste, and logs the duration; the Settings
  Model section shows "Word segmentation: Ready/Unavailable" (missing
  lexicon degrades to raw text, never crashes). `make-app.sh` copies both
  `lexicons.json` and `Pyaww_PyawwCore.bundle` into the app. CLI gained
  `--segment` (defaults off so parity/quality scripts stay raw) and
  `--segment-text STRING`. Measured (release): init 19.3 ms once, longest
  corpus text 3.8 ms — `docs/evidence/performance.md`. `swift test` = 17 core + 12
  app tests.
- **[OWNER] Word segmentation verified in-app (2026-10-17).** Owner ticked
  the Phase 4 table in `docs/evidence/manual-test-log.md`: word text pastes
  ("မင်္ဂလာ ပါ" style), toggle off = raw syllable text, toggle on again,
  Settings → Model shows "Ready".
- **Settings window comes to the front — final (2026-10-17, owner reports).**
  As an accessory app (`LSUIElement`) Pyaww is not activated by menu bar
  clicks, so the Settings window opened behind the frontmost app (owner:
  findable only via Mission Control). Probing macOS 27.0.1 with a scratch
  `LSUIElement` app showed: the private `showSettingsWindow:` selector is
  answered but no longer creates the window (an intermediate fix using it
  alone opened nothing — owner report #2); the public `openSettings` action
  creates the window (`com_apple_SwiftUI_Settings_window`) without
  activating the app; cooperative activation (`NSApp.activate()`,
  `NSRunningApplication.activate(options:)`) is a no-op for an accessory
  app; only `activate(ignoringOtherApps:)` (deprecated but functional)
  activates it, after which the window becomes key. Final wiring:
  `SettingsWindow.activateApp()` → `openSettings()` → bounded retry raising
  the window; a belt repeats this in `SettingsView.onAppear`.
  **[OWNER] Verified (2026-10-17):** the window comes to the front on the
  first click; re-verify table ticked in `docs/evidence/manual-test-log.md`.
- **Push approved + done (2026-10-17):** `e0398b4`, `9e972e8` and the
  Gate 3 / Settings-window commits are on `origin/main`.
- **Settings fix pushed (2026-10-17):** after owner verification, `a97c499`
  (fronting fix + test-runner `TestingMacros` plugin-path flags + docs) is
  on `origin/main`.
- **[OWNER] License = MIT (2026-10-17).** Pyaww's own code (app, core,
  scripts, tooling) is MIT — `LICENSE` added at the repo root, copyright
  "Thein Kyaw Lwin" (owner may rename). Third-party attributions are
  unaffected (bundled model Apache-2.0 by freococo; mmdt-tokenizer port
  MIT by Myanmar Data Tech).
- **[OWNER] "Pyaww" name check done (2026-10-17).** Agent-run collision
  check, findings in `docs/evidence/name-check.md`: no active product with the
  name; the only exact-spelling software match is a dormant 2022 PyPI
  package unrelated to dictation; nearest live trademark is PAWW
  (class 009) — relevant only if Pyaww is ever released publicly. Name
  kept; `pyaww.com` happens to be unregistered.
- **Phase 4 close-out started (2026-10-17):** remaining Phase 4 items are
  the app icon, the README, and the Gate 4 clean-install rehearsal. Icon
  draft landed: `scripts/make-icon.swift` (AppKit renderer) +
  `scripts/make-icon.sh` (iconset → `Resources/AppIcon.icns`), wired into
  `App/Info.plist` (`CFBundleIconFile`) and `scripts/make-app.sh`; design =
  indigo→violet rounded square with the Burmese ပြော glyph (draft for
  owner review — regenerate after tweaks with one command).
- **[OWNER] Distribution plan: discussion open (2026-10-17).** Owner wants
  a back-and-forth (personal-only vs share with a few people vs public)
  before choosing; SPEC Phase 5 (Developer ID + notarization, CI) stays
  gated on that outcome and nothing there has been started.
- **[OWNER] Icon wave final locked — variant B (2026-10-17).** Owner chose
  B over their hand-scaled ribbon: the wide ribbon uniformly scaled 11/12
  about the centre — end-centres (160, 570.6667) → (864, 453.3333), apexes
  (394.6667, 394.6667) / (629.3333, 629.3333), cap tips exactly on the
  128/896 grid lines, tip distance 388.46 vs d820 ring radius 410, stroke
  64, round caps. A proportional scale is a similarity transform, so all
  feel-defining physics are unchanged (handle:chord = 0.500, zero-velocity
  turns on the diagonal, dead-centre crossing, point symmetry). The
  working file was cleaned to **Wave (final) + Apple's grid + the C4
  field** (trial ribbons deleted; pre-clean copy parked in the temp dir),
  and the layer SVGs were re-exported in final colours with Apple's
  template metadata stripped: `Design/icon-assets/1.background.svg` +
  `2.ribbon.svg`, mirrored into the refreshed `Design/Pyaww.icon`
  package. Measured from the file (not assumed): the C4 gradient runs
  **diagonally**, top-left `#4DA6F4` → bottom-right `#1461E0`
  (`x1,y1,x2,y2 = 0,0,1024,1024`, `userSpaceOnUse`). Owner does the Icon
  Composer glass pass next; then bake `Resources/AppIcon.icns`.
- **[OWNER] Final app icon delivered — icns baked (2026-10-17).** Owner
  finished the Icon Composer pass and exported six 1024 px appearances to
  `Design/Icon Exports/` (Default / Dark / TintedLight / TintedDark /
  ClearLight / ClearDark, Icon Composer's export naming). The Default
  export already carries the macOS squircle mask (corners verified
  transparent); it shows the white glass wave on the azure field with the
  soft shadow the Icon Composer pass added. `Resources/AppIcon.icns` is
  baked from it via `./scripts/make-icon.sh`, which was repointed at the
  export — the interim `scripts/make-icon.swift` glyph renderer was
  removed. The dark/clear/tinted variants stay in the repo as reference;
  embedding appearance variants would need actool, which this CLT-only
  machine lacks, so the shipping path is the legacy icns + system-drawn
  appearances. The source package lives at
  `Design/pyaww-icon-composer.icon` (Icon Composer automatic-gradient field
  from the ribbon blue + glass/refractivity ribbon settings); superseded
  lab drafts and the hand-made `Design/Pyaww.icon` package were removed
  from the repo (kept in git history).

## Phase 4 close-out continued (2026-10-17)

- **[OWNER] Menu bar icon: the wave replaces the mic (2026-10-17).** Owner
  asked Pyaww to learn from **vorssaint** (`~/Desktop/vorssaint-utils` —
  FOSS, Mac-native, menu bar; "they are like teacher for us") and to use a
  custom menu bar icon, and picked the recording colour: **red** ("red for
  recording is common"; brand azure noted as the branding-first
  alternative). Implementation (`App/MenuBarIcon.swift`): the app icon's
  wave "B" drawn at runtime as a vector — idle and transcribing are
  **template** images (macOS paints them black on light and white on dark
  menu bars), recording is a real red (`isTemplate = false`). Menu bar
  tuning: 18 pt canvas, 16 pt ink, stroke optically bolded from the icon's
  6.25% to ~9.7% of the ink width (1.75 pt). Loading keeps the hourglass,
  errors the triangle symbol. Agent addition beyond the agreed
  idle/recording pair: transcribing shows the wave at 45% alpha as a
  subtle "busy" hint (drop it on request). Vector drawing sidesteps the
  1x/2x PNG pairs vorssaint needs only because its glyph comes from a
  bitmap logo; the template/tint principles are theirs. Verified live in
  the real menu bar (red while recording 17:23, template white at idle
  17:24) and by 5 new tests — `swift test` is now 34 (17 core + 17 app).
  `MenuBarLabel` maps phase → icon; the retired `AppState.menuBarSymbol`
  is gone.
- **[OWNER] Distribution: free "Moji-style" route (2026-10-17).** No Apple
  Developer Program subscription ($99/yr declined). First public release:
  a DMG on GitHub Releases plus a README install section — Gatekeeper
  dialog text, System Settings → Privacy & Security → Open Anyway (macOS 15
  removed right-click-Open), and an `xattr -dr com.apple.quarantine`
  fallback — then microphone/accessibility setup. Homebrew deferred:
  Homebrew removed `--no-quarantine` (Sep 2025) and quarantined casks that
  fail Gatekeeper get disabled, so a cask would be fragile without
  notarization. No CI: releases published locally with `gh release create`.
  Versioning proposal (first release `v0.1.0`, keep-a-changelog, DMG
  `Pyaww-0.1.0-arm64.dmg`) awaits owner confirmation.
- **Installer window diagnosed + fixed (2026-10-17, after Gate 4).** The
  owner invited a second look at the styled DMG ("you may find some
  odds"). Measured findings (pixel probes on captures + parsing the
  volume's `.DS_Store`): (1) macOS 26's Finder races the styling
  AppleScript's `set bounds` — the first build lost the race and saved
  its default `{{289, 214}, {920, 464}}` frame, so the 600×400 picture
  sat in a 920-wide window; the uncovered icon-view area shows the
  default white background. (2) Icon-view items draw centred on their stored y; the first reading
  mis-attributed a "+45 pt below stored" offset to Finder (corrected
  2026-10-17; icons stored at y=200 simply sat 45 pt under the then
  design's arrow line at 200). (3) The saved frame's y is Quartz coordinates (from the screen
  bottom) — the reason position values look swapped. (4) macOS 26 keeps
  the Finder status bar despite the saved `ShowStatusBar=false` (kept —
  it reads as a deliberate footer) and gives the `/Applications` symlink
  Finder's standard alias badge (kept). (5) The `.background` folder is
  visible only when hidden files are shown (dev machines; vorssaint
  shares this — accepted). Fix: after the styling detach and before
  compression, `make-dmg.sh` re-attaches quietly and
  `scripts/patch-ds-store.py` same-length byte-patches the `.DS_Store`
  (window frame 600×400 with x=200 and the saved y kept; items stored at
  y=155 so they draw on the arrow line). Structural surprises fail the
  build. Verified on a fresh mount: 600×400 window, background fills it,
  icons on the arrow line. Testing note: this Mac caches per-volume view
  state, so re-mounting the same image for checks shows stale geometry —
  verify with a freshly built image (new volume UUID).
- **Icon rendering: diagnosed; owner keeps the full-bleed badge
  (2026-10-17, resolved).** Owner noticed the icon looks "not filled"
  with a light plate in the microphone permission list while
  OpenWhispr/Raycast/Recordly fill their slot; he also said the Icon
  Composer export should be full-bleed — re-measuring proved him right
  (and the previous note wrong): `Resources/AppIcon.icns` carries 100 %
  full-bleed art at every rep (from Icon Composer's "iOS Default"
  export), while every comparison app ships classic Mac canvas
  proportions (OpenWhispr 80 %, Recordly 81 %, Raycast 81–83 %,
  Portal 86–88 %). macOS 26 has two icon worlds: the new surfaces
  (Spotlight/launcher) render our art full size, matching Apple's new
  full-bleed icons (measured: our 122 px = Podcasts' 122 px), while the
  legacy renderer (Settings privacy lists) treats full-bleed art as
  iOS-style and re-seats it — art shrunk to ~70 % (28 px inside the
  40 px slot) on the default light Mac tile, which is the "border".
  Recordly (same icns-only setup with inset art) renders clean directly
  above us, isolating the cause to the full-bleed shape. **Owner
  decision: keep full-bleed** (big and native in the new UI; the
  Settings plate is accepted). The fully-modern fix (icon bundle/asset
  catalog) needs Xcode's icon compiler — no Xcode on this Mac.
- **DMG background: azure -> dark ink (owner request, 2026-10-17).**
  With the full-bleed blue badge the azure installer field read
  blue-on-blue ("color cannot distinguish and don't support each
  other"). `scripts/make-dmg-background.swift` now draws the badge's
  own top-left -> bottom-right diagonal in near-black navy
  (#161F38 -> #06080F) plus a soft azure radial glow (alpha 0.20,
  radius 110) behind the app icon slot so the badge pops and looks lit
  from its own field. White title/arrow/instructions unchanged.
  Verified on a fresh mount: chrome, content and the Finder status bar
  read as one dark surface with the blue icon as the brightest element.
- **Installer captions: light plates, not suppression (owner request,
  evening 2026-10-17).** Owner: the black "Pyaww"/"Applications" labels
  vanish on the dark field — "do white text". Established the rules
  first: Finder paints its own labels near-black over custom background
  pictures in **every** system appearance (light- and dark-mode captures
  agree) and offers no colour control. Suppression attempt —
  `textSize`/`axTextSize` (one shared bplist real) rewritten to 1 by the
  structural walker — failed on a test build: values outside Finder's
  10–16 range make it discard the **whole icvp view state** (flat
  default background, default icon size, stock white labels). Reverted:
  the default stays Finder's 13, the walker remains as a harmless
  structural check, `PYAWW_DS_TEXT_SIZE` stays for experiments only.
  "Bake a larger white copy so the black glyphs read as white outlines"
  was rendered with the real font and rejected (uneven fringes — text
  metrics never align exactly). Ship: the background bakes **light
  caption plates** (height 25.5 pt, radius 8, width = text + 20, white
  @ 94 %) at the exact label spots (glyph band bottom-origin 155.5–167
  pt), so Finder's own black labels sit on them; verified on a fresh
  mount (chip bbox matches the render, labels centred, no stray ink).
  `PYAWW_CAPTION_STYLE` selects chip (default) / outline / plain / none.
  Also corrected the icon-row rationale above: stored y draws the icon
  *centre* at that y (stored 155 → centre 154.5 measured), so the arrow
  and glow were raised from 200 to y=245 bottom-origin (= 155 pt from
  the top) to meet the icons rather than moving the items — revertible
  if the owner prefers the lower arrow.
- **[OWNER] Versioning confirmed; release kit landed (2026-10-17).** Owner
  approved the proposal ("yes proceed"): first public release **v0.1.0**
  ("pyaww v0.1.0 (beta)"), Keep-a-Changelog + SemVer,
  `Pyaww-0.1.0-arm64.dmg`. `scripts/make-dmg.sh` (hdiutil plus a
  vorssaint-derived Finder-window layout with retries and a cleanup trap)
  and `scripts/make-dmg-background.swift` (the badge's azure diagonal,
  600×400 pt rendered at 2×) produce the styled installer — verified by
  mounting: the volume carries the signed app, the `/Applications`
  symlink and a saved `.DS_Store` layout; 37 MB. `README.md` (install,
  permissions, usage, privacy, build, troubleshooting, uninstall) and
  `CHANGELOG.md` written. **Discovery (macOS 26):** opening a well-formed
  DMG now triggers the system's **"Install this app?"** one-click dialog
  (installs into the user's `~/Applications`, and offers to trash the
  download and eject); the README documents both that flow and classic
  drag-to-Applications. Remaining before publishing: the owner's
  clean-install rehearsal from the README alone (Gate 4) — Gatekeeper
  *Open Anyway* journey with a quarantined copy, fresh permission prompts
  (`tccutil reset` for that run), first transcription — then the publish
  go-ahead (`git push` + `gh release create v0.1.0`).

## Popover rework (2026-10-18)

- **[OWNER, approved 2026-10-18] The wave opens a full panel; the menu and
  the Settings window are retired.** "yes build it now" — one card-based
  popover (header; Permissions; Dictation; Pasting; Feedback; Model)
  replaces both surfaces; `MenuBarView`/`SettingsView`/`SettingsWindow`
  deleted and the `Settings` scene removed.
- **Hosted `NSPopover` on our own status item — the teacher's pattern,
  adopted after `MenuBarExtra` failed the owner's look test.** The first
  attempt (SwiftUI `MenuBarExtra(.window)`) pinned its plain square panel
  to the screen corner, with no API to centre or round it — owner:
  "teacher poppup at middle … ours is solid corner". The app entry is now
  AppKit (`NSApplicationDelegate` + `NSStatusItem` + `NSPopover`): macOS
  anchors the popover centred under the icon and draws the rounded
  container + arrow itself, and highlights the anchor while open. Both
  mouse buttons toggle; a same-click reopen after a transient close is
  guarded. (vorssaint `StatusItemController` as the reference.)
- **Quit lives in the panel footer, teacher-style.** A right-click
  `NSMenu` (with ⌘Q) was built and removed the same day — owner: "i don't
  like left click and right click to quit, teacher use". The footer is
  `pyaww v0.1.0` + the GitHub link + a quiet `⏻ Quit` button (flat fill,
  hairline border, icon + label), trimmed to the panel's control scale
  after the owner judged the first cut "little wide or big".
- **The header keeps one shape (owner question, 2026-10-18).** A single
  message line under "Pyaww": error > fresh notice (orange) > live
  status — every message short enough for one line, so the panel never
  changes height and nothing truncates.
- **Model card shows identity, not status.** "Speech model — Myanmar
  Conformer" (SPEC §1's own words) once ready, a spinner while loading;
  the word-segmentation row appears only when the lexicon is unavailable
  — a row that always said "Ready" was noise (the header already says it).
- **Over-window audio is clipped, not rejected (bug found by the owner's
  live test, 2026-10-18).** Holding past the 30 s limit let the tap's last
  buffer push the capture past the model's fixed window; `Transcriber`
  threw "audio is too long" — contradicting the notice's promise — and
  the raw message truncated in the header. `AppState` now clips to
  `Transcriber.maxSamples` before transcribing; regression test
  `overWindowRecordingIsClippedToModelWindow` added.
- **Footer GitHub link (owner request, 2026-10-18).** Opens
  `github.com/tklwin/pyaww` in the browser on click; the app itself still
  makes no network requests (SPEC §1 unchanged).

## Marketing site (2026-10-18)

- **[OWNER] Bilingual landing page, live at tklwin.github.io/pyaww/.**
  Hand-written static HTML/CSS/JS — no dependencies, no external
  requests, system fonts — living in `site/` in this repository and
  published by GitHub Pages (`.github/workflows/pages.yml`, path-filtered
  to `site/**`, so releases never redeploy it). The repository's homepage
  field points here; `docs/website.md` carries the maintenance rules.
- **Moved to this repo at the same URL.** First published from the
  personal site (`tklwin.github.io/static/pyaww/`), then moved so the
  page versions with the app: the project-site URL is exactly
  `tklwin.github.io/pyaww/`, so nothing changed for visitors. The old
  copy was removed only after the new one was verified live (the URL
  never went dark) and the personal site's "apps" nav link still
  resolves. Do not re-add `static/pyaww/` there.
- **Myanmar copy is owner-reviewed and now frozen.** Two passes: a full
  rewrite in a spoken register modelled on the Talk2Notion knowledge base
  (short sentences, `ပါတယ်/ပါ` endings, English technical terms kept
  English, honest "ဒါ ပုံမှန်ပါပဲ"-style friction notes), then the owner's
  exact replacements — the tagline
  "စာရိုက်နေစရာမလို၊ မြန်မာလိုပဲ ပြောလိုက်ပါ။", five feature-card titles in
  the owner's short-noun-phrase (`…ခြင်း`) style, and the "Ready at login"
  card body — integrated verbatim. Future `.my` changes need the owner's
  check before pushing.
- **No guide/help section (owner).** A guide (Quick start) was built and
  removed before any commit — owner: "we don't need guide actually… just
  don't add guide"; the page stays one landing page because "the app is
  so clean and easy to setup".
- **The red wave sits in a keycap tile like its neighbours (owner).**
  Step 2 of "How it works" first showed a floating red dot; the owner
  asked for a red wave "with button padding as others to match", so it
  now shares the keycap tile, border, gradient and padding with the ⌥
  and ↵ cards, drawn in `#ff453a` with a soft pulse (reduced-motion
  aware).
- **Wave geometry has one source of truth — `App/MenuBarIcon.swift`.**
  Hero, header mark, favicon and share card all draw the icon's "B" path
  (rises first: 570.6667 → 394.6667 → 629.3333 → 453.3333). An early page
  wave was horizontally mirrored; every copy was corrected and compared
  against the icon export. Never mirror it.
- **Assets are captures of the app itself (owner rule).** `panel.png` is
  the real panel; no personal screen content appears anywhere on the
  page. Icon exports come from `Design/Icon Exports/`; the 1200×630 share
  card is rendered from `docs/og-card.html` (self-contained). Its Myanmar
  line still carried the pre-approval tagline and was updated to the
  owner's tagline during the 2026-10-18 housekeeping pass, so card and
  hero now match.
- **Promo video: draft built, owner parked it.** A 19 s 1920×1080 H.264
  draft was rendered in EffectCraft; the owner stopped the direction
  ("just leave it video now") and no audio pass exists. Project + draft
  are preserved at `~/Movies/pyaww-promo/`; do not resume unless asked.
- **Dev-only `PYAWW_SHOW_PANEL` hook added then dropped.** It forced the
  panel visible for captures; the owner said drop it, the branch was
  reset to `origin/main`, and no release contains it.
