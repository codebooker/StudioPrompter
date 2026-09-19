# StudioPrompter 0.1.0 · First tester release

A native Mac teleprompter for the person on camera and the producer behind it.

## Included

- Separate producer controls and clean, full-screen talent output, with mirroring, flipping, and blackout.
- A Markdown script library, document import, bold and underline, and visible, named cue points.
- Readable typefaces and adjustable size, spacing, margins, reading guide, and focus area.
- Local Whisper **Follow script** and **Adaptive pace**, with one-click model download.
- Microphone and individual input-channel selection for an isolated presenter feed.
- Manual scrolling during voice prompting: reposition for a retake, then read from the new location.
- **Check for Updates…** for subsequent tester releases, using signed update archives.

The experimental **“Hey Teleprompter” commands and command AI are not included**. They need more live testing and will return in a later release.

## Install

1. Download **StudioPrompter-0.1.0-macos-arm64.zip** below and unzip it.
2. Move **Prompter.app** to Applications. It appears as **StudioPrompter**.
3. Open it. This tester build is **not Developer ID signed or notarized**. If macOS blocks it, open **System Settings → Privacy & Security → Open Anyway** for StudioPrompter. [Apple’s first-launch instructions](https://support.apple.com/en-us/102445).
4. Import or write a script. For voice prompting, select your microphone/channel and click **Download model**, then **Play**.

Requires an **Apple silicon Mac (M1 or newer)**. Deployment target: **macOS 13.3+**; the minimum OS has not yet been tested on physical hardware. Intel Macs are not supported by this download. English speech models are offered; Base English is recommended for latency.

## Updates and testing status

Pause and stop the microphone, then choose **StudioPrompter → Check for Updates…**. Future published tester builds can download and install through the app. Updates use the separate tester feed and the app’s pinned Ed25519 signing key. Apple notarization and first-launch approval are separate from update archive verification.

Automated core/layout, audio-channel, bundle, and update-signature checks pass. Follow script, cadence changes, skipped words, and dual-display output have been exercised on the development Mac. A clean second-Mac installation, minimum-OS runtime, physical mixer routing, and broader retake acceptance still need tester feedback. This is an early testing release, not a production-readiness claim. See [testing details](https://github.com/codebooker/StudioPrompter/blob/main/docs/TESTING.md).

Audio stays in memory on your Mac. The app does not save audio or transcripts. Scripts and downloaded speech models remain local and survive app updates.

`SHA256SUMS.txt` verifies the archive; `BUILD-INFO.txt` records the exact source commit and signing status. Source is available under AGPL v3, with third-party notices included in the app.
