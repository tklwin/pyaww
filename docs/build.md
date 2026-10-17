# Building and running Pyaww

## Commands

| Artifact | Command | Notes |
| --- | --- | --- |
| Tests | `scripts/test.sh` (or plain `swift test`) | 34 tests: 17 core (`PyawwCoreTests`) + 17 app (`PyawwAppTests`: 12 state + 5 menu bar icon) |
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
   Accessibility and enable Pyaww. (The menu bar menu has buttons with the
   right deep links for both.)

Usage: **hold Right Option**, speak, release — the text is pasted at the
cursor. **Esc** cancels. The menu shows status, permission help,
Settings…, and Quit.

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
