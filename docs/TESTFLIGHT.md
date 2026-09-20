# StudioPrompter Companion · TestFlight preparation

The iPad app is **StudioPrompter Companion**, a reading display for **StudioPrompter 0.2.0 or later on Mac**. It is not a standalone script editor and does not capture audio or run speech models. Mac distribution remains GitHub plus Sparkle; this submission does not put the Mac app on TestFlight.

## App record

- Platform: iOS (iPad-only target)
- Name: StudioPrompter Companion
- Primary language: English (U.S.)
- Bundle ID: `co.codebooker.studioprompter.companion`
- SKU: `studioprompter-companion-ipad`
- Apple app ID: `6814059982`
- [App Store Connect](https://appstoreconnect.apple.com/apps/6814059982/testflight)
- Version: 0.1.0, build 4
- Category suggestion: Photo & Video
- Support: https://github.com/codebooker/StudioPrompter/issues
- Privacy policy draft: [PRIVACY.md](PRIVACY.md)

The app record was created under the John Tawes account. Build 2 passed local export but Apple rejected its embedded frameworks because their marketing versions were missing. Build 3 shares version settings across the app and both frameworks; the export script checks all three bundles. Account agreements must be reviewed and accepted by the account holder.

The beta description, marketing/privacy URLs, feedback email, and review contact have been saved in App Store Connect. Personal review contact details remain there and are not committed to this repository.

Build 3 finished processing on 2026-09-20 and was added to the **Studio Testing** internal group. The owner authorized an invitation to their existing App Store Connect account; App Store Connect confirmed **Invited**. Build 4 corrects an icon-rendering defect found during visual inspection. Neither build has yet been verified as installed through TestFlight or submitted for external beta review.

## Build and export

Run with full Xcode and a team authorized for distribution:

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID ./scripts/archive-companion.sh
```

This creates a Release `.xcarchive` in `.build/` and exports an App Store Connect IPA under `dist/testflight/`. It does not upload or invite anyone. Xcode handles automatic distribution signing with the locally configured account. Never put certificates, private keys, profiles, authentication keys, or exported archives into Git.

The app includes an opaque 1024-pixel icon and a privacy manifest declaring system uptime solely for elapsed-time calculations/timers (`35F9.1`). The app uses Apple’s TLS implementation; the encryption declaration is set to no non-exempt encryption. Confirm the export-compliance answers in App Store Connect against the submitted build.

## Beta description

StudioPrompter Companion turns your iPad into the reading display for StudioPrompter on your Mac. Pair once on the same local network, then use the Mac’s producer controls for scrolling, bookmarks, text appearance, mirroring, and blackout. Pairings survive app restarts. The iPad holds its place if the connection drops and explains when the producer has removed its access.

Requires StudioPrompter 0.2.0 or later on an Apple silicon Mac. This companion does not work on its own. No microphone access, cloud account, or speech-model download is required on the iPad.

## What to test

1. Install the matching Mac release and companion on devices connected to the same local network. Allow Local Network access.
2. On the Mac select Prompter Output → Connect iPad; enter that code on the iPad and choose the Mac.
3. Try Play/Pause, manual scrolling, bookmarks, font/guide changes, mirror/flip, and blackout. Read for 15–30 minutes and report stutters with the device models and network setup.
4. Disconnect/reconnect, restart both apps, and verify that the pairing is remembered.
5. Briefly interrupt the iPad connection; confirm the script holds and resumes at the Mac’s current position.
6. Remove a connected iPad on the Mac, then repeat with the companion closed. Verify the removal message and pair again using the new code.
7. Check portrait/landscape, app backgrounding, and control auto-hide after five seconds.

## Beta review notes

This app is a companion display. Review requires an iPad and an Apple silicon Mac running StudioPrompter 0.2.0 or later. The Mac release is available from https://github.com/codebooker/StudioPrompter/releases once published. Do not submit for external review before that matching Mac release is actually accessible.

Both devices must be on the same local network, with Local Network permission granted. Guest networks may isolate clients. Open StudioPrompter on the Mac, choose Prompter Output → Connect iPad, and enter the displayed code in the companion. No demo account or login is required. The Mac includes sample scripts. For a basic review, leave Voice prompting off and press Play. Audio processing is optional and happens only on the Mac.

Add a review contact name, email, and phone number directly in App Store Connect; do not publish personal contact details in this file. Start with internal testing, then submit the first external build for TestFlight review. Invite testers only after the owner identifies the recipients or approves a public invitation link.

## Remaining submission gates

- Upload and processing of the corrected icon in build 4.
- Matching Mac release available for companion testers/reviewers.
- Internal installation from TestFlight and verification of the icon and companion connection.
- External beta review approval before inviting external testers.

Apple references: [create an app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app), [upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds), [TestFlight](https://developer.apple.com/testflight/).
