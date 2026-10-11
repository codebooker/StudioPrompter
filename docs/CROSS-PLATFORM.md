# Windows, Linux, and Android previews

StudioPrompter's first cross-platform implementations live alongside the native Mac app. These are development previews, not replacements for the tested Mac release. The Mac app and iPad companion remain in their existing source trees.

## Applications and CPU support

| Application | Targets | Installer |
| --- | --- | --- |
| StudioPrompter producer | Windows x86-64 and ARM64 | NSIS `.exe` |
| StudioPrompter producer | Linux x86-64 and ARM64 | AppImage and Debian `.deb` |
| StudioPrompter Companion | Android 8.0+ tablets | Universal `.apk` |

Here, x86 means **64-bit x86 (x64)**. These desktop builds do not target legacy 32-bit Windows or Linux. Android's rendering and TLS implementation are Java and need no CPU-specific native runtime.

## Desktop preview

The producer interface shares the browser demo's tested script editor and visual assets. It runs as an installed Electron application with a separate, sandboxed producer window and reading display. Scripts are stored locally; an additional Markdown copy of each script is written into the application's `Scripts` directory. The library index preserves titles, bookmarks, and settings. TXT and Markdown import/export, rich bold/underline editing, paragraph bookmarks, manual scrolling, playback, blackout, typography, reading-guide position and height are included.

**Prompter Output** lists physical displays and **Connect a tablet…**. Display output uses a separate full-screen window. Prompting stays active when the producer uses another app or minimizes the control window. Mirroring and vertical flipping affect the reading output and tablet, while the operator preview remains readable. Tablet pairing uses the same version 2 TLS-PSK protocol as the Mac/iPad apps, including saved credentials and removal notices.

**Voice prompting** offers Follow script and Adaptive pace. Choose a microphone and input channel, download Tiny English (about 78 MB) or Base English (about 148 MB), then press Play. Downloads are checked against pinned SHA-256 hashes before they are installed. The bundled whisper.cpp CPU runtime processes audio on the computer. Pause, manual scrolling, changing inputs, and exiting the app stop capture. Audio stays in memory and is passed over local process pipes to a persistent speech engine. Capture runs on the audio thread using a 16 kHz resampled input, so interface work cannot block audio callbacks. Recognition runs on bounded overlapping audio chunks with an update attempted every 300 ms when the engine is free; silence holds the script and matching tolerates omitted words.

The preview.2 audio path accepts quiet microphone speech and adjusts gain on the copy sent to Whisper. The voice card shows recognized words, inference time, and script-match status; empty recognition results and worker failures are visible. Token timestamp estimates no longer suppress an otherwise valid transcript. Automated checks feed low-gain speech through the renderer capture pipeline into the native worker on every desktop architecture.

This port's speech motion needs live tuning on Windows and Linux. Phrase matching, reading-position spreading, and damped motion are ported from the Mac core; the audio capture and transcription back end are separate. It does not yet have hands-free LLM commands, Webcam Layout, DOCX/PDF import, or automatic in-app updates. Font availability differs by OS. Output uses producer-computed line breaks; check emphasis and spacing on the target display during a take.

### Run and build

Requires Node.js 22+ and CMake/C++ tools to build the pinned whisper.cpp runtime. Install Node dependencies and generate the shared interface:

```sh
cd desktop
npm ci
npm run prepare-ui
npm run fetch-network-runtime
npm test
npm start
```

`desktop/runtime/studio-whisper` (`studio-whisper.exe` on Windows) must be present to use voice. The **Cross-platform preview** GitHub Actions workflow compiles that runtime from a pinned commit, packages each desktop architecture on its target OS, and uploads installers as temporary build artifacts. Local development can use the same CMake flags from that workflow. Packages include whisper.cpp's license and the official Node runtime and license. Tablet networking runs in a separate local process because Electron's BoringSSL does not implement the Mac's AES-GCM PSK cipher. They are unsigned previews and are not published as stable releases.

## Android companion

Connect the tablet and producer computer to the same local network. On the producer, open tablet output and display the pairing code. On Android, select the discovered producer and enter its 12-character code. With Mac 0.2.0, the existing menu is called **Connect iPad…**; it advertises the same service used by Android.

The companion draws text locally using the producer's UTF-16 text ranges, emphasis, precomputed line breaks, guide, mirror/flip settings, blackout, and playback updates. It buffers motion by 100 ms and never extrapolates through a network interruption. Controls hide after five seconds; tap the reading display to reveal them. Disconnect preserves the pairing. Reconnect restores the producer's current position. Forget producer clears local credentials. Removing the tablet on the producer prevents further script delivery and reports removal even if the tablet was offline.

Android never records audio or downloads a speech model. It uses Bouncy Castle's pure Java TLS implementation with exactly the Mac/iPad AES-128-GCM PSK cipher, rather than relying on Android vendors' differing TLS-PSK support. Pairings live in private application storage with backup disabled. Frame size, document geometry, and playback values are checked before rendering.

### Build

Requires Java 17, Gradle 8.11.1, and Android SDK 35. Open `android/` in Android Studio, or run:

```sh
cd android
gradle testDebugUnitTest assembleDebug
```

The debug APK is in `android/app/build/outputs/apk/debug/`. Debug APKs are intended for development testing; a stable signing key and release distribution need to be established before Play Store or durable public APK distribution.

## Validation and release gates

The Node checks cover fragmented Unicode framing, bounded messages, invalid geometry, skipped-word alignment, genuine TLS pairing/resumption, persisted credentials, incorrect-key rejection, and offline revocation. Java checks cover Unicode framing, oversized frames, key derivation, motion interpolation/freeze, and actual TLS pairing/resumption/revocation against the desktop server and the native Mac Network.framework transport. CI compiles the Android APK and all four desktop installers, and checks Android launch, readable script drawing, mirroring, and blackout in a tablet emulator.

Before a public release, test the installed packages on physical Windows x64/ARM64 and Linux x64/ARM64 systems, plus an Android tablet. Check local model downloads, microphone channels, cadence changes, retakes, external displays, rendering and bookmarks, mirroring, denied network access, disconnected networks, app restarts, and producer removals. Android-to-Mac and iPad-to-Windows/Linux interoperability require device confirmation. The initial four desktop installers, persistent speech-worker builds, Mac transport interoperability, and Android tablet emulator checks have passed. Native model-download/transcription checks are included for each desktop CPU architecture. The build artifacts alone do not establish feature parity or live speech performance.
