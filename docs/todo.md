# Pyaww open work

Open items only. History and reasons live in `decisions.md`; measurements
and test records in `evidence/`; the docs map in `README.md`.

## Next version

- **Scope not chosen (2026-10-18).** v0.1.0 is shipped. Pick `v0.1.1`
  (fixes only) or `v0.2.0` (features) before development resumes. The
  landing page versions independently — only pushes touching `site/**`
  redeploy it.
- **Model storage (decide before the next model bump).** The 37 MB
  `.mlpackage` is tracked in git; every new version would add ~37 MB to
  history forever. Choose Git LFS or a build-time download.
- **Test-only CI (recommended for v0.2).** A macOS workflow running
  `scripts/test.sh` on push/PR. Independent of Phase 5 notarization;
  does not change the free-distribution decision.
- **Phase 5 (optional, unchanged).** Developer ID signing/notarization,
  a release CI, and features from the non-goals list — only if the owner
  asks.

## Beta testing

- **Collect external reports** through GitHub Issues using
  `beta.md`; fill in its compatibility matrix as results arrive.
- **Triage rule:** first reproduce on the owner's Mac; link the issue to
  the decision/Fix commit when resolved.

## Parked

- **Promo video.** The 19 s draft did not pass the owner's look review
  ("just leave it video now"); no audio pass exists. Project + draft are
  preserved at `~/Movies/pyaww-promo/` with a README. Do not ship the
  draft; resume only if asked.
- **Website redesign.** Planned later; build it on a branch and keep
  `main` deployable.
- **`myanmar_asr/` reference checkout.** Deleted after Gate 1. Re-clone
  `git clone https://huggingface.co/freococo/myanmar_asr myanmar_asr`
  before running `scripts/reconvert_coreml.py`, `scripts/export_fixtures.py`
  or `scripts/parity_check.py`.

## Engineering notes

- `scripts/make-app.sh` builds release into `.build-release/` (separate
  scratch dir); mixing configurations in `.build` breaks Swift Testing
  plugin resolution on this CLT toolchain. `swift package clean` resets
  `.build` if it wedges.
- Keep `docs/evidence/` append-only; add a new log rather than editing an
  old one.
