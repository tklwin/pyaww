# Pyaww open TODOs

Items that block a phase gate or need owner action. Phase-internal task
lists live in the phase reports, not here.

## Recently closed (recorded in docs/decisions.md)

- ✅ **License + name check (2026-10-17):** owner chose **MIT** for Pyaww's
  own code (`LICENSE` added); agent ran the "Pyaww" collision check — no
  blocking conflicts, name kept (`docs/name-check.md`).
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

- **Distribution plan** (personal-only vs sharing with others): discussion
  open (2026-10-17) — owner wants a back-and-forth before deciding; SPEC
  Phase 5 (Developer ID + notarization) stays gated on the outcome.
- **Icon — final wave locked, layer SVGs exported (2026-10-17):** owner
  picked **B** — the wide ribbon uniformly scaled 11/12: cap tips sit
  exactly on the 128/896 grid lines (tip distance 388.46 < d820 ring
  radius 410), stroke 64, round caps, apexes on the diagonal,
  dead-centre crossing, point-symmetric. Measured from the file itself:
  the Apple template is an **8×8 grid at 128 px** (lines at 128…896) with
  keyline circles **d820 / d512 / d204**; the C4 anchor blue `#4DA6F4` is
  literally Apple's demo-bead blue. The working file
  `Design/Pyaww-Icon-Template.vectorcraft` (local-only, gitignored —
  Apple content) is now cleaned to just **Wave (final) + Apple's grid +
  the C4 field** (the three trial ribbons were deleted; pre-clean backup
  kept in the temp dir). Final layer SVGs re-exported in C4 with Apple
  metadata stripped: `Design/icon-assets/1.background.svg` (field —
  gradient runs **diagonally**, top-left `#4DA6F4` → bottom-right
  `#1461E0`) and `Design/icon-assets/2.ribbon.svg` (the wave, white
  `#FFFFFF`, stroke 64 on the 1024 canvas). `Design/Pyaww.icon` package
  refreshed alongside. Next: owner's Icon Composer glass pass → export
  all icon variations → bake `Resources/AppIcon.icns` (replaces the
  interim `./scripts/make-icon.sh` icns). Comparison sheets
  `Design/template-snap-*.png` are local-only (Apple template content).

## Phase 4

- **Word segmentation — implemented + owner-verified (2026-10-17).**
  Swift port of `mmdt-tokenizer` 0.1.3 (MIT) with the approved adaptations;
  209/209 Python reference vectors exact; Settings toggle (default on);
  applied after transcription before the paste; `pyaww-cli --segment` /
  `--segment-text` for inspection (CLI default stays raw). Evidence:
  `docs/decisions.md` (Phase 4), `docs/performance.md` (cost).

- **Remaining for Gate 4 (2026-10-17):** README (build / install /
  permissions / troubleshooting) + clean-install rehearsal from the README
  alone. Icon: final art locked; owner's Icon Composer pass in progress
  (see Owner action).

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
