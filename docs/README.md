# Pyaww documentation

Start here. This folder is the project's memory: **one home per fact**,
links instead of copies. Current behaviour lives in `architecture.md`;
the reasons live in `decisions.md`; open work in `todo.md`; the process in
`build-release.md` and `beta.md`.

## Reading order

1. [`../README.md`](../README.md) — what Pyaww is, install, usage
2. [`architecture.md`](architecture.md) — the as-built design
3. [`decisions.md`](decisions.md) — why it is built this way
4. [`build-release.md`](build-release.md) — build, test and release
5. [`beta.md`](beta.md) — tester checklist and reporting
6. [`model-spec.md`](model-spec.md) — model I/O and front-end contract
7. [`website.md`](website.md) — the landing page
8. [`../SPEC.md`](../SPEC.md) — the frozen v1 build brief (historical)

## Index

| File | What it is | Status | Update when |
| --- | --- | --- | --- |
| `architecture.md` | As-built design: modules, data flow, privacy, shell | Living | The design changes |
| `decisions.md` | Chronological decision log with reasons | Append-only | A decision is made |
| `build-release.md` | Build, test, packaging and release runbook | Living | The process changes |
| `beta.md` | External tester guide: checks, reports, known issues | Living | The beta changes |
| `model-spec.md` | Model I/O and audio front-end contract | Living | The model changes |
| `third-party.md` | Licences and notices | Living | A dependency changes |
| `website.md` | Landing page: hosting, copy rules, assets | Living | The site changes |
| `todo.md` | Open work, owner decisions, parked items | Living | Work starts or finishes |
| `retrospective-v0.1.0.md` | What building v0.1.0 taught us | Historical | Never |
| `evidence/performance.md` | Phase 3 measurements (Gate 3) | Historical | A new measurement supersedes it |
| `evidence/manual-test-log.md` | Gate 2/4 test records | Historical | Never — append a new log instead |
| `evidence/name-check.md` | Name collision check | Historical | Never |
| `og-card.html` | Source for `site/assets/og.png` | Tool | The share card changes |

The rule: **current behaviour** → architecture/README; **why** →
decisions; **open work** → todo; **process** → build-release / beta /
website; **user steps** → README and the site. Everything else links.

## Historical documents

`../SPEC.md` is the v1 build brief. It is frozen: its phases and gates are
the record of how v0.1.0 was built, not current instructions. New work
starts from `architecture.md`, `todo.md` and the `v0.1.0-foundation` tag.

## Adding a decision

Append to `decisions.md` with the date, the decision, why, and what was
rejected. Do not rewrite earlier entries — supersede them.
