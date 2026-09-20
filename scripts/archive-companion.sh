#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer team ID.}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ARCHIVE="$PWD/.build/StudioPrompterCompanion.xcarchive"
EXPORT="$PWD/dist/testflight"
mkdir -p .build "$EXPORT"
xcodebuild -project iPad/StudioPrompterCompanion.xcodeproj -scheme StudioPrompterCompanion \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" -derivedDataPath .build/ipad-distribution \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" -allowProvisioningUpdates archive
python3 - "$DEVELOPMENT_TEAM" > .build/companion-export-options.plist <<'PY'
import plistlib,sys
plistlib.dump({'method':'app-store-connect','destination':'export','signingStyle':'automatic',
              'teamID':sys.argv[1],'manageAppVersionAndBuildNumber':False,'uploadSymbols':True},sys.stdout.buffer)
PY
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist .build/companion-export-options.plist \
  -exportPath "$EXPORT" -allowProvisioningUpdates
echo "Exported Companion for App Store Connect to $EXPORT (not uploaded)."
