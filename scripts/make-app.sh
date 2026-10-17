#!/bin/bash
# Assembles Pyaww.app from the SPM build.
#
# This machine has Command Line Tools only (no Xcode/xcodebuild), so the app
# bundle is assembled by hand: binary + Info.plist + Models resources, then
# signed with the local "Pyaww Local" identity (see docs/build.md).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_DIR="build/Pyaww.app"
# Release builds use a separate scratch directory: mixing configurations in
# one .build breaks macro-plugin resolution for the next `swift test` on
# this CLT-only toolchain (Swift Testing plugins go missing).
SCRATCH=".build-release"
MODEL_PACKAGE="BurmeseASR-Encoder-30s.mlpackage"
CONSTANTS=(mel_filters.json hann_window.json cmvn.json vocab.json)

echo "building PyawwApp ($CONFIG)…"
swift build -c "$CONFIG" --product PyawwApp --scratch-path "$SCRATCH"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path --scratch-path "$SCRATCH")"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/Models"

cp "$BIN_PATH/PyawwApp" "$APP_DIR/Contents/MacOS/PyawwApp"
cp App/Info.plist "$APP_DIR/Contents/Info.plist"
cp -R "Models/$MODEL_PACKAGE" "$APP_DIR/Contents/Resources/Models/"
for f in "${CONSTANTS[@]}"; do
    cp "Models/$f" "$APP_DIR/Contents/Resources/Models/"
done

# App icon (draft 2026-10-17; regenerate with scripts/make-icon.sh).
ICON="Resources/AppIcon.icns"
if [ ! -f "$ICON" ]; then
    echo "error: $ICON not found — run scripts/make-icon.sh" >&2
    exit 1
fi
cp "$ICON" "$APP_DIR/Contents/Resources/"

# Owner decision (2026-10-17): ship the Phase 4 word-segmentation lexicon.
# Both layouts are copied; PyawwCoreResources checks the direct file first,
# then the SPM resource bundle (Contents/Resources of the app).
RESOURCE_BUNDLE="$BIN_PATH/Pyaww_PyawwCore.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
    echo "error: $RESOURCE_BUNDLE not found — PyawwCore resources did not build" >&2
    exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
cp "$RESOURCE_BUNDLE/Contents/Resources/lexicons.json" "$APP_DIR/Contents/Resources/lexicons.json"

# Owner decision (2026-10-17): sign with the Apple Development identity so
# Microphone/Accessibility grants persist across rebuilds. Fallbacks:
# "Pyaww Local" self-signed (guide in docs/build.md), then ad-hoc.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Pyaww Local\)".*/\1/p' | head -1)
fi
if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" "$APP_DIR"
    echo "signed with \"$IDENTITY\""
else
    echo "warning: no stable code-signing identity found — falling back to ad-hoc signing."
    echo "warning: macOS will forget Microphone/Accessibility grants after every rebuild."
    echo "warning: see docs/build.md (Apple Development or \"Pyaww Local\" certificate)."
    codesign --force --sign - "$APP_DIR"
fi

echo "built: $APP_DIR"
