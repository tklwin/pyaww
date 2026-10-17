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
# Item positions are forced to y=155: the AppleScript styling can lose the
# same race for item positions, and the background picture is drawn for the
# icon centres at 155 pt from the top — the arrow and glow meet them there,
# and the light caption plates baked into the picture sit exactly where
# Finder's own labels land.
#
# Finder labels stay ON: macOS draws them near-black over custom background
# pictures in every system appearance and offers no colour control, so the
# background bakes light plates under them instead (see
# scripts/make-dmg-background.swift). PYAWW_DS_TEXT_SIZE is kept for
# experiments only: setting it (e.g. 1) rewrites textSize/axTextSize, but
# values outside Finder's 10–16 range make Finder discard the whole icvp
# view state (window size, icon size, background picture) — verified with a
# test build, do not use for shipping.
#
# All edits are same-length, in-place byte swaps so the .DS_Store structure
# stays valid. Exits non-zero on structural surprises: a loud build failure
# beats shipping a mis-sized window.
#
# Usage: python3 scripts/patch-ds-store.py /Volumes/Pyaww
import itertools
import os
import plistlib
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
LABEL_TEXT_SIZE = float(os.environ.get("PYAWW_DS_TEXT_SIZE", "13"))


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

    # --- icon label text size (Finder default 13; env override only for experiments) ---
    i = data.find(b"icvp")
    if i < 0 or data[i + 4:i + 8] != b"blob":
        print("✗ no icvp blob in .DS_Store — cannot patch label text size", file=sys.stderr)
        return 1
    icvp_len = struct.unpack(">I", data[i + 8:i + 12])[0]
    icvp_start, icvp_end = i + 12, i + 12 + icvp_len
    payload = bytes(data[icvp_start:icvp_end])
    try:
        before = plistlib.loads(payload)
    except Exception as exc:
        print(f"✗ icvp unreadable before patch: {exc}", file=sys.stderr)
        return 1

    def read_int(buf, pos):
        """bplist int starting at buf[pos]; returns (value, next pos)."""
        m = buf[pos]
        if m <= 0x0F:
            return m, pos + 1
        if 0x10 <= m <= 0x13:
            size = 1 << (m - 0x10)
            return int.from_bytes(buf[pos + 1:pos + 1 + size], "big"), pos + 1 + size
        raise ValueError(f"not an int at {pos}: 0x{m:02x}")

    def key_at(ref):
        off = offsets[ref]
        m = payload[off]
        if 0x50 <= m <= 0x5F:  # ASCII string
            ln, pos = m & 0x0F, off + 1
            if ln == 0x0F:
                ln, pos = read_int(payload, pos)
            return payload[pos:pos + ln].decode("utf-8", "replace")
        return None

    def real_at(ref):
        """(offset, byte size) of a real value object inside the payload."""
        off = offsets[ref]
        m = payload[off]
        if m == 0x23:
            return off + 1, 8
        if m == 0x22:
            return off + 1, 4
        return None

    trailer = payload[-32:]
    offset_size, ref_size = trailer[6], trailer[7]
    num_objects = int.from_bytes(trailer[8:16], "big")
    top = int.from_bytes(trailer[16:24], "big")
    table_off = int.from_bytes(trailer[24:32], "big")
    offsets = [int.from_bytes(payload[table_off + k * offset_size:
                                       table_off + (k + 1) * offset_size], "big")
               for k in range(num_objects)]

    # The icvp dictionary is the top object: <count><key refs><value refs>.
    top_marker = payload[offsets[top]]
    if 0xD0 <= top_marker <= 0xDE:
        count, pos = top_marker & 0x0F, offsets[top] + 1
    elif top_marker == 0xDF:
        count, pos = read_int(payload, offsets[top] + 1)
    else:
        print(f"✗ icvp top object is not a dict (0x{top_marker:02x})", file=sys.stderr)
        return 1
    keys = [int.from_bytes(payload[pos + k * ref_size:pos + (k + 1) * ref_size], "big")
            for k in range(count)]
    pos += count * ref_size
    values = [int.from_bytes(payload[pos + k * ref_size:pos + (k + 1) * ref_size], "big")
              for k in range(count)]

    patched_fields = []
    for want in ("textSize", "axTextSize"):
        ref = next((values[k] for k in range(count) if key_at(keys[k]) == want), None)
        if ref is None:
            continue
        loc = real_at(ref)
        if loc is None:
            print(f"✗ {want} is not stored as a real — cannot patch", file=sys.stderr)
            return 1
        off, size = loc
        data[icvp_start + off:icvp_start + off + size] = struct.pack(
            ">d" if size == 8 else ">f", LABEL_TEXT_SIZE)
        patched_fields.append((want, size))

    if not any(name == "textSize" for name, _ in patched_fields):
        print("✗ no textSize field found in icvp", file=sys.stderr)
        return 1
    after = plistlib.loads(bytes(data[icvp_start:icvp_end]))
    if after.get("textSize") != LABEL_TEXT_SIZE or (
            "axTextSize" in before and after.get("axTextSize") != LABEL_TEXT_SIZE):
        print("✗ label text-size patch did not stick", file=sys.stderr)
        return 1
    fields = " + ".join(f"{name} ({size * 8}-bit)" for name, size in patched_fields)
    if before["textSize"] == LABEL_TEXT_SIZE:
        print(f"  label text size: {LABEL_TEXT_SIZE:g} (kept; light plates come from the background)")
    else:
        print(f"  label text size: {before['textSize']:g} -> {LABEL_TEXT_SIZE:g} ({fields})")

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
