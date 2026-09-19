#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product PrompterChecks
CHECKS_BIN="$(swift build --show-bin-path)/PrompterChecks"
codesign --verify --strict "$CHECKS_BIN"
"$CHECKS_BIN"
swift run -c release WhisperCheck --channels
./scripts/build.sh
plutil -lint dist/Prompter.app/Contents/Info.plist scripts/Entitlements.plist
# Shipping binaries may depend on Apple runtime libraries, never this build machine.
otool -L dist/Prompter.app/Contents/MacOS/Prompter | awk 'NR > 1 { print $1 }' > .build/runtime-dependencies.txt
if grep -Ev '^(/System/Library/|/usr/lib/|@rpath/Sparkle\.framework/Versions/B/Sparkle$)' .build/runtime-dependencies.txt; then
    echo "Unexpected non-system runtime dependency" >&2
    exit 1
fi
test -x dist/Prompter.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate
test -x dist/Prompter.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater
python3 scripts/test-update-feed.py
swift scripts/verify-update.swift --self-test
echo "PASS: core, layout, audio channels, release bundle, signature integrity, and runtime dependencies"
