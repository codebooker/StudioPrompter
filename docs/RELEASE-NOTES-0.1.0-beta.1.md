# StudioPrompter 0.1.0 beta 1

A native macOS teleprompter for producers and presenters: keep the controls on one display and the script on another.

## In this beta

- Clean, synchronized talent output with mirroring, flipping, and blackout.
- A local script library, text/document import, editor, and cue points.
- Adjustable typography, reading guide, and focus highlighting.
- Local Whisper voice prompting: Follow script and Adaptive pace.
- Main-window microphone and channel selection, one-click model download, and unified Play/Pause.
- Automatic retake hold: manually scroll during active voice prompting, then read from the new position to resume following.

## Candidate status — do not publish yet

This draft contains an **Apple silicon development package**. It is ad-hoc signed, **not Developer ID signed or notarized**, and is not ready for friction-free installation on other Macs. Replace it with the notarized candidate before publication.

Automated checks cover transport, persistence, matching, cadence, retake gating, typography, and audio-channel isolation. Real Base English download and synthetic streaming checks are included in the repository. Live retake acceptance, physical mixer routing, clean-Mac installation, minimum-OS validation, and signing remain release gates. See [the complete checklist](https://github.com/codebooker/StudioPrompter/blob/main/docs/TESTING.md).

## Requirements and data

The candidate is arm64 only. The declared minimum is macOS 13; minimum-version runtime testing is still pending. Voice prompting currently supports English. Initial setup downloads model/tokenizer files; recognition subsequently runs locally. Audio and transcripts are not saved by the app.

Base English is the default. Small English is optional and may introduce more latency. Voice prompting remains experimental; test it with your delivery and microphone before a production session.

`SHA256SUMS.txt` verifies the ZIP. `BUILD-INFO.txt` identifies its exact source commit and signing status. Source is available under AGPL v3; third-party notices ship inside the app.
