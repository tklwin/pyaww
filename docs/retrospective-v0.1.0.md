# Retrospective — building v0.1.0

Written 2026-10-18, before v0.2 work. **Historical — do not update.**
It records how the beta was built and what we want to keep doing.

## Snapshot

- **48 commits over three calendar days** (2026-10-16 → 18): 42 up to the
  `v0.1.0` release, 6 afterwards. No merge commits.
- **v0.1.0:** 35 tests, 100 golden clips, ~30 ms median transcription,
  38 MB bundle, zero crashes over 100- and 300-dictation soaks.
- **Repo:** ~96 MB on GitHub — 37 MB model, 33 MB fixtures, the rest code,
  icons and history.
- **Shipped:** app DMG on GitHub Releases, bilingual landing page, docs.

## Timeline

- **Oct 16 — Phase 0:** inspected the model, wrote `model-spec.md`, built
  the parity tooling and the 100-clip golden set. **Phase 1:** Swift core
  and CLI reached exact parity; Gate 1 passed.
- **Oct 17 — Phase 2:** menu-bar app, permissions, paste, Gate 2 matrix.
  **Phase 3:** measurements and soaks, Gate 3. **Phase 4:** word
  segmentation, icon, menu-bar wave, installer, packaging, Gate 4.
  `v0.1.0` tagged and released.
- **Oct 18 —** panel rework (menu + Settings window → one popover), the
  30 s overrun fix, website launch and copy passes, docs sync, and this
  foundation baseline.

## What worked

- **Spec first, then gates.** Every phase had evidence and an owner check
  before the next one. Nothing was declared done from memory.
- **The decision log.** Most projects lose the “why” within a week; this
  one has it, including rejected options.
- **Owner in the loop on look and copy.** The panel, the icon and every
  Burmese string improved because the owner looked before shipping.
- **One-command evidence.** `scripts/test.sh` and `scripts/run-parity.sh`
  made “green” checkable; performance and manual logs were written as
  evidence, not as marketing.
- **Honest user-facing copy.** Gatekeeper friction, ignored short clips,
  secure-input limits — stated plainly.

## What was messy

- **The same fact lived in four places** (SPEC, TODO, decisions,
  architecture). On Oct 18 we found and fixed eight stale spots: bundle
  ID, build script name, UI description, publish status, og-card tagline,
  test count, and two docs lists. Duplication, not carelessness, caused
  it.
- **SPEC tried to be two documents** — the v1 contract and the current
  state. It is now frozen; current truth moved to architecture/README.
- **Docs were written late.** The website guide, beta guide and release
  runbook arrived after the code. Their absence showed up as repeated
  questions and re-discovery.
- **Late UI rework.** The menu and Settings window were retired one day
  before release in favour of the popover. The result is better; the
  rework cost a day and left stale references behind.
- **Temporary artifacts.** A dev-only panel hook was added and dropped; a
  promo video was built and parked; scratch assets lived in temp folders.
  All are now either removed or preserved with a note.

## Bugs that taught us

- **Core ML autorelease leak** — found by the 300-clip soak; fixed with a
  per-prediction `autoreleasepool`.
- **30 s overrun** — the last audio buffer could exceed the model window;
  audio is now clipped before transcription, not rejected.
- **Installer window race** — Finder could lay out the DMG at the wrong
  size; `patch-ds-store.py` makes the layout deterministic.
- **Mirrored wave** — the site drew the brand wave backwards; fixed
  everywhere by treating `App/MenuBarIcon.swift` as the only source.
- **Stale share card** — the og image kept the pre-approval tagline;
  copy changes must now sweep the page *and* the card.

## Rules for v0.2 and later

1. **One fact, one home.** Current behaviour → architecture/README; why →
   decisions; open work → todo; process → build-release/beta/website.
   Everywhere else links.
2. **Freeze history.** Historical docs (SPEC, evidence, this file) are not
   edited; supersede them.
3. **Owner-reviewed copy.** Any `.my` string change needs the owner's
   check and must update the page *and* the share card.
4. **Release runbook every time** — `build-release.md`; no release from
   memory.
5. **External reports go through Issues** with `beta.md`'s template, not
   chat messages.
6. **Add test-only CI** before accepting code contributions (independent
   of notarization).
7. **Decide model storage before the next model bump** — every version of
   the 37 MB asset stays in git history forever; LFS or a build-time
   download keeps clones sane.
8. **Protect the invariants** — bundle ID, signing identity, wave
   geometry, copy freeze.
9. **Do not ship parked work** just because it exists (the video).

## Open decisions

- Next version scope: `v0.1.1` (fixes) vs `v0.2.0` (features).
- Phase 5 (notarization/Developer ID): optional, not taken.
- Website redesign: later; keep `main` deployable while it is built.
