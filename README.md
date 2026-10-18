<p align="center">
  <img src="Design/Icon%20Exports/Icon-iOS-Default-1024@1x.png" width="128" alt="The Pyaww app icon: a white wave on an azure field">
</p>

# Pyaww (ပြော)

**Menu-bar dictation for Myanmar.** Hold a key, speak, release — your words
are pasted into whatever app you're using. Everything runs **locally on
your Mac**: no accounts, no network, and your audio never leaves the
computer.

## Requirements

- macOS 14 (Sonoma) or later
- Apple silicon (M1 or newer)

## Install

1. Download the latest `Pyaww-…-arm64.dmg` from
   [Releases](https://github.com/tklwin/pyaww/releases/latest).
2. Open the disk image and install the app:
   - **macOS 15 and later** shows an **Install this app?** dialog — click
     **Install** (Pyaww goes into your own Applications folder); or
   - drag **Pyaww** onto the **Applications** shortcut in the window
     yourself (use `/Applications` if you want it for every user — both
     places work).
3. The first launch is blocked by Gatekeeper, because Pyaww is a free,
   non-notarized app ("Apple could not verify …"). Allow it once: open
   **System Settings → Privacy & Security**, scroll to **Security**, click
   **Open Anyway** next to the Pyaww message, and confirm. (On macOS 14 you
   can instead right-click the app and choose **Open**; macOS 15 removed
   that shortcut, so the Settings route always works.)
4. Launch Pyaww and grant the permissions as they're prompted — see below.

If macOS still refuses (for example a stale "app is damaged" message):

```sh
xattr -dr com.apple.quarantine "/Applications/Pyaww.app"
```

Use your actual install path — `~/Applications/Pyaww.app` if the install
dialog put it there.

## Permissions

Pyaww asks for two permissions, only when they're first needed. Both can
also be opened from the panel — click the wave in the menu bar.

| Permission | Why | Where |
| --- | --- | --- |
| **Microphone** | record your voice (prompted on first recording) | System Settings → Privacy & Security → Microphone |
| **Accessibility** | hear the push-to-talk key system-wide and paste the text | System Settings → Privacy & Security → Accessibility |

## Using Pyaww

- **Hold Right Option (⌥)** and speak — or switch to Right Command (⌘) in
  the panel. Release the key to transcribe and paste.
- **Esc** cancels a recording (or abandons a transcription in progress).
- Recordings shorter than the minimum (0.3 s by default) are ignored, and
  so are silent ones.
- Long recordings stop themselves at the maximum (30 s by default) and are
  still transcribed.
- The menu bar wave follows the menu bar appearance when idle and turns
  **red while recording**.
- **Click the wave** to open the panel: permission status, the
  push-to-talk key, minimum/maximum durations, Myanmar word segmentation
  (on by default — it joins the model's syllable spacing into natural
  words), clipboard restore, a recording sound cue, launch at login,
  model status, and Quit.

## Privacy

- Fully offline: the speech model is bundled inside the app and nothing is
  sent anywhere.
- No analytics, no accounts, no update checks.
- Text is pasted via the clipboard; Pyaww restores your previous clipboard
  contents afterwards (on by default).

## Build from source

Requires the Xcode Command Line Tools — a full Xcode is not needed.

```sh
./scripts/test.sh       # 35 tests (core + app)
./scripts/make-app.sh   # → build/Pyaww.app
./scripts/make-dmg.sh   # → dist/Pyaww-<version>-arm64.dmg
```

## Troubleshooting

- **The app opens but there is no window** — correct: Pyaww is a menu-bar
  app with no Dock icon. Look for the wave at the right end of the menu
  bar (left of the system status icons).
- **Nothing happens when I hold the key** — grant Accessibility (above);
  the global key listener needs it.
- **"Pyaww is damaged" / it won't open at all** — apply the Gatekeeper
  allow step, or the `xattr` command; keep the app in Applications.
- **No text is pasted** — focus a text field first; some sandboxed or
  terminal apps handle synthetic pastes differently. The transcript is
  also briefly on your clipboard, so ⌘V works as a fallback.
- **I spoke but nothing happened** — recordings under the minimum
  duration, or silent ones, are ignored by design; also check the input
  device in System Settings → Sound.

## Uninstall

Quit Pyaww from the panel (⏻ Quit), then drag it from Applications to the
Trash. To also clear the permissions it was granted:

```sh
tccutil reset Microphone com.tklwin.pyaww
tccutil reset Accessibility com.tklwin.pyaww
```

## Website

The bilingual landing page — <https://tklwin.github.io/pyaww/> — is
hand-written and lives in [`site/`](site/), published by GitHub Pages
whenever that folder changes. Maintainer notes (copy rules, the wave
geometry, previewing and publishing): [`docs/website.md`](docs/website.md).

## License and credits

Pyaww's own code is [MIT licensed](LICENSE), © 2026 Thein Kyaw Lwin.

- Speech recognition: a Core ML conversion of
  [freococo/myanmar_asr](https://huggingface.co/freococo/myanmar_asr)
  (Apache-2.0).
- Myanmar word segmentation: a Swift port of
  [mmdt-tokenizer](https://github.com/Myanmar-Data-Tech/mmdt-tokenizer)
  (MIT, Myanmar Data Tech).
- Icon and menu bar wave: original artwork for this project.
