<p align="center">
  <img src="docs/assets/hero.svg" alt="StudioPrompter — Stay present. We'll keep your place." width="100%">
</p>

<p align="center">
  <a href="https://github.com/codebooker/StudioPrompter/actions/workflows/ci.yml"><img src="https://github.com/codebooker/StudioPrompter/actions/workflows/ci.yml/badge.svg" alt="Build and checks"></a>
  <img src="https://img.shields.io/badge/macOS-13.3%2B-15191f?logo=apple&logoColor=white" alt="macOS 13.3 or later">
  <img src="https://img.shields.io/badge/Voice-local%20Whisper-ff8147" alt="Local Whisper voice recognition">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-AGPL--3.0-637087" alt="AGPL-3.0 license"></a>
</p>

<p align="center"><strong>A native Mac teleprompter built for the person on camera—and the producer behind it.</strong></p>
<p align="center">Two screens. One shared script. A pace that follows the conversation.</p>
<p align="center"><a href="https://github.com/codebooker/StudioPrompter/releases">Releases</a> · <a href="docs/USER-GUIDE.md">User guide</a> · <a href="docs/TESTING.md">Testing & release status</a> · <a href="https://github.com/codebooker/StudioPrompter/issues">Feedback</a></p>

---

## Your studio, in sync

Keep the controls on your Mac. Send a clean, full-screen script to the talent monitor. Adjust the type, move the reading guide, or take over the scroll without making your presenter navigate a single menu.

| For the producer | For the presenter |
| :--- | :--- |
| A searchable Markdown script library, emphasis, and named bookmarks | A clean, borderless display with generous type |
| Live preview and manual wheel, drag, and keyboard control | Adjustable reading guide and focus highlighting |
| One Play button for the microphone and prompting | Voice following that tolerates skipped words |
| Microphone **and individual input channel** selection | Mirrored or flipped output for prompter glass |
| Instant blackout and synchronized display controls | A producer who can step in for a retake |

## Read naturally

**Follow script** listens for nearby phrases and moves the script with you. Skip a word, add a filler, or pause to think. Smooth movement keeps recognized text near the reading guide.

**Adaptive pace** adjusts to your speaking cadence, easing into faster speech and slowing down when you do. Nearby phrase matches help keep the guide close to your place.

**Take over whenever you need to.** While voice prompting is running, scroll back to a line. The mic stays on; the script waits for fresh speech at the new position before following again. Pause stops both the microphone and prompting. With voice prompting off, manual scrolling pauses fixed-speed playback.

Voice features are in beta. Recognition and responsiveness depend on your Mac, microphone, speaking style, and script. English is currently supported.

## Start in four steps

1. **Open a script.** Write directly in the app or import TXT, Markdown, RTF, RTFD, DOC, or DOCX. Emphasize key passages with bold and underline, and place named bookmarks directly in the editor.
2. **Send it to your display.** Connect an extended display and choose **Send to display**. The producer workspace stays on your Mac.
3. **Choose your pace.** Use fixed speed, or turn on **Voice prompting**, choose a mode and microphone channel, and click **Download model** once.
4. **Press Play.** Voice mode starts listening and prompting together. Space pauses both.

Everyday controls live in the main window. **Advanced voice settings** is there when you want to tune—not a stop you have to make before every take.

### Local speech. Simple setup.

Whisper runs on your Mac through [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift). The app downloads its model and tokenizer on demand, with progress and retry controls. No model account, command line, or API key is needed.

- **Base English** is the default for responsive live prompting.
- **Small English** is an optional larger model. Try it on your Mac before using it live; improved recognition can come with more delay.
- Audio is processed locally in memory. The app does not save audio or transcripts.
- Once setup completes, prompting works offline. Scripts and settings stay in your local library.

Using an audio interface? Select the interviewer's isolated channel so the guest's separate track does not drive the script. This is channel selection, not speaker identification; sound bleeding into the selected microphone can still be heard. See the [mixer setup guide](docs/USER-GUIDE.md#microphones-and-mixers).

## Get StudioPrompter

**[Download StudioPrompter 0.1.0 — tester release](https://github.com/codebooker/StudioPrompter/releases/tag/0.1.0)**

For **Apple silicon Macs (M1 or newer), macOS 13.3+**. Unzip the download, move `Prompter.app` to Applications, and open it. It appears as **StudioPrompter**. This early build is not notarized: if macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway** for StudioPrompter. See [Apple’s instructions](https://support.apple.com/en-us/102445).

Follow script, Adaptive pace, the Markdown editor, bookmarks, and dual-display output are included. **“Hey Teleprompter” commands and the command AI are excluded** while we improve and test them. This is a tester release, not a production-readiness claim; [remaining validation](docs/TESTING.md) is documented.

Future tester releases arrive through **StudioPrompter → Check for Updates…**. Signed update archives are verified before installation; scripts and downloaded models stay on your Mac.

Developers can build now on macOS 13.3 or later with a recent Xcode or Swift toolchain:

```sh
git clone https://github.com/codebooker/StudioPrompter.git
cd StudioPrompter
./scripts/run.sh
```

This creates and opens `dist/Prompter.app` with a local ad-hoc signature. It is a development build, not a notarized distribution. The app appears as **StudioPrompter** in macOS.

## Coming next: Camera view

The development build includes a compact, floating reading window for solo recording. It starts near the webcam on a built-in display, respects camera cutouts, and can be dragged beneath an external webcam. Adjust width and height independently while keeping the same script position and controls. Camera view is not included in the 0.1.0 tester download yet.

## Built for the Mac

SwiftUI for the workspace. AppKit for native windows and consistent text layout. Core Audio for isolated microphone channels. Core ML for local Whisper inference.

```sh
./scripts/check.sh                    # Core, layout, channel, and bundle checks
./scripts/check-speech.sh             # Download + real-model synthetic speech checks
./scripts/package-release.sh          # Versioned ZIP, checksum, and build metadata
```

See [development and packaging](docs/DEVELOPMENT.md) for architecture, signing, notarization, and release instructions. Contributions and focused bug reports are welcome; include your Mac, macOS version, voice mode, and steps to reproduce. Please avoid posting private scripts or recordings.

## Open source

StudioPrompter is licensed under [GNU AGPL v3](LICENSE). [WhisperKit and its bundled notices](ThirdParty) retain their respective licenses. Thanks to the Whisper and WhisperKit teams for making local speech recognition possible.

### Updates without the download dance

Choose **StudioPrompter → Check for Updates…** to get published tester releases from GitHub. [Sparkle](https://sparkle-project.org/) handles the signed download and Install & Relaunch flow, while your scripts and local speech models stay in place. Checks are manual so update prompts stay out of recording sessions. See [the update guide](docs/UPDATES.md) for release setup and validation.
