# Changelog

All notable changes to Pyaww are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Project website: a bilingual (English / မြန်မာ) landing page at
  <https://tklwin.github.io/pyaww/>, written by hand and published from
  `site/` by GitHub Pages; the social card carries the same tagline

## [0.1.0] - 2026-10-18

First public beta: hold a modifier key, speak Myanmar, release — the text
is pasted into the app you're using. Everything runs on your Mac.

### Added

- Menu-bar dictation with a hold-to-talk hotkey (Right Option by default,
  Right Command optional) and Esc to cancel
- Fully offline speech recognition — Core ML conversion of freococo's
  Myanmar ASR model, 30 s window, audio never leaves the Mac
- Myanmar word segmentation after transcription (mmdt-tokenizer rules,
  on by default, switchable off to paste the raw model text)
- Menu-bar wave: follows the menu bar appearance when idle, red while
  recording
- One panel behind the menu-bar wave: permission status, the hotkey,
  minimum/maximum recording durations, word segmentation, clipboard
  restore, sound cue, launch at login, model status, Quit, and a
  GitHub link
- Clipboard-safe pasting: the previous clipboard contents are restored
  afterwards (on by default)
- App and DMG build scripts (`scripts/make-app.sh`, `scripts/make-dmg.sh`
  with a styled installer window); no third-party runtime dependencies
- MIT license with third-party attributions (ASR model Apache-2.0 by
  freococo; segmentation rules MIT by Myanmar Data Tech)

### Fixed

- A recording that ran to the 30 s limit could fail to transcribe
  instead of using the captured audio (the tap's final buffer pushed
  the capture past the model's fixed window); it is now clipped to the
  window
