#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Prompter
APP="$PWD/dist/Prompter.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/Prompter" "$APP/Contents/MacOS/Prompter"
cp scripts/Info.plist "$APP/Contents/Info.plist"
SPARKLE="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SPARKLE" ]] || { echo "Sparkle binary artifact is missing." >&2; exit 1; }
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
# SwiftPM derives the root artifact identity from the checkout directory name.
LLAMA="$(find "$PWD/.build/artifacts" -type d -path '*/llama/llama.xcframework/macos-arm64_x86_64/llama.framework' -print -quit)"
[[ -d "$LLAMA" ]] || { echo "Command AI runtime artifact is missing." >&2; exit 1; }
rm -rf "$APP/Contents/Frameworks/llama.framework"
ditto "$LLAMA" "$APP/Contents/Frameworks/llama.framework"
cp ThirdParty/*.txt "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
swift scripts/make-icon.swift "$PWD/.build/Prompter.iconset"
iconutil -c icns .build/Prompter.iconset -o "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    [[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || { echo "Use a Developer ID Application identity for distribution." >&2; exit 1; }
    FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
    # Sign nested executables before their containing bundles. Retain the XPC
    # helpers' sandbox entitlements; do not use --deep to re-sign a distribution.
    for ITEM in "$FRAMEWORK/XPCServices/Downloader.xpc" "$FRAMEWORK/XPCServices/Installer.xpc" "$FRAMEWORK/Autoupdate" "$FRAMEWORK/Updater.app"; do
        codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$SIGNING_IDENTITY" "$ITEM"
    done
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP/Contents/Frameworks/llama.framework"
    codesign --force --options runtime --timestamp --entitlements scripts/Entitlements.plist --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP/Contents/Frameworks/llama.framework"
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $APP"
