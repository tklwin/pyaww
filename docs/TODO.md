# Pyaww open TODOs

Items that block a phase gate or need owner action. Phase-internal task
lists live in the phase reports, not here.

## Recently closed (recorded in docs/decisions.md)

- ✅ **Gate 1 (2026-10-16):** Swift == Python on all 100 golden files
  (100/100 exact; CER delta +0.00 pp); one command `scripts/run-parity.sh`;
  feature tensors max|diff| 3.3e-05 ≤ 1e-3 budget.
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

- Phase 2: bundle `Models/` (mlpackage + JSON constants) as app resources;
  the first-launch `MLModel.compileModel` fallback + Application Support
  cache already exists and is exercised by the tests.
- Phase 3: profile per-clip latency from the Swift side (current CLI figure:
  ~0.6 s fixed process+load + ~0.3 s marginal per short clip on this M2) and
  re-measure compute-unit choice via the Swift `MLModel` API; the Python
  coremltools snapshot is indicative only.
- Phase 2+: `docs/manual-test-log.md` — manual app matrix results.
- Dev note: `myanmar_asr/` (Python reference checkout) was deleted after
  Gate 1, owner-approved. Re-clone
  `git clone https://huggingface.co/freococo/myanmar_asr myanmar_asr`
  before running `scripts/reconvert_coreml.py`, `scripts/export_fixtures.py`,
  or `scripts/parity_check.py`.
