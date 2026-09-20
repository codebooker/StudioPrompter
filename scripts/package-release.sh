#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${STUDIO_EXPERIMENTAL_COMMANDS:-0}" == 1 && "${TESTER_RELEASE:-0}" != 1 ]]; then
    echo "Experimental commands require an explicitly selected tester release." >&2; exit 1
fi
VERSION="${RELEASE_VERSION:-0.2.0}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] || { echo "Invalid release version" >&2; exit 1; }
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' scripts/Info.plist)"
[[ "${VERSION%%-*}" == "$PLIST_VERSION" ]] || { echo "Release version must match Info.plist" >&2; exit 1; }
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "Commit source changes before packaging so the archive has an exact source revision." >&2
    exit 1
fi
if [[ "${UPDATE_FEED:-0}" == 1 ]]; then
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Update feeds require numeric release versions." >&2; exit 1; }
    if [[ "${TESTER_RELEASE:-0}" != 1 ]]; then
        [[ -n "${NOTARY_PROFILE:-}" && -n "${SIGNING_IDENTITY:-}" ]] || { echo "Stable updates require Developer ID signing and notarization. Use TESTER_RELEASE=1 only for the separate tester feed." >&2; exit 1; }
    fi
    [[ -f "${RELEASE_NOTES_FILE:-}" ]] || { echo "Set RELEASE_NOTES_FILE to the release's Markdown notes." >&2; exit 1; }
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
    echo "Experimental hands-free commands: ${STUDIO_EXPERIMENTAL_COMMANDS:-0}"
    echo "Minimum macOS: $(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
    echo "Signing: $SIGNING"
    echo "Built UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    swift --version
} > "$OUT/BUILD-INFO.txt"
if [[ "${UPDATE_FEED:-0}" == 1 ]]; then
    FEED_NAME=appcast.xml
    if [[ "${TESTER_RELEASE:-0}" == 1 ]]; then FEED_NAME=tester-appcast.xml; fi
    BUNDLE_FEED="$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' "$APP/Contents/Info.plist")"
    [[ "$BUNDLE_FEED" == "https://raw.githubusercontent.com/codebooker/StudioPrompter/main/updates/$FEED_NAME" ]] || { echo "Bundle update channel does not match release channel." >&2; exit 1; }
    cp "$RELEASE_NOTES_FILE" "${ZIP%.zip}.md"
    .build/artifacts/sparkle/Sparkle/bin/generate_appcast \
        --account studio.local.prompter -o "$OUT/$FEED_NAME" --maximum-deltas 0 --maximum-versions 1 --embed-release-notes \
        --download-url-prefix "https://github.com/codebooker/StudioPrompter/releases/download/$VERSION/" \
        --link "https://github.com/codebooker/StudioPrompter/releases/tag/$VERSION" "$OUT"
    python3 - "$OUT/$FEED_NAME" "$VERSION" "$FEED_NAME" <<'PYVERIFY'
import pathlib, sys
sys.path.insert(0, 'scripts')
from update_feed import inspect_feed
inspect_feed(pathlib.Path(sys.argv[1]).read_bytes(), tag=sys.argv[2], previous=pathlib.Path('updates', sys.argv[3]).read_bytes())
PYVERIFY
    swift scripts/verify-update.swift scripts/Info.plist "$OUT/$FEED_NAME" "$ZIP"
fi
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS.txt)
echo "Packaged $ZIP ($SIGNING)"
