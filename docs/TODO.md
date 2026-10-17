# Pyaww open TODOs

Items that block a phase gate or need owner action. Phase-internal task
lists live in the phase reports, not here.

## Recently closed (recorded in docs/decisions.md)

- ✅ **Gate 4 rehearsal (2026-10-17):** owner ticked all 8 steps in
  `docs/manual-test-log.md` — clean install from the README alone
  (Gatekeeper *Open Anyway*, fresh permission prompts, first dictation,
  red wave, README wording). Afterwards the installer window was
  diagnosed and fixed (macOS 26 Finder race: it opened 920×464 with
  white bands; now exactly 600×400 with icons on the arrow line — a
  build-time `.DS_Store` patch, `scripts/patch-ds-store.py`); artifact
  rebuilt and re-staged in `~/Downloads` (quarantined). Next: publish
  go-ahead.
- ✅ **Menu bar wave (2026-10-17):** custom icon shipped — the app icon's
  wave drawn at runtime (`App/MenuBarIcon.swift`); template idle plus
  transcribing, real red while recording (owner's call). Verified live in
  the menu bar; 5 new tests (suite now 34); vorssaint-learnings recorded.
- ✅ **Icon (2026-10-17):** final art shipped — owner's Icon Composer pass
  exported six 1024 px appearances to `Design/Icon Exports/`; the Default
  one is baked into `Resources/AppIcon.icns` by the now export-sourced
  `./scripts/make-icon.sh`. The interim glyph renderer
  (`scripts/make-icon.swift`) was removed. Design trail:
  `docs/decisions.md` (2026-10-17 icon entries).
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

- **Distribution: route chosen — free "Moji-style" (2026-10-17).** DMG on
  GitHub Releases + README "Open Anyway" steps + `xattr` fallback; no
  Apple Developer Program, no brew, no CI (`gh release create` locally).
  Versioning confirmed: first release `v0.1.0` ("pyaww v0.1.0 (beta)").
  Gate 4 rehearsal green (log ticked) and the installer window fixed.
  Next: the publish go-ahead (`git push origin main`, tag, release).
  SPEC Phase 5 notarization/CI stay optional.
- **Icon fill: question open (2026-10-17).** In System Settings lists our
  icon shows the Apple-grid transparent margin as a light plate (their
  reference apps ship full-canvas artwork). Owner to choose: keep the
  Apple proportions or re-bake `Resources/AppIcon.icns` edge-to-edge.

## Phase 4

- **Word segmentation — implemented + owner-verified (2026-10-17).**
  Swift port of `mmdt-tokenizer` 0.1.3 (MIT) with the approved adaptations;
  209/209 Python reference vectors exact; Settings toggle (default on);
  applied after transcription before the paste; `pyaww-cli --segment` /
  `--segment-text` for inspection (CLI default stays raw). Evidence:
  `docs/decisions.md` (Phase 4), `docs/performance.md` (cost).

- **Gate 4 close-out (2026-10-17):** `README.md`, `CHANGELOG.md` and the
  DMG kit (`scripts/make-dmg.sh`, `scripts/make-dmg-background.swift`,
  `scripts/patch-ds-store.py`) are in. Rehearsal green (log ticked) and
  the installer window fixed; remaining: the publish go-ahead
  (`git push` + `gh release create v0.1.0`).

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
