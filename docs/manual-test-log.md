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
| First launch | Microphone prompt appears → **Allow** |✅ |
| Then | Accessibility prompt → **Open System Settings** → enable Pyaww |✅ |
| Menu bar | Menu shows both permissions green (use *Refresh Permission Status* after granting) |✅ |
| One dictation | Hold Right Option, say a short phrase, release → text pastes at the cursor |✅ |
| Menu → Quit | app exits cleanly |✅ |

## Phase 4 re-verify — word segmentation (owner)

The app word-segments the transcription by default (Settings → Pasting →
"Segment Myanmar words"; toggle off = raw model text). The lexicon ships in
the app bundle, so there are no new permissions. Launch `build/Pyaww.app`:

| Step | Expected | ✅ / notes |
| --- | --- | --- |
| One dictation | Text pastes as words, e.g. "မင်္ဂလာ ပါ" (not "မင်္ဂ လာ ပါ") |✅ |
| Settings → Pasting → toggle off | Next dictation pastes the raw model text (syllable spacing) |✅ |
| Toggle back on | Word text again |✅ |
| Settings → Model | "Word segmentation: Ready" |✅ |
| Menu → Quit | app exits cleanly |✅ |

## Settings window re-verify — final fix (owner)

Accessory apps are not activated by menu bar clicks, so the Settings window
used to open *behind* the frontmost app. The final fix (2026-10-17) activates
Pyaww and raises the window explicitly. Quit any running Pyaww first, then
launch the rebuilt `build/Pyaww.app`:

| Step | Expected | ✅ / notes |
| --- | --- | --- |
| Put another app in front, then menu → *Settings…* | Settings window appears **in front** immediately |✅ |
| Switch to another app, then menu → *Settings…* again | window comes back to the front |✅ |
| Menu → Quit | app exits cleanly |✅ |

## Gate 4 rehearsal — clean install from the README alone (owner)

Follow `README.md` → *Install* as if you were a new user ("the real download
journey"). The "download" is pre-staged at
`~/Downloads/Pyaww-0.1.0-arm64.dmg`, quarantined exactly like a Safari
download; Gatekeeper was verified beforehand to report `rejected`
(`origin=Apple Development…`), so the block dialog is guaranteed to appear.
The dev instance was quit and both permission grants were reset
(`tccutil reset Microphone/Accessibility com.tklwin.pyaww`) for genuine
first-run prompts.

| Step | Expected | ✅ / notes |
| --- | --- | --- |
| Open the DMG in `~/Downloads` | "Install this app?" dialog → **Install** (or drag to Applications) |✅ |
| First launch of the installed app | Gatekeeper block ("Apple could not verify …") |✅ |
| System Settings → Privacy & Security → **Open Anyway** → confirm | Pyaww launches; menu bar wave appears |✅ |
| First dictation attempt | Microphone prompt → **Allow** |✅ |
| Menu → *Grant Accessibility Access…* | System Settings opens; enable Pyaww, return to Pyaww |✅ |
| Hold Right Option, say a short phrase, release | Text pastes at the cursor |✅ |
| Menu bar while recording | Wave turns red; white again when idle |✅ |
| README wording check | dialog texts / paths / menu names match the README |✅ |

**2026-10-17 (later): installer window polish.** After the rehearsal, the
packaged window was diagnosed and fixed — on macOS 26 the styling step's
AppleScript `set bounds` can lose a race with Finder, so the shipped
window had opened 920×464 (white bands right of/below the 600×400
background, icons ~45 pt under the arrow line). `scripts/make-dmg.sh`
now normalizes the saved `.DS_Store` after styling (window exactly
600×400, item row on the arrow line). Then, on the owner's request, the
background went from azure to **dark ink navy** (with a soft azure glow
behind the app icon) so the full-bleed blue badge reads clearly instead
of blue-on-blue. `~/Downloads/Pyaww-0.1.0-arm64.dmg` was refreshed
(quarantined again); the flow is unchanged, so the ticks above stay
valid — re-open the new image only to see the polish.
`dist/Pyaww-0.1.0-arm64.dmg` sha256
`775a5a6b2971b4668675e4060f5d103a0c78956bfa01ba99d22fe9926a662302`
(earlier build; superseded by the evening fix below).

**2026-10-17 (evening): caption legibility + arrow placement.** Finder
paints its item labels near-black over custom background pictures in
every appearance (no colour control), so the dark field hid them. The
background now bakes **light plates** under both labels — Finder's own
black text sits on them and reads crisply — after a `textSize`
suppression route was tested and rejected (out-of-range values make
Finder discard the whole saved view state). The arrow and glow also
moved up 45 pt to meet the icon centres (verified: stored y=155 draws
the centre at 155). `~/Downloads/Pyaww-0.1.0-arm64.dmg` refreshed again
(quarantined); the ticks above are unaffected — re-open the new image
only to see the fix. `dist/Pyaww-0.1.0-arm64.dmg` sha256
`915d010105aefe51598ace63c4a1fd7cf964f97333894155dc82cd7d8a35ddba`.
