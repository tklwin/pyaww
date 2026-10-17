# Pyaww open TODOs

Items that block a phase gate or need owner action. Phase-internal task
lists live in the phase reports, not here.

## Recently closed (recorded in docs/decisions.md)

- ✅ **Settings window fronting (2026-10-17):** owner confirmed the window
  comes to the front on the first click; fix `a97c499` pushed.
- ✅ **Gate 3 (2026-10-17):** owner reviewed `docs/performance.md`
  (resident memory = Activity Monitor footprint, 77–88 MB idle) and ticked
  the Phase 3 re-verify table; the Phase 4 word-segmentation table is ticked
  too (word text vs raw toggle verified in-app). Push approved and done.
- ✅ **Gate 2 (2026-10-17):** owner manual matrix green — paste + clipboard
  restore in Notes/Safari/Chrome/VS Code/Terminal/Messages/Telegram; FR-1…10
  ✅. Log: `docs/manual-test-log.md`.
- ✅ **Phase 2 build (2026-10-17):** menu bar app implemented; `swift test`
  20/20 (11 core + 9 app state); `./scripts/make-app.sh` produces a 38 MB
  `build/Pyaww.app`.
- ✅ **Gate 1 (2026-10-16):** Swift == Python on all 100 golden files
  (100/100 exact; CER delta +0.00 pp); one command `scripts/run-parity.sh`;
  feature tensors max|diff| 3.3e-05 ≤ 1e-3 budget.
- ✅ **Gate 0 (2026-10-16):** `docs/model-spec.md` approved; w16 g2063
  tolerance accepted; JSON constants + mel_filters repair confirmed.
- ✅ **Binary handling (2026-10-16):** deployment asset + JSON constants
  tracked in git; 91 MB checkpoint and legacy 2 s asset stay out.

## Owner action

- **Name check for "Pyaww"** (GitHub / web / trademark search) before Phase 4.
- **License for Pyaww's own code** (the model itself is Apache-2.0): decide
  at Phase 4.

## Phase 4

- **Word segmentation — implemented + owner-verified (2026-10-17).**
  Swift port of `mmdt-tokenizer` 0.1.3 (MIT) with the approved adaptations;
  209/209 Python reference vectors exact; Settings toggle (default on);
  applied after transcription before the paste; `pyaww-cli --segment` /
  `--segment-text` for inspection (CLI default stays raw). Evidence:
  `docs/decisions.md` (Phase 4), `docs/performance.md` (cost).

## Agent / engineering

- **Phase 3:** closed — owner Gate 3 passed 2026-10-17 (measurements in
  `docs/performance.md`; re-verify table ticked). Keep
  `docs/manual-test-log.md` updated for later re-runs.
- Dev note: `myanmar_asr/` (Python reference checkout) was deleted after
  Gate 1, owner-approved. Re-clone
  `git clone https://huggingface.co/freococo/myanmar_asr myanmar_asr`
  before running `scripts/reconvert_coreml.py`, `scripts/export_fixtures.py`,
  or `scripts/parity_check.py`.
- Dev note: `scripts/make-app.sh` builds release into `.build-release/`
  (separate scratch dir) — mixing configurations in `.build` breaks Swift
  Testing plugin resolution on this CLT toolchain; `swift package clean`
  resets `.build` if it ever gets wedged.
