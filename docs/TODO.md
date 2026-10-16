# Pyaww open TODOs

Items that block a phase gate or need owner action. Phase-internal task
lists live in the phase reports, not here.

## Recently closed (recorded in docs/decisions.md)

- ✅ **Gate 0 (2026-10-16):** `docs/model-spec.md` approved; w16 g2063
  tolerance accepted; JSON constants + mel_filters repair confirmed.
- ✅ **Binary handling (2026-10-16):** deployment asset + JSON constants
  tracked in git; 91 MB checkpoint and legacy 2 s asset stay out.

## Owner action

- **Name check for "Pyaww"** (GitHub / web / trademark search) before Phase 4.
- **Signing identity** for stable local signing (see decisions.md) — pick
  before Phase 4 so TCC grants don't reset.
- **License for Pyaww's own code** (the model itself is Apache-2.0): decide
  at Phase 4.

## Agent / engineering

- **Phase 1:** `Package.swift` with `PyawwCore` + `pyaww-cli`; build stage by
  stage (resample → features → model → decoder → tokenizer), each stage with
  a test against `Tests/Fixtures/intermediates/`.
- **Phase 1:** `scripts/run-parity.sh` — one-command golden-set parity + CER
  report (fixtures in place; g2063 tolerance approved).
- Phase 1: `FeatureExtractor` constants ship from `Models/*.json` (mel
  filters, Hann window, CMVN, vocab) — bundle loading path settled in Phase 2.
- Phase 3: re-measure compute-unit choice from Swift (MLModel API) with real
  audio; Python coremltools snapshots are indicative only.
- Phase 2+: `docs/manual-test-log.md` — manual app matrix results.
