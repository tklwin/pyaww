# Gate 2 manual test log

Owner-run. For each app: hold **Right Option**, say a short Myanmar phrase,
release — the text must paste at the cursor. Fill in ✅/❌ and notes.

Environment: macOS 27.0.1 , Mac M2 Air 15" 8GB , commit 70871eb

## App matrix

| # | App | Paste at cursor | Clipboard restored | Notes |
| --- | --- | --- | --- | --- |
| 1 | Notes |✅ |✅ | |
| 2 | Safari |✅ |✅ | |
| 3 | Chrome |✅ |✅ | |
| 4 | VS Code |✅ |✅ | |
| 5 | Terminal |✅ |✅ | |
| 6 | Messages / Telegram |✅ |✅ | |

## FR checklist (SPEC §5.1)

| FR | Check | ✅ |
| --- | --- | --- |
| FR-1 | Menu bar icon only (no Dock icon); menu has status, Settings…, Quit |✅ |
| FR-2 | Right Option is push-to-talk by default; changeable in Settings |✅ |
| FR-3 | Text lands at the cursor in the focused app |✅ |
| FR-4 | Esc while recording cancels; nothing pasted |✅ |
| FR-5 | Very short (< 0.3 s) and silent clips are ignored (no paste) |✅ |
| FR-6 | At the maximum duration, recording stops and a notice appears |✅ |
| FR-7 | Previous clipboard contents are restored after the paste |✅ |
| FR-8 | Icon states: idle, recording, transcribing, error |✅ |
| FR-9 | First-run permission guidance + System Settings deep links |✅ |
| FR-10 | Settings: hotkey, min/max duration, launch at login, restore clipboard, sound cue |✅ |

## Edge cases

| Case | Expected | ✅ / notes |
| --- | --- | --- |
| Press hotkey while transcribing | ignored (no second recording) | it is too fast for transcribing so, cannot test |
| Esc while transcribing | paste abandoned |cannot test Esc, because transcribing is so fast |
| Hotkey released instantly (< 0.3 s) | nothing pasted |✅ |
| Speak in a password field (secure input) | no synthetic paste; text left on clipboard + menu message |✅ |
| Clipboard had rich content (image/HTML) | restored after paste |✅ |
| Menu → Quit while recording | app quits cleanly |✅ |

## Phase 3 re-verify (after signing switch + memory fix)

The app is now signed with the Apple Development certificate (first rebuild
after the Phase 3 memory fix), so macOS asks for permissions once more — the
last time. Launch `build/Pyaww.app` (or `./scripts/make-app.sh` then open it)
and tick:

| Step | Expected | ✅ / notes |
| --- | --- | --- |
| First launch | Microphone prompt appears → **Allow** | |
| Then | Accessibility prompt → **Open System Settings** → enable Pyaww | |
| Menu bar | Menu shows both permissions green (use *Refresh Permission Status* after granting) | |
| One dictation | Hold Right Option, say a short phrase, release → text pastes at the cursor | |
| Menu → Quit | app exits cleanly | |
