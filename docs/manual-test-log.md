# Gate 2 manual test log

Owner-run. For each app: hold **Right Option**, say a short Myanmar phrase,
release — the text must paste at the cursor. Fill in ✅/❌ and notes.

Environment: macOS ________ , Mac ________ , commit ________

## App matrix

| # | App | Paste at cursor | Clipboard restored | Notes |
| --- | --- | --- | --- | --- |
| 1 | Notes | | | |
| 2 | Safari | | | |
| 3 | Chrome | | | |
| 4 | VS Code | | | |
| 5 | Terminal | | | |
| 6 | Messages / Telegram | | | |

## FR checklist (SPEC §5.1)

| FR | Check | ✅ |
| --- | --- | --- |
| FR-1 | Menu bar icon only (no Dock icon); menu has status, Settings…, Quit | |
| FR-2 | Right Option is push-to-talk by default; changeable in Settings | |
| FR-3 | Text lands at the cursor in the focused app | |
| FR-4 | Esc while recording cancels; nothing pasted | |
| FR-5 | Very short (< 0.3 s) and silent clips are ignored (no paste) | |
| FR-6 | At the maximum duration, recording stops and a notice appears | |
| FR-7 | Previous clipboard contents are restored after the paste | |
| FR-8 | Icon states: idle, recording, transcribing, error | |
| FR-9 | First-run permission guidance + System Settings deep links | |
| FR-10 | Settings: hotkey, min/max duration, launch at login, restore clipboard, sound cue | |

## Edge cases

| Case | Expected | ✅ / notes |
| --- | --- | --- |
| Press hotkey while transcribing | ignored (no second recording) | |
| Esc while transcribing | paste abandoned | |
| Hotkey released instantly (< 0.3 s) | nothing pasted | |
| Speak in a password field (secure input) | no synthetic paste; text left on clipboard + menu message | |
| Clipboard had rich content (image/HTML) | restored after paste | |
| Menu → Quit while recording | app quits cleanly | |
