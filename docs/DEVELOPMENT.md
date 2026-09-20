# Development and releases

## Build

Use a recent Swift toolchain or Xcode on macOS. Use Swift 6.0 or newer for the pinned dependency graph (the app manifest itself declares Swift tools 5.9). Development currently uses Swift 6.4. The app deployment target is macOS 13.3. Apple silicon is the initial distribution target; Intel and the minimum OS still need runtime validation.

```sh
./scripts/build.sh
./scripts/run.sh
./scripts/check.sh
./scripts/check-speech.sh
```

`check.sh` runs deterministic core/layout assertions, planar and interleaved audio-channel isolation checks, a release build, signature integrity, plist validation, and a check for non-system runtime dependencies. `check-speech.sh` generates a synthetic English fixture using macOS speech synthesis, downloads Base English to a new cache, reopens it without allowing model downloads, and tests quiet rolling-window transcription. It needs internet and storage for another model cache; caches stay under `.build/` for inspection.

The Actions workflow builds on a [GitHub-hosted macOS runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). CI does not open the microphone or validate physical displays. Its artifact is an ad-hoc development build, not a public release.

## Source layout

| Target | Responsibility |
| --- | --- |
| `Prompter` | SwiftUI workspace, native windows, voice coordination, file dialogs |
| `PrompterCore` | Script library, transport, phrase matching, cadence, retake gate |
| `PrompterLayout` | Shared AppKit typography and reading-guide geometry |
| `PrompterCommands` | Optional local command-model download, integrity checks, and serialized llama.cpp inference |
| `CommandCheck` | Natural-language evaluation corpus and cached-model validation |
| `PrompterSpeech` | WhisperKit model lifecycle and single-channel Core Audio capture |
| `PrompterChecks` | Deterministic assertion runner without XCTest |
| `WhisperCheck` | Real-model transcription, downloads, and channel tests |

`Package.resolved` pins dependencies. Runtime models are downloaded separately and must not be committed. Do not commit personal scripts, audio, model caches, signing identities, provisioning material, or build output.

## Package a beta

Commit all changes first. The packaging script requires a clean checkout and records the source commit in `BUILD-INFO.txt`.

```sh
RELEASE_VERSION=0.1.0 ./scripts/package-release.sh
```

Output: `dist/releases/0.1.0/`, containing a versioned ZIP, SHA-256 checksum, and build information. The version's numeric part must match `scripts/Info.plist`. Without signing credentials, this is explicitly an **ad-hoc development package**. For explicitly approved early tester distribution, follow the separate tester process in [UPDATES.md](UPDATES.md). General distribution still requires signing and live acceptance.

The ZIP contains the application license and third-party notices. The matching Git tag and GitHub source archive provide the source for the distributed app.

## Sign and notarize

