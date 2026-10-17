#!/bin/sh
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
# Dev tool only — not part of the app. Requires only macOS built-ins
# (swift, sips, iconutil). Usage: ./scripts/make-icon.sh
set -eu
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

swift scripts/make-icon.swift "$TMP/icon-1024.png"

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
    sips -z "$px" "$px" "$TMP/icon-1024.png" --out "$SET/$name.png" >/dev/null
done
# The 1024 render doubles as the macOS "512@2x" art.
cp "$TMP/icon-1024.png" "$SET/icon_512x512@2x.png"

mkdir -p Resources
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"
