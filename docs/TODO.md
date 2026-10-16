# Pyaww open TODOs

Items that block a phase gate or need owner action. Phase-internal task
lists live in the phase reports, not here.

## Owner action

- **I-7 Golden test WAVs:** provide ≥50 clips (target 100) with
  ground-truth Burmese transcripts. See the Phase-0 report for the exact
  checklist (short/long utterances, numbers, names, noisy rooms, multiple
  speakers, held-out subset). Blocks: Gate 0 completion, Gate 1 parity run.
- **I-9 Maximum audio length:** the shipped Core ML asset is fixed at
  exactly 2.00 s (32000 samples). Decide: keep 2 s, or re-convert from the
  untouched checkpoint to a longer fixed input (Deciding factor: usable
  dictation length; the app must never feed out-of-range audio).
- **Bundle ID** (`com.yourname.pyaww` placeholder in SPEC.md): provide the
  real reverse-domain prefix. It is set once in Phase 2 and never changed,
  because macOS ties Microphone/Accessibility grants to it.
- **Name check for "Pyaww"** (GitHub / web / trademark search) must be done
  by the owner before Phase 4.
- **Signing identity** for stable local signing (see decisions.md) — pick
  before Phase 4 so TCC grants don't reset.
- **License for Pyaww's own code** (the model itself is Apache-2.0): to
  decide at Phase 4.

## Agent / engineering

- Phase 1: create `Package.swift` with `PyawwCore` + `pyaww-cli` targets
  and stage-parity tests against the exported Python tensors.
- Phase 1: `scripts/run-parity.sh` — one-command golden-set parity + CER
  report (blocked on I-7 golden WAVs until then).
- Phase 2+: `docs/manual-test-log.md` — manual app matrix results.
- Phase 3: re-measure compute-unit choice from Swift (MLModel API) with
  real audio; the Python coremltools snapshot is indicative only.
