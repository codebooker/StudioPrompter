#!/bin/bash
set -euo pipefail
# Package an already verified app without changing its contents or signature.
APP="${1:?Usage: package-dmg.sh /path/Prompter.app /path/output.dmg}"
DMG="${2:?Provide the output DMG path}"
[[ ! -e "$DMG" ]] || { echo "Refusing to replace an existing disk image: $DMG" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
STAGING="$(mktemp -d -t studioprompter-dmg)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/StudioPrompter.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Install StudioPrompter.txt" <<'INSTALL'
StudioPrompter

Drag StudioPrompter.app into Applications, then open it from Applications.

Early tester builds may not be Apple notarized. If macOS blocks the first launch,
open System Settings > Privacy & Security and choose Open Anyway for StudioPrompter.

Apple silicon Mac (M1 or newer), macOS 13.3 or later.

Source, license, release notes, and feedback:
https://github.com/codebooker/StudioPrompter

Future updates: StudioPrompter > Check for Updates…
INSTALL
mkdir -p "$(dirname "$DMG")"
hdiutil create -volname StudioPrompter -srcfolder "$STAGING" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi
