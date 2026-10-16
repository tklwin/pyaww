# Pyaww open TODOs

Items that block a phase gate or need owner action. Phase-internal task
lists live in the phase reports, not here.

## Recently closed (recorded in docs/decisions.md)

- ✅ **Phase 2 build (2026-10-17):** menu bar app implemented; `swift test`
  20/20 (11 core + 9 app state); `./scripts/make-app.sh` produces a 38 MB
  `build/Pyaww.app`; manual Gate 2 matrix pending (owner).
- ✅ **Gate 1 (2026-10-16):** Swift == Python on all 100 golden files
  (100/100 exact; CER delta +0.00 pp); one command `scripts/run-parity.sh`;
  feature tensors max|diff| 3.3e-05 ≤ 1e-3 budget.
- ✅ **Gate 0 (2026-10-16):** `docs/model-spec.md` approved; w16 g2063
  tolerance accepted; JSON constants + mel_filters repair confirmed.
- ✅ **Binary handling (2026-10-16):** deployment asset + JSON constants
  tracked in git; 91 MB checkpoint and legacy 2 s asset stay out.

## Owner action

- **Create the "Pyaww Local" certificate** (one-time, ~5 clicks; guide in
  `docs/build.md`) **before granting Microphone/Accessibility the first
  time** — the grants stick to the signature; ad-hoc rebuilds reset them.
- **Gate 2:** run the manual matrix in `docs/manual-test-log.md`
  (Notes, Safari, Chrome, VS Code, Terminal, Messages/Telegram + FR
  checklist) and report results.
- **Name check for "Pyaww"** (GitHub / web / trademark search) before Phase 4.
- **License for Pyaww's own code** (the model itself is Apache-2.0): decide
  at Phase 4.

## Agent / engineering

- Phase 3: profile per-clip latency from the Swift side (current CLI figure:
  ~0.6 s fixed process+load + ~0.3 s marginal per short clip on this M2) and
  re-measure compute-unit choice via the Swift `MLModel` API; the Python
  coremltools snapshot is indicative only.
- Phase 2+: keep `docs/manual-test-log.md` updated for later re-runs.
- Dev note: `myanmar_asr/` (Python reference checkout) was deleted after
  Gate 1, owner-approved. Re-clone
  `git clone https://huggingface.co/freococo/myanmar_asr myanmar_asr`
  before running `scripts/reconvert_coreml.py`, `scripts/export_fixtures.py`,
  or `scripts/parity_check.py`.
- Dev note: `scripts/make-app.sh` builds release into `.build-release/`
  (separate scratch dir) — mixing configurations in `.build` breaks Swift
  Testing plugin resolution on this CLT toolchain; `swift package clean`
  resets `.build` if it ever gets wedged.
