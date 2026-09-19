#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift run PrompterChecks
swift run -c release WhisperCheck --channels
./scripts/build.sh
plutil -lint dist/Prompter.app/Contents/Info.plist scripts/Entitlements.plist
# Shipping binaries may depend on Apple runtime libraries, never this build machine.
otool -L dist/Prompter.app/Contents/MacOS/Prompter | awk 'NR > 1 { print $1 }' > .build/runtime-dependencies.txt
if grep -Ev '^(/System/Library/|/usr/lib/)' .build/runtime-dependencies.txt; then
    echo "Unexpected non-system runtime dependency" >&2
    exit 1
fi
echo "PASS: core, layout, audio channels, release bundle, signature integrity, and runtime dependencies"
