# StudioPrompter 0.1.1 · Webcam Layout & hands-free commands

A simpler output workflow for solo creators, with smoother script following and experimental local voice commands.

## What’s new

- **Webcam Layout:** a compact floating prompter near your camera, with adjustable width, height, position, and reading guide. Placement accounts for built-in displays and camera notches; external webcams can be aligned manually.
- **One output menu:** choose Webcam Layout or a connected monitor from **Prompter Output**. Removed the duplicate sidebar dropdown and rehearsal window. Mirror and flip controls appear only for external output.
- **Smoother following:** completed lines bring the next words into the focus area sooner, and placing the webcam guide at the bottom no longer shifts the script between lines. Resize controls stay stationary while you adjust the window.
- **Bookmarks:** the friendlier name for cue points. Existing saved positions carry over automatically.
- **Experimental “Hey Teleprompter” commands:** hands-free start/pause, navigation, bookmarks, and appearance adjustments. Enable Voice prompting and Hands-free commands to listen; say the wake phrase, give a command, and briefly pause. Pause keeps listening for commands; Esc stops the microphone.
- **Optional local command AI:** enable **Natural commands · Beta** in Advanced voice settings and choose **Download command AI** for flexible phrasing. The approximately 1.1 GB model downloads within the app and runs locally afterward. Clear commands can also use the built-in parser.

Commands remain experimental: ambiguous requests, background speech, and recognition errors can produce missed or incorrect actions. Keep the selected microphone isolated and verify the on-screen response. This is a tester release, not a general-production release.

## Update or install

Existing testers: pause prompting, stop the microphone, then choose **StudioPrompter → Check for Updates… → Install Update → Install and Relaunch**. Checks are manual. Your script library and downloaded models remain on your Mac.

New testers: download **StudioPrompter-0.1.1-macos-arm64.zip**, unzip it, and move **Prompter.app** to Applications. It appears as **StudioPrompter**. This build is ad-hoc signed and **not Apple notarized**; first launch may require **System Settings → Privacy & Security → Open Anyway**. [Apple’s instructions](https://support.apple.com/en-us/102445).

Requires **Apple silicon (M1 or newer), macOS 13.3+**. Intel is not supported. Minimum-OS hardware and 8 GB command-model performance still need broader testing. English speech models are offered; Base English is the default.

Audio and command processing stay on your Mac. Audio and transcripts are not saved during ordinary use. Models download separately; no cloud transcription account is required.

See [testing evidence and remaining checks](https://github.com/codebooker/StudioPrompter/blob/main/docs/TESTING.md). The ZIP’s SHA-256 checksum, exact source revision, build details, and signed update feed are attached below.
