# Development and releases

## Build

Use a recent Swift toolchain or Xcode on macOS. Use Swift 6.0 or newer for the pinned dependency graph (the app manifest itself declares Swift tools 5.9). Development currently uses Swift 6.4. The app deployment target is macOS 13. Apple silicon is the initial distribution target; Intel and the minimum OS still need runtime validation.

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
| `PrompterSpeech` | WhisperKit model lifecycle and single-channel Core Audio capture |
| `PrompterChecks` | Deterministic assertion runner without XCTest |
| `WhisperCheck` | Real-model transcription, downloads, and channel tests |

`Package.resolved` pins dependencies. Runtime models are downloaded separately and must not be committed. Do not commit personal scripts, audio, model caches, signing identities, provisioning material, or build output.

## Package a beta

Commit all changes first. The packaging script requires a clean checkout and records the source commit in `BUILD-INFO.txt`.

```sh
RELEASE_VERSION=0.1.0-beta.1 ./scripts/package-release.sh
```

Output: `dist/releases/0.1.0-beta.1/`, containing a versioned ZIP, SHA-256 checksum, and build information. The version's numeric part must match `scripts/Info.plist`. Without signing credentials, this is explicitly an **ad-hoc development package**. Keep it in a draft release while distribution and live acceptance gates are outstanding.

The ZIP contains the application license and third-party notices. The matching Git tag and GitHub source archive provide the source for the distributed app.

## Sign and notarize

Distribution requires a Developer ID Application certificate with its private key and notarization credentials stored in the login keychain. An Apple Development certificate cannot substitute for it. See Apple's [Developer ID guide](https://developer.apple.com/developer-id/) and [notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Once configured locally, supply the identity name and keychain profile:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='StudioPrompter-notary' \
RELEASE_VERSION=0.1.0-beta.1 \
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
