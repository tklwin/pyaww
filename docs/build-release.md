# Building, testing and releasing Pyaww

## Commands

| Artifact | Command | Notes |
| --- | --- | --- |
| Tests | `scripts/test.sh` (or plain `swift test`) | 35 tests: 17 core (`PyawwCoreTests`) + 18 app (`PyawwAppTests`) |
| CLI (WAV in, text out) | `swift build && .build/debug/pyaww-cli --model-dir Models clip.wav` | any AVFoundation-readable file, 0.5–30 s |
| Menu bar app | `./scripts/make-app.sh` | release build → `build/Pyaww.app`, signed |
| Gate 1 parity | `scripts/run-parity.sh` | one command: build, golden-set run, compare, CER |

## Signing identity

`scripts/make-app.sh` signs with, in order of preference:

1. the first **Apple Development** identity in your keychain (owner decision
   2026-10-17 — stable across rebuilds),
2. a **"Pyaww Local"** self-signed certificate, or
3. ad-hoc signing (warns; macOS forgets Microphone/Accessibility grants
   after every rebuild in this mode).

To create the fallback certificate (only needed on machines without a
developer identity):

1. Open **Keychain Access** (Applications → Utilities).
2. Menu **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Fill in:
   - **Name:** `Pyaww Local`
   - **Identity Type:** _Self Signed Root_
   - **Certificate Type:** _Code Signing_
4. Click **Create**, then **Done**.
5. Verify: `security find-identity -v -p codesigning | grep "Pyaww Local"`

macOS ties Microphone/Accessibility (TCC) grants to the code signature;
switching identities (e.g. ad-hoc → Apple Development) asks for them once.

## Running

```
./scripts/make-app.sh
open build/Pyaww.app
```

First launch prompts:

1. **Microphone** — macOS asks; click Allow.
2. **Accessibility** — open System Settings → Privacy & Security →
   Accessibility and enable Pyaww. (The panel has buttons with the right
   deep links for both.)

Usage: **hold Right Option**, speak, release — the text is pasted at the
cursor. **Esc** cancels. Click the wave (left or right) for the panel:
permissions, hotkey, durations, word segmentation, clipboard restore,
sound cue, launch at login, model status, and Quit.

## Bundle layout

```
build/Pyaww.app/Contents/
  MacOS/PyawwApp           release binary
  Resources/Models/        BurmeseASR-Encoder-30s.mlpackage + 4 JSON constants (~38 MB)
  Resources/lexicons.json  word-segmentation lexicon (Phase 4; mmdt, MIT)
  Resources/Pyaww_PyawwCore.bundle/  SPM resource bundle (same lexicon)
  Info.plist               LSUIElement, com.tklwin.pyaww, microphone usage string
```

- No entitlements file, **no App Sandbox** (SPEC §6.8: required for the
  synthetic paste). Hardened runtime: off (local builds).
- First launch compiles the model into
  `~/Library/Application Support/Pyaww/CompiledModels`; safe to delete
  (it rebuilds on next launch).

## Why there is no Xcode project

This machine has Command Line Tools only: no `xcodebuild`, no Core ML
compiler, and no `SwiftUIMacros` plugin. Therefore:

- the app is an SPM executable target (`App/`) and the bundle is assembled
  by `scripts/make-app.sh`;
- the model compiles on first launch via `MLModel.compileModel`;
- the app avoids SwiftUI property-wrapper *macros* (`@State`, `@Entry`, …:
  `plugin for module 'SwiftUIMacros' not found`) and uses Observation
  (`@Observable`/`@Bindable`) — SwiftUI tracks observable reads in `body`
  directly; plain property wrappers such as `@Environment` compile fine
  (used for `\.openSettings`).

## Development notes

- Logs: `log stream --predicate 'subsystem == "com.tklwin.pyaww"'`
  (transcripts and audio are never logged).
- Release builds use their own scratch directory (`.build-release/`):
  mixing a release build into `.build` breaks Swift Testing's macro-plugin
  resolution for later `swift test` runs on this CLT toolchain.
- **"plugin for module 'TestingMacros' not found":** Swift Build's plan no
  longer passes the resolved `TestingMacros` plugin
  (`-load-resolved-plugin`), because the dylib lives in the `testing/`
  subdirectory of the toolchain plugin directory
  (`…/usr/lib/swift/host/plugins/testing/`), which the plan generator does
  not scan (observed 2026-10-17 — the old plan-cache workaround alone is no
  longer enough). `scripts/test.sh` deletes the cached plan (`.build/`
  `manifest.pif` + `XCBuildData`) **and** passes the plugin directories
  explicitly (`-Xswiftc -plugin-path …/host/plugins` and
  `…/host/plugins/testing`), derived from `xcrun --find swiftc`. Resolution
  at compiler level verified with a bare `swiftc -typecheck` of an
  `import Testing` file. If `.build` gets wedged despite both, `swift
  package clean` resets it.

## Releasing

Versioning is SemVer. Two places carry it:

- `App/Info.plist` → `CFBundleShortVersionString` — the public version
  (`0.1.0`), the tag name, and the release title.
- `App/Info.plist` → `CFBundleVersion` — a monotonically increasing build
  number (`1` today). Bump it for every uploaded build, even a rebuild of
  the same public version.
- `CHANGELOG.md` — the user-facing entry. Release notes are its matching
  section plus the short install blurb and the website link.

### Release checklist

1. **Start clean:** `git status` clean; `git pull`.
2. **Bump:** both version keys in `App/Info.plist`, plus `CHANGELOG.md`.
3. **Tests:** `./scripts/test.sh` — all 35 green.
4. **Parity** (only if the model or front-end changed):
   `./scripts/run-parity.sh`.
5. **Build:** `./scripts/make-app.sh`, then `./scripts/make-dmg.sh`
   (→ `dist/Pyaww-<version>-arm64.dmg`).
6. **Smoke-test the artifact as a user would:** copy the DMG to
   `~/Downloads` (quarantined), open it, install, launch through
   Gatekeeper, dictate once, then uninstall.
7. **Hash:** `shasum -a 256 dist/Pyaww-<version>-arm64.dmg`.
8. **Tag and publish:**

   ```sh
   git tag -a v<version> -m "pyaww v<version> (beta)"
   git push origin main
   git push origin v<version>
   gh release create v<version> dist/Pyaww-<version>-arm64.dmg \
       --title "pyaww v<version>" --notes-file <release-notes.md>
   ```

9. **Afterwards:** confirm the release's `latest` URL works, the README
   still points to it, and the website install steps still match. The site
   redeploys only when `site/**` changes — releasing the app does not
   touch it.

Do **not** commit `dist/` (gitignored). Do **not** change the signing
identity between builds: macOS resets the Microphone and Accessibility
grants when it changes. Never replace an uploaded artifact under the same
public version — bump `CFBundleVersion` and rebuild.

On macOS 26 the styling step's AppleScript `set bounds` can lose a race
with Finder and the saved window ends up larger than the 600×400
background. `make-dmg.sh` therefore re-attaches the image quietly (no
Finder) after styling and `scripts/patch-ds-store.py` byte-patches the
saved `.DS_Store` (window 600×400, item row on the arrow line) before
compression. If the patcher prints an `✗`, it failed on purpose — do not
ship that image.

Distribution is intentionally not notarized (free project, no Apple
Developer Program subscription) — `README.md`'s install section is the
user-facing side of that decision. Beta reports are handled per
`beta.md`.
