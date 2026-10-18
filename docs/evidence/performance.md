# Phase 3 — performance and robustness (measured 2026-10-17)

All numbers measured on the owner's Mac (MacBook Air M2, 15", 8 GB,
macOS 27.0.1) with the **release** build and the compiled-model cache warm
(normal daily-use state). This file is the evidence for Gate 3 (SPEC §5.2).

## Results vs targets

| Metric | Target | Measured | Status |
| --- | --- | --- | --- |
| Transcription latency, 5 s clip, after warm-up | < 300 ms | **~30 ms** (per-clip p50 27.5–32.7 ms; 300-run mixed soak p50 29.6 ms, max 40.4 ms) | ✅ ~10× margin |
| Cold start to ready | < 2 s | **0.57 s** in-app (exec → "model ready" ≈ 0.61 s, unified log) | ✅ |
| Idle CPU | ~0 % | **0.0 %** (top, 4 × 1 s samples, warmed app) | ✅ |
| Resident memory, idle | < 150 MB | **77–88 MB** footprint (Activity Monitor "Memory" / top MEM); RSS 175–187 MB incl. shared framework pages | ✅ * |
| App bundle size | < 60 MB | **38 MB** | ✅ |
| Crashes in 100 consecutive dictations | 0 | **0** (100- and 300-iteration soaks + manual sessions) | ✅ |

\* "Resident memory" is read as the number Activity Monitor shows
(`phys_footprint`). If read strictly as RSS (`ps -o rss`), idle is
175–187 MB and the target would need revision — flagged to the owner in the
Gate 3 report.

The mic path adds ~1 ms of resampling on top of the ~30 ms inference
(48 kHz stereo 5 s clip → 16 kHz mono: decode + downmix + resample 2.1 ms
vs 1.4 ms for the native 16 kHz file), so key-release → paste stays far
below 300 ms.

## Method (how to reproduce)

Harness: `pyaww-cli --bench N [--compute-units cpuOnly|cpuAndNeuralEngine|all] FILE...`
runs the exact app pipeline (`Transcriber.transcribe(samples:)` on 16 kHz
mono samples) with the same post-load 1 s-silence warm-up the app performs.
It prints TSV rows `iter / file / ms / chars / footprint_mb` (`#` lines are
metadata and summary). A soak is `--bench 100` over a rotating mix of clips.

```sh
swift build -c release --product pyaww-cli --scratch-path .build-release
.build-release/release/pyaww-cli --model-dir Models --compute-units all --bench 100 \
  Tests/Fixtures/audio/g0007.wav Tests/Fixtures/audio/g1049.wav \
  Tests/Fixtures/audio/g2069.wav Tests/Fixtures/audio/g3088.wav
```

Memory = `phys_footprint` (task_vm_info) sampled per iteration, plus peak
RSS (getrusage).

## Compute-unit benchmark (SPEC 6.1: benchmark, do not assume)

`g1049.wav` (4.95 s = the SPEC's "5 s clip"), 8 iterations each, release build:

| compute units | load ms | p50 ms | p90 ms | max ms | footprint start→end | peak RSS |
| --- | --- | --- | --- | --- | --- | --- |
| **all** | 1215 | **27.5** | 28.0 | 28.0 | 91 → 125 MB | 163 MB |
| cpuOnly | 642 | 58.5 | 69.9 | 69.9 | 43 → 76 MB | 137 MB |
| cpuAndNeuralEngine | 1591 | 82.0 | 96.3 | 96.3 | 64 → 97 MB | 407 MB |

**Decision: keep `.all`** — measured 2.1× faster than cpuOnly and 3.0×
faster than cpuAndNeuralEngine (the SPEC's suggested starting point). The
app default is therefore unchanged. Load-ms differences between runs are
first-touch/cache noise (later runs measured 261–309 ms); the authoritative
cold-start figure is the app measurement below.

## Soak tests (100 / 300 consecutive dictations)

Mix per round: 1.12 s, 4.95 s, 10.08 s and 26.04 s clips. The encoder is
fixed-30 s, so inference is constant-cost per clip (per-file means
29.6–34.3 ms).

| Run | Latency p50 / p90 / max | Footprint start → end | Peak RSS |
| --- | --- | --- | --- |
| 100 × before memory fix | 30.9 / 34.7 / 36.3 ms | 98.8 → **572.2 MB** (≈ +4.7 MB/clip) | 595.5 MB |
| 100 × after memory fix | 32.7 / 48.9 / 102.5 ms | 96.9 → 117.6 MB | 132.6 MB |
| 300 × after memory fix | 29.6 / 33.4 / 40.4 ms | 96.4 → 111.0 MB; plateau ~107.5 MB from iteration ~50 (held flat 107.4 → 107.6 MB for the next 200 iterations) | 134.6 MB |

The pre-fix growth was a real bug caught by this soak: Core ML creates
autoreleased Objective-C objects (feature values, internal buffers) per
`MLModel.prediction`, and the actor executor has no run-loop drain, so they
accumulated. Fixed with an explicit `autoreleasepool` around each prediction
(`Sources/PyawwCore/ModelRunner.swift`). Text output after the fix is
unchanged: **parity re-run = 100/100 exact** (CER delta +0.00 pp), tests
20/20.

## Profiling (hot spots)

`sample <bench-pid> 8` during a 600-iteration run: wall time is dominated by
threads **waiting on Core ML background execution** (workq/mach_msg traps);
the top frame in Pyaww's own code is `ModelRunner.floats(from:frames:vocab:)`
— the fp16→fp32 readback of the full 751 × vocab logits matrix (≈ 22 MB per
call), even though a 5 s clip decodes only the first ~40 rows.

No optimization applied: targets are met with ~10× margin and the decode
path is parity-critical. Candidate for a later phase (only if ever needed):
read back only the needed row range and reuse preallocated input arrays
(SPEC 6.1 "where practical").

## App-level measurements (final signed bundle)

- Cold start: `model ready after 573 ms` (in-app, AppModel init → ready);
  exec → ready ≈ **0.61 s** (unified log timestamps). `log show` returns an
  empty store on this Mac, so this was measured via `log stream` through a PTY.
- Idle after warm-up: CPU 0.0 %, footprint 77–88 MB (top MEM / Activity
  Monitor "Memory"), RSS 175–187 MB (`ps -o rss=`, shared pages included).
- Bundle: `du -sh build/Pyaww.app` = 38 MB.

## Phase 4 addendum — word-segmentation cost (measured 2026-10-17)

- `pyaww-cli --segment-text` (release build): segmenter **init 19.3 ms**
  (lexicon load + regex compile, once at app startup); segmenting the
  longest corpus text (~350 chars) **3.8 ms**. Per-dictation cost is
  negligible next to the ~30 ms model call; no SPEC §5.2 target changes.
- Fidelity: 209/209 exact vs the Python reference vectors; idempotent;
  only upstream's documented special characters are ever removed
  (`swift test` → SegmentationTests).

## Notes / limitations

- App-level measurements are on the owner's machine; latency numbers are
  in-process (exactly the pipeline the app calls), with the mic-path
  resample benchmarked separately (+~1 ms).
- The 100-dictation crash target is evidenced by automated pipeline soaks
  (300 consecutive transcriptions, zero crashes) plus the owner's manual
  sessions — the app UI with a real microphone cannot be driven headlessly.
