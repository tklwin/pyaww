#!/bin/bash
# Runs the Swift test suite with workarounds for this Command Line Tools
# toolchain (see docs/build.md → "plugin for module 'TestingMacros'"):
#
# 1. The build engine may reuse an on-disk build description that lacks the
#    Swift Testing macro flags; dropping the cached plan (manifest.pif +
#    XCBuildData) forces a fresh plan.
# 2. Fresh plans still omit the resolved `TestingMacros` plugin (its dylib
#    lives in the toolchain's `plugins/testing/` subdirectory, which the
#    plan generator does not scan), so `@Suite`/`@Test` fail with
#    "plugin for module 'TestingMacros' not found". Passing the plugin
#    directories explicitly with `-plugin-path` restores resolution
#    (verified 2026-10-17; a bare `swiftc -typecheck` repro works the same).
set -euo pipefail

cd "$(dirname "$0")/.."

rm -rf .build/manifest.pif .build/out/Intermediates.noindex/XCBuildData

# <toolchain>/usr/lib/swift/host/plugins{,/testing} (e.g. CommandLineTools).
USR="$(dirname "$(dirname "$(xcrun --find swiftc)")")"
PLUGINS="$USR/lib/swift/host/plugins"
PLUGIN_FLAGS=()
if [ -d "$PLUGINS/testing" ]; then
    PLUGIN_FLAGS=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS" -Xswiftc -plugin-path -Xswiftc "$PLUGINS/testing")
fi

exec swift test ${PLUGIN_FLAGS[@]+"${PLUGIN_FLAGS[@]}"} "$@"
