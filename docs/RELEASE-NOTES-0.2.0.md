# StudioPrompter 0.2.0 · Your iPad joins the studio

Keep the producer controls on your Mac and put the script on an iPad with **StudioPrompter Companion**.

## New in this tester release

- **iPad output:** choose **Prompter Output → Connect iPad…**, then pair the companion on the same local network. The Mac sends text and playback position over an encrypted connection; the iPad renders the script locally.
- **Your familiar controls:** scrolling, bookmarks, typography, reading guide, horizontal mirroring, vertical flipping, and blackout carry through to the iPad.
- **Pair once:** the companion remembers its Mac across app and device restarts. Disconnect keeps the pairing; Reconnect resumes at the Mac’s current position.
- **Producer access controls:** Remove iPad revokes a saved device. Even an iPad that was offline learns why it cannot reconnect when it next reaches the Mac.
- **A clean reading display:** the iPad’s controls fade out after five seconds. Tap to bring them back; connection warnings stay visible.
- **Connection guidance:** setup explains the same-network requirement and how guest networks can block discovery. A dropped connection holds the script in place rather than continuing to scroll.

All 0.1.1 features remain, including Webcam Layout and experimental “Hey Teleprompter” commands. Speech recognition, microphone/channel selection, and command processing stay on the Mac.

## Compatibility and availability

- Mac: Apple silicon, macOS 13.3 or later; the oldest supported OS still needs runtime verification.
- Companion: iPadOS 16 or later, with the matching durable-pairing protocol. The companion is in internal TestFlight testing and is not included in this Mac ZIP. External invitations are not available yet.
- The original temporary-pairing prototype requires one new pairing after both apps are updated.
- One iPad receives the live feed at a time. Use the same local network; router-free peer-to-peer operation has not been validated.

## Tester status

This is an early tester prerelease, not a production release. Live tests have covered iPad prompting, mirror/flip, bookmark jumps, Wi-Fi recovery, app restarts without re-pairing, and offline device removal. Automated checks cover persistence, authorization, transport framing, and removal notices. Longer-session smoothness and fresh-machine setup remain part of beta testing.

The initial package uses an ad-hoc Mac signature and is not Apple notarized. Existing testers use **StudioPrompter → Check for Updates…** to install this release; scripts, bookmarks, downloaded models, and saved device pairings remain outside the app bundle.
