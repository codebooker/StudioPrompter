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
python3 - "$EXPORT" <<'PYVERIFY'
import pathlib,plistlib,re,sys,zipfile
spec=pathlib.Path('iPad/project.yml').read_text()
version=re.search(r"MARKETING_VERSION: '([^']+)'",spec).group(1)
build=re.search(r"CURRENT_PROJECT_VERSION: '([^']+)'",spec).group(1)
with zipfile.ZipFile(pathlib.Path(sys.argv[1])/'StudioPrompterCompanion.ipa') as archive:
    root='Payload/StudioPrompterCompanion.app/'
    info=plistlib.loads(archive.read(root+'Info.plist'))
    assert info['CFBundleShortVersionString']==version, 'Exported version differs from project'
    assert info['CFBundleVersion']==build, 'Exported build differs from project'
    assert info['UIDeviceFamily']==[2], 'Companion must be iPad-only'
    assert info['CFBundleIdentifier']=='co.codebooker.studioprompter.companion'
    assert root+'PrivacyInfo.xcprivacy' in archive.namelist(), 'Missing privacy manifest'
    for framework in ('PrompterCore', 'PrompterLink'):
        metadata=plistlib.loads(archive.read(root+f'Frameworks/{framework}.framework/Info.plist'))
        assert metadata.get('CFBundleShortVersionString')==version, f'{framework} missing or incorrect marketing version'
        assert metadata.get('CFBundleVersion')==build, f'{framework} missing or incorrect build version'
print(f'Verified Companion {version} ({build}), iPad-only, with privacy manifest.')
PYVERIFY
echo "Exported Companion for App Store Connect to $EXPORT (not uploaded)."
