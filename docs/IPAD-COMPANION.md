# StudioPrompter Companion

A native iPad reading display for StudioPrompter on macOS. This is a development prototype, not part of the published 0.1.1 release and not yet distributed through TestFlight or the App Store.

## Pairing

1. Connect the iPad and Mac to the same local network and allow Local Network access on both devices. The Mac can use Wi-Fi or Ethernet on that network. Guest/public networks may isolate devices and prevent discovery; no internet connection is required.
2. On the Mac, choose **Prompter Output → Connect iPad…**.
3. Open **StudioPrompter Companion** on the iPad, enter the 12-character pairing code, and select the Mac.
4. Use the Mac's normal Play, Pause, scroll, bookmarks, typography, reading guide, mirror/flip, and blackout controls. Connection controls fade away after five seconds of inactivity. Tap the iPad display to reveal them or hide them immediately. Connection warnings remain visible while disconnected.

The Mac continues to own the script library and all voice processing. The iPad does not record audio or download speech models. Connection controls remain readable when script mirroring is enabled.

If the connection drops, the iPad holds the last received position and displays a connection warning. Tap **Reconnect** to resume at the Mac's current position. Returning from the background also requires reconnecting. **Disconnect** returns to setup and keeps the saved pairing. **Reconnect** resumes without a code. The companion remembers the Mac across app and device restarts and tries to reconnect when it discovers that Mac on launch. **Forget Mac** deletes the iPad’s saved pairing.

On the Mac, open **Prompter Output → Connect iPad…** to see paired iPads. **Remove iPad** revokes that device’s access. A connected device immediately receives “This iPad was removed by the producer. Pair again to reconnect.” If it was offline, it receives that message on its next authenticated connection. A Mac that is offline or has stopped iPad output produces an unavailable message instead; the iPad cannot know about removal until it reaches the Mac.

The Mac remembers paired devices and removals across restarts and starts the connection service when it has saved records. Stopping output keeps the pairings. Removal changes the enrollment code, so the removed iPad needs the new code to pair again; other devices keep their own credentials.

## Development build

Requires full Xcode with iOS support, an Apple development signing identity, and Developer Mode enabled on a physical iPad. The deployment target is iPadOS 16.0. Open `iPad/StudioPrompterCompanion.xcodeproj`, select the app target's signing team, choose the attached iPad, and run. Local signing details are not committed.

The project is generated from `iPad/project.yml` using XcodeGen. After changing that specification, run:

```sh
xcodegen generate --spec iPad/project.yml
```

An unsigned compile check:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project iPad/StudioPrompterCompanion.xcodeproj \
  -scheme StudioPrompterCompanion -destination 'generic/platform=iOS' \
  -derivedDataPath .build/ipad-check CODE_SIGNING_ALLOWED=NO build
```

Build the matching Mac app with `./scripts/build.sh` (add `STUDIO_EXPERIMENTAL_COMMANDS=1` to include the optional voice-command feature).

## Connection design

- Bonjour discovery and Network.framework TCP with peer-to-peer Wi-Fi enabled. Same-network operation is the initial test path; this is not a Bluetooth implementation.
- TLS with an enrollment code for initial pairing and a distinct random 256-bit credential for each paired iPad. Device authorization happens before script delivery. Only one iPad receives the feed at a time; other known devices can still connect to receive access/status messages.
- The Mac sends script text, emphasis, settings, and precomputed line breaks when they change; small playback updates follow at 20 Hz.
- The iPad draws locally and interpolates motion with a 100 ms buffer. It never extrapolates indefinitely through a dropped connection.
- Framed messages have an 8 MiB limit; document geometry, text ranges, revisions, and playback values are checked before rendering.
- Credentials and removal records live in private local application storage, outside script exports and backups. The Mac files and atomic replacements are owner-readable/writable only; iPad files also use its application sandbox and data protection. No cloud account or internet relay. Removed records retain the key needed to deliver an authenticated removal notice, but never authorize a script.

## Verification

`swift run -c release PrompterLinkChecks` checks framing limits, unsafe document rejection, motion interpolation/retakes/freeze, encrypted transfer of a large Unicode script with playback state, rejection of an incorrect pairing code, final-message delivery on close, persistence across restarts, offline revocation, unaffected second-device access, and invalidation of old enrollment codes. The native iPad and matching Mac targets have compiled locally. The companion has been installed and launched on a 10th-generation iPad running iPadOS 26.6.1; the Mac reports a live paired connection. The existing 462 playback, persistence, speech-alignment, and cadence assertions also pass.

The tester has confirmed live prompting, horizontal mirroring, vertical flipping, bookmark jumps, and reconnection to the current Mac feed after a Wi-Fi interruption on the physical iPad.

The durable-pairing protocol replaces the initial session-only prototype, so upgrading that prototype requires one new pairing. The current Mac and iPad builds must be installed together.

Both apps were restarted on the physical Mac/iPad pair and reconnected without a code. The tester also confirmed the removal message after the companion was closed, removed on the Mac while offline, and reopened. Before distribution, check portrait/landscape legibility, emphasis and guide alignment, smooth playback, manual retakes, bookmarks, mirroring/flip, blackout, reconnect, and background/foreground behavior. Also test denied Local Network permission and networks that isolate Wi-Fi clients. Peer-to-peer discovery without a shared router remains unverified.
