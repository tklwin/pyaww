# Pyaww beta testing

v0.1.0 is the first public beta. The goal is to find problems on Macs and
macOS versions other than the owner's. Thank you for testing.

## Before you start

- Apple silicon (M1 or newer), macOS 14 (Sonoma) or later.
- Install from [Releases](https://github.com/tklwin/pyaww/releases/latest)
  and follow the README's first-launch steps. macOS will block the app
  because it is free-distribution signed, not notarized:
  **System Settings → Privacy & Security → Open Anyway**.
- Pyaww is a menu-bar app: no Dock icon, no window. The wave sits at the
  right end of the menu bar. Click it (left or right) to open the panel.
- Everything runs locally: no account, no network, no telemetry. Audio and
  transcripts never leave your Mac.

## 15-minute checklist

Tick each row. Anything that fails is a useful report — the notes matter
more than the tick.

| # | Check | Expected | Result |
| --- | --- | --- | --- |
| 1 | Install from the DMG | App in Applications (or your user Applications) | |
| 2 | First launch through Gatekeeper | **Open Anyway** works; no crash | |
| 3 | Microphone prompt | Allow; panel shows Microphone granted | |
| 4 | Accessibility prompt | Toggle Pyaww on; panel shows Accessibility granted | |
| 5 | Idle wave | Matches the menu bar appearance (not red) | |
| 6 | Hold **Right Option**, speak, release in Notes | Text appears at the cursor | |
| 7 | Wave while recording | Turns red, returns to idle after paste | |
| 8 | **Esc** while recording | No paste, back to idle | |
| 9 | Tap the key and release instantly | Ignored (shorter than the 0.3 s minimum) | |
| 10 | Record to the 30 s limit | Stops itself and still pastes the text | |
| 11 | Clipboard restore | Your previous clipboard contents return after the paste | |
| 12 | Paste in Notes / Safari / Chrome / VS Code / Terminal / Messages | Text lands at the cursor; Myanmar renders correctly | |
| 13 | Word segmentation toggle (panel) | Off = the model's raw syllable spacing | |
| 14 | Sound cue + launch at login | Toggle on, restart, settings persist | |
| 15 | Panel footer | Shows `pyaww v0.1.0`; GitHub link and **Quit** work | |

## Reporting a problem

Open a GitHub issue:
<https://github.com/tklwin/pyaww/issues/new?template=bug_report.yml>

Please include:

- **Pyaww version** — the panel footer (`pyaww v0.1.0`)
- **macOS version** and **Mac model/chip** (Apple menu → About This Mac)
- **Steps** that reproduce it, **expected** and **actual**
- A screenshot if it is visual
- **Logs** (optional, below)

### Logs

```sh
log show --last 15m --predicate 'subsystem == "com.tklwin.pyaww"' --info --debug
```

Logs contain timings and error messages, never audio or transcribed text.
Still, read them before posting — if you see something personal, leave it
out.

## Known issues

- **“Apple could not verify…”** — expected: the app is not notarized. Use
  Open Anyway (README has the steps, including a Terminal fallback).
- **Password fields and secure input** — macOS blocks synthetic paste
  there by design; Pyaww does not try to defeat it.
- **Some terminal or Electron apps paste differently** — the transcript is
  left on the clipboard, so ⌘V is the fallback.
- **First launch is slower** — the bundled model is compiled once into
  `~/Library/Application Support/Pyaww/CompiledModels`; later starts are
  fast.
- **Rebuilding from source with ad-hoc signing resets permissions** — this
  does not apply to the release DMG (stable Apple Development identity).

## Reset, uninstall, re-test

Quit from the panel, then drag Pyaww from Applications to the Trash. To
also clear the permissions it was granted:

```sh
tccutil reset Microphone com.tklwin.pyaww
tccutil reset Accessibility com.tklwin.pyaww
```

Reinstall and run the checklist again from a clean state.

## Compatibility matrix

Filled in from tester reports — please say which row you tested.

| macOS | Chip | Status |
| --- | --- | --- |
| 14 Sonoma | M1 / M2 / M3 / M4 | not tested yet |
| 15 Sequoia | M1 / M2 / M3 / M4 | not tested yet |
| 26 | M1 / M2 / M3 / M4 | not tested yet |
| 27 | M2 (owner) | v0.1.0 verified |

## Out of scope for this beta

Intel Macs, macOS 13 and earlier, languages other than Myanmar, streaming
partial results, and transcript history. If one of these blocks you, say
so in the issue — it helps prioritise, but it is not a bug.
