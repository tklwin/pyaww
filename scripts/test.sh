#!/bin/bash
# Runs the Swift test suite with a workaround for a Swift Build quirk on this
# Command Line Tools toolchain: after some source edits, the build engine
# reuses an on-disk build description that is missing the Swift Testing
# macro-plugin flags, so every `@Suite`/`@Test` fails with
# "plugin for module 'TestingMacros' not found". Dropping the cached plan
# (manifest.pif + XCBuildData) forces a correct re-plan; compiled objects and
# the module cache are kept, so runs stay incremental.
set -euo pipefail

cd "$(dirname "$0")/.."

rm -rf .build/manifest.pif .build/out/Intermediates.noindex/XCBuildData
exec swift test "$@"