Distribution requires a Developer ID Application certificate with its private key and notarization credentials stored in the login keychain. An Apple Development certificate cannot substitute for it. See Apple's [Developer ID guide](https://developer.apple.com/developer-id/) and [notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Once configured locally, supply the identity name and keychain profile:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='StudioPrompter-notary' \
RELEASE_VERSION=0.1.0 \
./scripts/package-release.sh
```

The script enables hardened runtime with microphone access, submits the ZIP, staples the ticket, checks Gatekeeper, then rebuilds the ZIP and checksum. It stops on failure. Credentials and private keys never belong in source or release assets. This path must be exercised with an actual distribution identity before claiming a signed release.

## Publish

1. Complete the [release checklist](TESTING.md), including a clean-Mac launch of the exact candidate.
2. Commit any final changes; rerun checks and package that revision.
3. Create a version tag at the packaged commit. Never move an already published release tag.
4. Create or update the draft release with notes, ZIP, `SHA256SUMS.txt`, and `BUILD-INFO.txt`. Replace the ad-hoc ZIP with the notarized candidate and verify uploaded checksums.
5. Publish as a prerelease only when its required checks pass; update the README download status.

No workflow automatically publishes releases. A passing CI build alone is not release acceptance.

## In-app updater

Sparkle 2.10.0 is pinned in SwiftPM. `build.sh` embeds its framework and helper executables; Developer ID builds sign nested helpers before the enclosing framework and app. Development builds preserve Sparkle’s vendor signatures. The Sparkle signing key is not needed for ordinary builds or CI. See [UPDATES.md](UPDATES.md) for feed generation and the stable GitHub-release promotion workflow.

## Experimental command build (not shipped)

Normal builds exclude hands-free controls, wake-word handling, model interpretation, and the llama runtime from the app. To resume development testing explicitly:

```sh
STUDIO_EXPERIMENTAL_COMMANDS=1 ./scripts/run.sh
```

The packaging script refuses that flag. Run the next ordinary build without it to remove the embedded experimental runtime. `--voice-diagnostics` is honored only by experimental app builds; it prints rolling Whisper text and command decisions to stdout for an explicitly requested live test, including word timings while collecting commands. Do not use it with private speech or save/share its output inadvertently.

## Natural command interpretation (deferred experiment)

The fast command parser runs first. Only a settled, previously unconsumed request after **Hey Teleprompter** reaches the optional model. Qwen2.5-1.5B-Instruct Q4_K_M runs through the official llama.cpp b11053 XCFramework, embedded and signed with the app. Neither Ollama nor a separate server is required. `CommandModelStore` pins the publisher revision, byte size, and SHA-256. Downloads use temporary files and atomic installation; cached weights are verified before loading. Cancellation and retry are supported. Setup requires about 2.3 GB free disk space temporarily.

The model emits a grammar-constrained action object, then `CommandIntent` validates the object and request again. Line and relative paragraph counts are limited to 1–10. Absolute paragraph/cue indices are bounded to 1–999, with actual script bounds checked before navigation; exact font size is 32–90. Mode switching selects Follow script or Adaptive pace; “the other mode” uses the current app mode. Named source/destination phrasing and “following” are also supported. Appearance commands select the four built-in typefaces, adjust line spacing/margins/guide position by bounded steps, resize the reading guide within 1–3 lines, and show or hide the guide and focus effect. A request-specific grammar removes choices that conflict with explicit units, numbers, directions, or destinations, and post-validation checks the result again. Multiple actions, negation, and unsupported requests are declined. The model never receives the script, tools, file access, or general app automation. It is an intent classifier, not a general assistant.

Inference runs on an actor with a 2,048-token context, at most 32 output tokens, and a four-second deadline. Command collection permits up to twelve seconds for a longer utterance, preserving the beginning across Whisper windows. Visible wake phrases are separated from their command by token order so revised timestamps cannot drop early command words. A repeated fresh wake replaces an unfinished request. Out-of-window or invalid word timestamps are ignored. Obvious unfinished endings wait for more speech, and natural requests settle longer than fast commands. The UI holds prompting while interpreting and invalidates pending actions after manual repositioning, pause, mic stop, script changes, or disabling the feature. Whisper decoding waits during the short interpretation; audio capture and UI metering continue. Cancellation is checked between decode steps; Metal calls already in progress finish without applying stale results.

Run the evaluation and the synthetic speech integration separately from ordinary CI (both need downloaded weights):

```sh
swift build -c release --product CommandCheck
.build/release/CommandCheck '/path/to/qwen2.5-1.5b-instruct-q4_k_m.gguf'
.build/release/CommandCheck --cache-check "$HOME/Library/Application Support/Prompter/CommandModel"
swift build -c release --product WhisperCheck
.build/release/WhisperCheck --natural-commands '/path/to/qwen2.5-1.5b-instruct-q4_k_m.gguf'
```

The evaluation reports exact outcomes, conservative declines, and incorrect actions separately. The experimental acceptance threshold is at least 90% exact outcomes with zero incorrect actions **on the listed fixtures**; this is not a guarantee for arbitrary speech. Initial evaluation on an M5 Mac matched 46/48 fixtures: 26/28 intended actions, 20/20 expected refusals, and two conservative declines. Median model interpretation was about 0.36–0.42 seconds, excluding Whisper and the pause used to finish a command. These fixtures were also used during prompt development, so they are regression checks rather than an independent quality estimate. Real speaker testing and older-Mac latency/memory testing remain necessary.

Experimental app shutdown uses AppKit’s deferred termination reply: stop microphone/inference, cancel and await model preparation, unload the command model on its actor, then allow the process to exit. This avoids llama.cpp Metal resource assertions during global teardown.

Command wording keeps text layout separate from the reading guide: “line height” aliases line spacing (including “up the line height”), while “reading guide height” adjusts the highlighted area. Guide height supports one-line increases/decreases and explicit 1–3-line sizes; changing it preserves guide position and the reading anchor.


## Webcam Layout

`CameraPromptView` shares playback, script geometry, manual-retake handling, and voice status with the workspace. A floating, key-capable window supports local keyboard controls and dragging. Its initial guide position is near the webcam, then Webcam Layout keeps its own position for the session. Dragging is bounded by the canvas height and configured guide height, rather than a fixed top-of-screen percentage. These bounds do not depend on script progress: expansion around whole text lines is clipped at the viewport edge without moving the guide or text origin. Rendering and pointer hit testing share the same resolved position. Voice commands that move the guide address Webcam Layout while it is visible. The script's font, text layout, and progress mapping are unchanged.

`CGDisplayIsBuiltin` selects a built-in display when available; no model-name lookup is required. `NSScreen.safeAreaInsets.top` and `visibleFrame` keep initial placement below a notch/menu bar. The notch layout has a smaller initial footprint and gap than the plain-screen layout. Desktops fall back to the workspace display. Width/height are independently adjustable, and manual placement remains available on every device. Reopening during the session retains the window frame; re-centering uses the window's current display. Display changes reposition an open panel within a safe display frame.

The new line-height speech fixture exposed an empty Whisper decode caused by its first-token confidence cutoff. While collecting a command after a confirmed wake only, decoding now completes the utterance before applying the existing whole-segment confidence filter. Ordinary script recognition retains the original cutoff; the change does not add model downloads or temperature retries.

Webcam Layout is a mutually exclusive output choice alongside external monitors. `webcamLayoutActive` publishes window selection to the toolbar output menu and the preview status. Switching outputs closes the previous window without resetting playback. Native window close clears the selection; returning to producer controls keeps the webcam output active. Internal camera window identifiers and types are retained.

### Bookmark terminology

The UI calls saved script positions bookmarks. Existing `Cue`, `cues`, `studioprompter-cue` Markdown comments, and command action identifiers remain stable for file and action compatibility. The command prompt uses bookmark terminology; both bookmark and cue point remain accepted, with “book mark” normalized in command requests. No model weights or download changes are needed.
