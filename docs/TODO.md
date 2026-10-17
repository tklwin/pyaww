# Pyaww open TODOs

Items that block a phase gate or need owner action. Phase-internal task
lists live in the phase reports, not here.

## Recently closed (recorded in docs/decisions.md)

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

- **One-time permission re-grant (signing switch):** the rebuilt app is now
  signed with the Apple Development certificate, so macOS asks once more.
  Launch `build/Pyaww.app` and work through the "Phase 3 re-verify" table in
  `docs/manual-test-log.md` (microphone → Accessibility → one dictation).
- **Gate 3 approval:** review the numbers in `docs/performance.md`
  (proposal: "resident memory" = Activity Monitor footprint, 77–88 MB idle;
  strict RSS is 175–187 MB). Say "Gate 3 passed" once you agree.
- **Push:** Phase 2 + Phase 3 commits are local only — say the word to
  `git push origin main`.
- **Name check for "Pyaww"** (GitHub / web / trademark search) before Phase 4.
- **License for Pyaww's own code** (the model itself is Apache-2.0): decide
  at Phase 4.

## Parking lot (awaiting owner decision)

- **Word-segmentation post-processing (`mmdt-tokenizer`, MIT).** Evaluated
  2026-10-17 in a temp venv (Python package stays out of the repo): rule-based
  grammar pipeline, no statistical model; ~1.1k lines + one 162 KB lexicon
  JSON → Swift-portable. Measured on our 99 word-spaced gold clips (boundary
  F1 vs human gold): model raw output 0.27 → `mmdt(despace(model))` 0.33
  (64 clips better / 31 worse / 4 equal); intrinsic ceiling vs this gold
  ≈ 0.43. 0/100 clips had any non-space character changed; ~0.4–0.8 ms per
  clip. Caveats: needs a Burmese-only de-space step first (lexicon matching
  cannot cross spaces); upstream drops `၊` when present and space-separates
  `။` (both fixable in a port; today's model output contains neither).
  SPEC hook already exists: `TextPostProcessor.swift` ("owner specifies
  rules"). Awaiting owner: goal, style preference, go/no-go.

## Agent / engineering

- **Phase 3:** measurements complete (SPEC §5.2 targets, compute-unit
  benchmark, 100/300-iteration soaks, memory-trend check, `sample`
  profiling; memory-growth bug found and fixed). Evidence:
  `docs/performance.md`. Awaiting owner Gate 3.
- Phase 3+: keep `docs/manual-test-log.md` updated for later re-runs.
- Dev note: `myanmar_asr/` (Python reference checkout) was deleted after
  Gate 1, owner-approved. Re-clone
  `git clone https://huggingface.co/freococo/myanmar_asr myanmar_asr`
  before running `scripts/reconvert_coreml.py`, `scripts/export_fixtures.py`,
  or `scripts/parity_check.py`.
- Dev note: `scripts/make-app.sh` builds release into `.build-release/`
  (separate scratch dir) — mixing configurations in `.build` breaks Swift
  Testing plugin resolution on this CLT toolchain; `swift package clean`
  resets `.build` if it ever gets wedged.
