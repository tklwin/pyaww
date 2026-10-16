# Pyaww open TODOs

Items that block a phase gate or need owner action. Phase-internal task
lists live in the phase reports, not here.

## Owner action

- **Gate 0 sign-off (Phase 0 complete):**
  - **Approve `docs/model-spec.md`** (encoder-only 30 s contract). Gate 0
    requires owner review.
  - **[Parity tolerance]** The shipped `w16` Core ML asset reproduces the
    Python reference exactly on **100/101** fixture files. The one miss
    (`g2063.wav`, 10.4 s) is a single-token near-tie: the fp32 reference's
    own top-1/top-2 margin at the flipped frame is 0.0122 vs the model's
    0.0119 local diff. SPEC §5.3 allows a **documented, owner-approved
    tolerance** — approve it, or choose the exact-but-larger `fp32` asset
    (77.8 MB, exceeds the 60 MB bundle target) via
    `scripts/reconvert_coreml.py --precision fp32`.
  - **[mel_filters.json]** Confirm the repair: the file previously in
    `Models/` was Slaney-normalized and did not match the reference front-end;
    it has been regenerated reference-correct and the old content preserved as
    `Models/mel_filters.slaney.json` (see decisions.md).
  - **[I-8 format]** Mel filterbank + Hann window were exported as JSON to
    match your existing `cmvn.json`/`vocab.json` convention (spec suggested
    `.bin`/`.npy`). Confirm, or ask for `.bin`/`.npy`.
- **Binary handling for `Models/` and `myanmar_asr/`:** both are still
  untracked in git (working tree is the source of truth). Recommendation:
  commit the small JSON constants + the `w16` `.mlpackage` (39 MB) and keep
  the 91 MB checkpoint / 38 MB legacy assets out of git (or via LFS) — your
  call. `Models/**/*.mlmodelc` stays ignored.
- **Name check for "Pyaww"** (GitHub / web / trademark search) before Phase 4.
- **Signing identity** for stable local signing (see decisions.md) — pick
  before Phase 4 so TCC grants don't reset.
- **License for Pyaww's own code** (the model itself is Apache-2.0): decide
  at Phase 4.

## Agent / engineering

- Phase 1: create `Package.swift` with `PyawwCore` + `pyaww-cli` targets and
  stage-parity tests against the exported Python tensors
  (`Tests/Fixtures/intermediates/`).
- Phase 1: `scripts/run-parity.sh` — one-command golden-set parity + CER
  report (fixtures are in place; expects the g2063 tolerance decision).
- Phase 1: `FeatureExtractor` constants ship from `Models/*.json` (mel
  filters, Hann window, CMVN, vocab) — loading path TBD with the app bundle
  in Phase 2.
- Phase 3: re-measure compute-unit choice from Swift (MLModel API) with real
  audio; the Python coremltools snapshots are indicative only.
- Phase 2+: `docs/manual-test-log.md` — manual app matrix results.
