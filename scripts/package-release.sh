#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${RELEASE_VERSION:-0.1.0-beta.1}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] || { echo "Invalid release version" >&2; exit 1; }
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' scripts/Info.plist)"
[[ "${VERSION%%-*}" == "$PLIST_VERSION" ]] || { echo "Release version must match Info.plist" >&2; exit 1; }
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "Commit source changes before packaging so the archive has an exact source revision." >&2
    exit 1
fi
if [[ -n "${NOTARY_PROFILE:-}" && -z "${SIGNING_IDENTITY:-}" ]]; then
    echo "Notarization requires SIGNING_IDENTITY (Developer ID Application)." >&2; exit 1
fi
./scripts/check.sh
APP="$PWD/dist/Prompter.app"
ARCH="$(lipo -archs "$APP/Contents/MacOS/Prompter")"
[[ "$ARCH" == "arm64" ]] || { echo "This beta package currently targets arm64 only." >&2; exit 1; }
OUT="$PWD/dist/releases/$VERSION"
mkdir -p "$OUT"
ZIP="$OUT/StudioPrompter-$VERSION-macos-$ARCH.zip"
SIGNING="ad-hoc development build; not notarized"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then SIGNING="Developer ID signed; not notarized"; fi
# ditto may update an existing ZIP; remove only this generated artifact before recreating it.
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    SIGNING="Developer ID signed and notarized; ticket stapled and Gatekeeper assessment passed"
fi
codesign --verify --deep --strict "$APP"
{
    echo "StudioPrompter $VERSION"
    echo "Source: https://github.com/codebooker/StudioPrompter"
    echo "Commit: $(git rev-parse HEAD)"
    echo "Architecture: $ARCH"
    echo "Minimum macOS: $(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
    echo "Signing: $SIGNING"
    echo "Built UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    swift --version
} > "$OUT/BUILD-INFO.txt"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS.txt)
echo "Packaged $ZIP ($SIGNING)"
