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

IDENTITY="Pyaww Local"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP_DIR"
    echo "signed with \"$IDENTITY\""
else
    echo "warning: \"$IDENTITY\" identity not found — falling back to ad-hoc signing."
    echo "warning: macOS will forget Microphone/Accessibility grants after every rebuild."
    echo "warning: see docs/build.md to create the certificate (one-time, 5 clicks)."
    codesign --force --sign - "$APP_DIR"
fi

echo "built: $APP_DIR"
