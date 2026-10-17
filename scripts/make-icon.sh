#!/bin/sh
# Regenerates Resources/AppIcon.icns from the final Icon Composer export.
#
# Source of truth: "Design/Icon Exports/Icon-iOS-Default-1024@1x.png"
# (owner's Icon Composer pass, 2026-10-17). The dark/clear/tinted sibling
# exports in that folder are reference only — the shipping icns carries the
# default appearance and macOS draws the other appearances itself.
# Dev tool only — not part of the app. Requires only macOS built-ins
# (sips, iconutil). Usage: ./scripts/make-icon.sh
set -eu
cd "$(dirname "$0")/.."

SRC="Design/Icon Exports/Icon-iOS-Default-1024@1x.png"
if [ ! -f "$SRC" ]; then
    echo "error: $SRC not found (Icon Composer export)" >&2
    exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for spec in \
    16:icon_16x16 32:icon_16x16@2x \
    32:icon_32x32 64:icon_32x32@2x \
    128:icon_128x128 256:icon_128x128@2x \
    256:icon_256x256 512:icon_256x256@2x \
    512:icon_512x512; do
    px=${spec%%:*}
    name=${spec#*:}
    sips -z "$px" "$px" "$SRC" --out "$SET/$name.png" >/dev/null
done
# The 1024 export doubles as the macOS "512@2x" art.
cp "$SRC" "$SET/icon_512x512@2x.png"

mkdir -p Resources
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"
