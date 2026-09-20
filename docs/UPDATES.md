# In-app updates

Choose **StudioPrompter → Check for Updates…** with prompting paused and the microphone stopped. Sparkle downloads, verifies, installs, and relaunches an update. Checks are manual, so recording sessions are not interrupted. The library and downloaded speech models live outside the app bundle and survive replacement.

## Tester releases

The first release is an early tester build for Apple silicon, distributed as a GitHub **prerelease** with a numeric tag (`0.1.0`). It is ad-hoc signed, not Apple notarized. First installation may require **System Settings → Privacy & Security → Open Anyway**. [Apple explains that approval](https://support.apple.com/en-us/102445). Test the first launch on the recipient’s Mac; a successful local build is not a clean-machine acceptance test.

This build uses `updates/tester-appcast.xml`. Subsequent tester releases use that same feed and the same Ed25519 key, so testers can update from within the app. An archive is verified against the app’s pinned public key before extraction. Non-notarized tester releases never enter the separate stable feed.

1. Increment `CFBundleVersion` for every distributed build. Set `CFBundleShortVersionString` to the numeric release version. Never reuse or replace an already published version.
2. Keep `SUFeedURL` pointed at the tester feed and commit the source. Ordinary builds exclude experimental commands. Starting with 0.1.1, explicitly approved tester packages may include them by setting `STUDIO_EXPERIMENTAL_COMMANDS=1`; stable packaging still rejects that flag.
3. Package and sign the update archive with the existing local Sparkle key:

   ```sh
   STUDIO_EXPERIMENTAL_COMMANDS=1 RELEASE_VERSION=0.1.1 TESTER_RELEASE=1 UPDATE_FEED=1 \
   RELEASE_NOTES_FILE=docs/RELEASE-NOTES-0.1.1.md \
   ./scripts/package-release.sh
   ```

4. Tag the exact packaged commit as `0.1.1`. Upload the ZIP, `tester-appcast.xml`, `SHA256SUMS.txt`, and `BUILD-INFO.txt` to a draft GitHub release. Publish it as a **prerelease** after checks and smoke testing.
5. The **Publish update feed** workflow verifies the uploaded archive’s Ed25519 signature, byte count, app signature integrity, bundle identity, versions, feed URL, minimum OS, and architecture before committing the tester feed. Drafts cannot be promoted. Private signing keys are not needed on GitHub.
6. Check the workflow and perform **Check for Updates… → Install & Relaunch** from the prior tester build. Confirm scripts, bookmarks, emphasis, and model cache survive.

To retry promotion locally: `python3 scripts/publish-update-feed.py 0.1.1 --tester`, then review and commit the verified feed. The script never publishes a release itself. Increasing build numbers and exact release asset URLs prevent downgrade and accidental mismatches. Any failure leaves the existing feed intact.

## Signed general releases

The separate `updates/appcast.xml` stable feed continues to require Developer ID signing, notarization, a stapled ticket, and Gatekeeper acceptance. Stable promotion rejects GitHub prereleases. Configure that bundle’s feed URL accordingly and package with:

```sh
RELEASE_VERSION=1.0.0 UPDATE_FEED=1 \
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-notary-profile' \
RELEASE_NOTES_FILE=docs/RELEASE-NOTES-1.0.0.md \
./scripts/package-release.sh
```

Complete the general-release checks in [TESTING.md](TESTING.md). A future move from the tester feed to the stable feed must itself be delivered as a signed update to existing testers; changing a feed URL only in source does not migrate installed apps.

## Signing key and verification

The app pins `SUPublicEDKey`. Its private key is held in the release Mac’s login Keychain under `studio.local.prompter`. It is not in the repository, app, assets, or Actions secrets. Keep a secure Keychain backup and do not regenerate the key for each release. `generate_keys --account studio.local.prompter -p` prints only the public key. See [Sparkle’s documentation](https://sparkle-project.org/documentation/) for key migration and backup.

`check.sh` verifies the embedded installer helpers, feed validation, and cryptographic tamper rejection. `verify-update.swift` verifies the exact ZIP before promotion extracts it. Update archive signing does not provide Apple notarization or remove the first-install warning.
