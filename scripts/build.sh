#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Prompter
APP="$PWD/dist/Prompter.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/Prompter" "$APP/Contents/MacOS/Prompter"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp ThirdParty/*.txt "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
swift scripts/make-icon.swift "$PWD/.build/Prompter.iconset"
iconutil -c icns .build/Prompter.iconset -o "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    [[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || { echo "Use a Developer ID Application identity for distribution." >&2; exit 1; }
    codesign --force --options runtime --timestamp --entitlements scripts/Entitlements.plist --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $APP"
