# In-app updates

StudioPrompter uses [Sparkle 2](https://sparkle-project.org/documentation/) to download, verify, install, and relaunch published updates. Choose **StudioPrompter → Check for Updates…** in the macOS menu bar.

Checks are manual. There are no background update prompts during a recording and no silent installations. Pause prompting and stop microphone listening before checking. Sparkle presents release notes and progress, handles network errors, and asks before installation. The app saves its library before restarting. The library and downloaded Whisper models live outside the application bundle and are preserved by replacement.

The public channel contains stable Apple-silicon releases only. Drafts and prereleases are never promoted. The feed starts empty until the first eligible release is published. A build without Sparkle must be replaced manually once; subsequent updater-enabled builds can use this menu.

## Release process

1. Increment `CFBundleVersion` in `scripts/Info.plist` to a new integer for **every distributed build**. Sparkle compares this build number, not the Git tag. Set `CFBundleShortVersionString` to the stable version, such as `0.1.1`.
2. Commit and run the normal checks. Complete the release gates in [TESTING.md](TESTING.md).
3. Package the stable release with Developer ID signing, notarization, and update-feed generation:

   ```sh
   RELEASE_VERSION=0.1.1 \
   SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
   NOTARY_PROFILE='your-notary-profile' \
   RELEASE_NOTES_FILE='docs/RELEASE-NOTES-0.1.1.md' \
   UPDATE_FEED=1 ./scripts/package-release.sh
   ```

4. Attach the resulting ZIP, `appcast.xml`, `SHA256SUMS.txt`, and `BUILD-INFO.txt` from `dist/releases/0.1.1/` to the matching GitHub release **before publishing**. The tag must be `0.1.1`, without a `v` prefix. Prepare it as a draft while testing.
5. Publish the release as a stable release. The **Publish update feed** workflow downloads its appcast and archive, checks the pinned Ed25519 signature, archive size, bundle identity, versions, notarization, and Gatekeeper acceptance. Only then does it commit `updates/appcast.xml` to `main`. It refuses old or repeated build numbers and mismatched release URLs. Publishing a prerelease does not run this promotion.
6. Check the workflow result and test **Check for Updates…** from the previous installed version. Confirm Install & Relaunch preserves the library, cue/emphasis data, and model cache.

The workflow has narrowly scoped repository-content write access for this feed commit. It needs no signing secret. If repository branch rules prevent its push, use an allowed review/merge flow for the verified appcast rather than weakening branch protection. After correcting a missing asset or transient failure, rerun the workflow manually with the already-published tag. It never publishes a draft release itself.

For local promotion/testing, `python3 scripts/publish-update-feed.py 0.1.1` performs the same validation and changes only the local feed. Review and commit that file to publish it.

## Signing key

The app pins `SUPublicEDKey`. The corresponding private Ed25519 key is held in the release Mac’s login Keychain under the Sparkle account `studio.local.prompter`. It is **not** in the repository, app, release assets, or GitHub Actions. Keep a secure Keychain backup; do not generate a replacement key for each release.

`generate_keys --account studio.local.prompter -p` prints only the existing public key. Sparkle documents secure key backup and migration in its [setup guide](https://sparkle-project.org/documentation/). Anyone building their own fork must configure their own key and feed.

Sparkle archive signatures complement Apple Developer ID signing and notarization. Update-feed packaging intentionally rejects ad-hoc or unnotarized builds. The ordinary development build still works without access to the private key.

## Validation and remaining release gate

- The app bundle embeds Sparkle and its signed installer helpers; the executable resolves the framework inside the bundle.
- Automated feed checks reject malformed feeds, incorrect hosts/tags, unsigned archives, architecture mismatches, and build-number downgrades.
- `scripts/verify-update.swift` verifies archive bytes with the pinned public key before the publishing workflow extracts anything.
- Before the first public release, exercise a complete update between two Developer ID signed, notarized builds on a separate Mac, plus network failure, cancellation, and recovery. A development signature check alone does not establish Gatekeeper or installation behavior on another machine.

The currently prepared draft beta is not automatically eligible for this feed. Do not publish it just to exercise the updater.
