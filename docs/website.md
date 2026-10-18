# The Pyaww website

Live: <https://tklwin.github.io/pyaww/>
Source: [`site/`](../site/) · Deploy: [`.github/workflows/pages.yml`](../.github/workflows/pages.yml)

The landing page is hand-written static HTML/CSS/JS: no build step, no
dependencies, no external requests (system fonts, local assets only). GitHub
Pages publishes the `site/` folder directly; the workflow runs only when
`site/**` (or itself) changes, so app releases never redeploy the page.

## Layout

- `site/index.html` — all page content, including both languages
- `site/style.css` — every style on the page
- `site/pyaww.js` — language toggle + hero wave draw-in
- `site/assets/appicon.png`, `appicon-1024.png`, `apple-touch-icon.png` —
  icon exports from `Design/Icon Exports/`
- `site/assets/panel.png` — a real capture of the app's panel
- `site/assets/wave.svg` — favicon (the brand wave)
- `site/assets/og.png` — 1200 × 630 social card (generated; see below)
- `docs/og-card.html` — social-card source, not published

## Deploy

Push to `main` touching `site/**` → workflow **Deploy landing page to GitHub
Pages** (~20 s – 1 min). Verify that what is served is what is committed:

```sh
curl -s https://tklwin.github.io/pyaww/ | diff -q site/index.html - && echo identical
curl -s https://tklwin.github.io/pyaww/style.css | diff -q site/style.css - && echo identical
curl -s -o /dev/null -w '%{http_code}\n' https://tklwin.github.io/pyaww/assets/og.png
```

History: the page was first published from the personal site
(`tklwin.github.io/static/pyaww/`) and moved here on 2026-10-18 at the same
URL, so links kept working. The old copy was removed; do not re-add it there.

## Two languages

Every user-visible string is a pair of spans:

```html
<span class="en">English</span><span class="my">မြန်မာ</span>
```

`body.lang-en` / `body.lang-my` show one at a time. `pyaww.js` restores the
choice from `localStorage["pyaww-lang"]`, otherwise follows the browser
language (`my…` → Myanmar, else English). The toggle is
`.langswitch button[data-lang]`, with `aria-pressed` kept in sync.

Keep the two languages in step: never ship an `.en` string without its `.my`
pair, or the reverse.

## Copy rules (owner-owned)

- **Burmese copy is owner-reviewed.** Do not change `.my` strings without the
  owner checking them before a push.
- Register: spoken Myanmar, short sentences ending `ပါတယ်` / `ပါ`; English
  technical terms stay English (`Microphone`, `Accessibility`, `menu bar
  dictation`); feature-card titles are short noun phrases in the owner's
  `…ခြင်း` style.
- Frozen by the owner (2026-10-18): the hero tagline
  `စာရိုက်နေစရာမလို၊ မြန်မာလိုပဲ ပြောလိုက်ပါ။` and the five feature-card
  titles. The tagline also appears on the social card — keep them identical.
- There is deliberately no guide/help section (owner decision): the page is a
  landing page; the README carries the details.

## The wave

The geometry has one source of truth: `App/MenuBarIcon.swift` (the app icon's
"B" path). It rises first — start `570.6667` → peak `394.6667` → valley
`629.3333` → end `453.3333` in viewBox `118 352.6667 788 318.6667`.

It appears in four places and they must match:

| Where | Stroke width |
| --- | --- |
| Hero `.wave-path` in `site/index.html` | 84 |
| Header brand mark in `site/index.html` | 110 |
| `site/assets/wave.svg` (favicon) | — |
| `docs/og-card.html` (social card) | 84 |

Never mirror it horizontally: the rise/fall order is part of the mark. Step 2
of "How it works" draws the same path in red (`#ff453a`) inside a keycap tile
(owner request, 2026-10-18) with a soft `recpulse` glow; the animation is
disabled under `prefers-reduced-motion`.

## Assets

- `panel.png` is a capture of the app itself — never use personal screen
  content in any asset (owner rule).
- Icon exports come from the Icon Composer workflow in `Design/`.
- No external images, fonts, analytics, or network requests of any kind. Keep
  it that way.

## Preview locally

```sh
python3 -m http.server 8123 --directory site
# open http://127.0.0.1:8123/
```

Use the toggle to check the Myanmar view; the choice is remembered in
`localStorage`. A fresh browser profile starts in English unless its language
is Myanmar.

## Social card

`site/assets/og.png` is rendered from `docs/og-card.html` at 1200 × 630:

```sh
python3 -m http.server 8124 --directory .
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --hide-scrollbars \
  --window-size=1200,630 --virtual-time-budget=4000 \
  --screenshot=site/assets/og.png \
  http://127.0.0.1:8124/docs/og-card.html
```

Regenerate it whenever the hero tagline or branding changes. The `og:image`
meta tag in `index.html` points at the live URL, so replacing the file is
enough.

## Checklist before pushing

- Toggle both languages: every section switches, no mixed-language leftovers.
- The wave rises first (compare against the icon export).
- DevTools → Network shows only local requests.
- The social card matches the hero tagline (regenerate if it changed).
- After deploy: byte-diff `index.html` / `style.css` against the live URL and
  check that every asset returns 200.
