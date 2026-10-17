#!/usr/bin/env python3
# patch-ds-store.py — normalize the packaged DMG's saved Finder window.
#
# Background: macOS 26's Finder races the AppleScript `set bounds` while the
# image is being styled. When the styling loses, Finder saves its own default
# window frame (observed: {{289, 214}, {920, 464}}); when it wins, it saves
# our requested frame (600×400). Either way, the .DS_Store must end up saying
# 600×400 so the installer background picture fills the window exactly (no
# white gaps). This runs after the styling detach, before compression.
#
# The saved frame uses Quartz coordinates: {{left, y-from-screen-bottom},
# {width, height}}. Size is what matters; the saved position is left as the
# styling step produced it (always sane, and screen-size dependent anyway).
#
# Item positions move from y=200 to y=155: macOS 26 draws icon-view items
# ~45 pt below their stored y (measured against the app icon's self-centering
# wave), so y=155 lands the icons on the arrow line at the visual centre of
# the background.
#
# All edits are same-length, in-place byte swaps so the .DS_Store structure
# stays valid. Exits non-zero on structural surprises: a loud build failure
# beats shipping a mis-sized window.
#
# Usage: python3 scripts/patch-ds-store.py /Volumes/Pyaww
import itertools
import re
import struct
import sys
from pathlib import Path

FRAME_RE = re.compile(rb"\{\{([0-9]+), ([0-9]+)\}, \{([0-9]+), ([0-9]+)\}\}")
TARGET_X = 200
TARGET_W = 600
TARGET_H = 400
ITEM_Y_TARGET = 155
ITEM_XS = (150, 450)


def frame_variants(nums, length):
    """Canonical frame string for `nums`, plus whitespace-adjusted variants
    (the Finder rect parser skips spaces) that hit an exact byte length."""
    canonical = "{{%d, %d}, {%d, %d}}" % nums
    if len(canonical) == length:
        yield canonical
        return
    space_idx = [i for i, ch in enumerate(canonical) if ch == " "]
    for r in range(1, len(space_idx) + 1):
        for combo in itertools.combinations(space_idx, r):
            s = "".join(ch for i, ch in enumerate(canonical) if i not in combo)
            if len(s) == length:
                yield s
    for r in range(1, 5):
        for combo in itertools.combinations_with_replacement(space_idx, r):
            s = canonical
            for i in sorted(combo, reverse=True):
                s = s[:i] + " " + s[i:]
            if len(s) == length:
                yield s


def dump_context(data):
    print("  occurrences of '{{' for diagnosis:", file=sys.stderr)
    i = 0
    while True:
        i = data.find(b"{{", i)
        if i < 0:
            break
        print(f"    at {i}: {data[i:i + 40]!r}", file=sys.stderr)
        i += 1


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    path = Path(sys.argv[1]) / ".DS_Store"
    if not path.exists():
        print(f"⚠ no .DS_Store at {path} (window styling was skipped) — leaving as is")
        return 0
    data = bytearray(path.read_bytes())

    # --- window frame: enforce x=200, size 600×400; keep saved y ---
    matches = list(FRAME_RE.finditer(bytes(data)))
    if len(matches) != 1:
        print(f"✗ expected exactly 1 saved window frame, found {len(matches)}", file=sys.stderr)
        dump_context(bytes(data))
        return 1
    m = matches[0]
    saved = tuple(int(g) for g in m.groups())
    nums = (TARGET_X, saved[1], TARGET_W, TARGET_H)
    old = m.group(0)
    new = next((c.encode() for c in frame_variants(nums, len(old))), None)
    if new is None:
        print(f"✗ no same-length replacement for frame {old!r}", file=sys.stderr)
        return 1
    if new != old:
        data[m.start():m.end()] = new
        print(f"  window frame: {old.decode()} -> {new.decode()}")
    else:
        print(f"  window frame: {old.decode()} (already correct)")

    # --- item positions ---
    patched = 0
    i = 0
    while True:
        i = bytes(data).find(b"Iloc", i)
        if i < 0:
            break
        if data[i + 4:i + 8] == b"blob":
            ln = struct.unpack(">I", bytes(data[i + 8:i + 12]))[0]
            if ln == 16:
                p = i + 12
                x, y = struct.unpack(">II", bytes(data[p:p + 8]))
                if x in ITEM_XS:
                    struct.pack_into(">I", data, p + 4, ITEM_Y_TARGET)
                    patched += 1
                    print(f"  item x={x}: y {y} -> {ITEM_Y_TARGET}")
        i += 1
    if patched != 2:
        print(f"⚠ patched {patched} of 2 item positions (styling was partial?)")

    path.write_bytes(data)
    print(f"✓ .DS_Store patched: window {new.decode()}, items at y={ITEM_Y_TARGET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
