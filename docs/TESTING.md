# Beta validation and release gates

Tester release: **0.1.0**, Apple silicon, macOS deployment target 13.3.

A green automated build is necessary, but does not establish comfortable live prompting or clean-machine installation. The owner has chosen to distribute an early, non-notarized tester build. The unfinished items below remain requirements before declaring the app ready for general production use; they are not claimed as completed by this tester release.

## Automated checks

| Area | Repeatable check | Current evidence |
| --- | --- | --- |
| Transport and persistence | `swift run PrompterChecks` | 289 assertions pass: countdown, frame independence, pause/end, library round-trip, legacy font migration, typeface persistence, corrupt-file preservation, Markdown migration/round-trip, emphasis, cue anchors, and rich-text round-trip |
| Speech matching and motion | Same runner | Skipped/filler words, unrelated speech rejection, recognition corrections, quiet-speech recovery logic, cadence smoothing, bounded motion, layout and focus geometry |
| Retake control | Same runner | Active playback preserved, countdown cancelled, old/far location rejected, scrolling-settle gate, fresh nearby match releases hold, explicit pause preserved |
| Input isolation | `swift run -c release WhisperCheck --channels` | Synthetic 20-channel planar/interleaved input: selected host channel reaches mono recognition, other channels remain silent, invalid channel rejected |
| First model setup | `./scripts/check-speech.sh` | Fresh Base English download, local preparation, cache detection, reopen with model download disabled, synthetic transcription |
| Real Whisper streaming | Same script | Quiet synthetic speech at −50 dB RMS, rolling eight-second windows; passage must reach its final eight words |
| Bundle | `./scripts/check.sh` | Release compilation, plist lint, code-signature integrity, system libraries and embedded Sparkle only |
| GitHub build | Actions: Build and checks | Runs core/layout/channel/bundle checks on a hosted macOS runner; review the run linked from the README |

The speech fixture is generated locally; no microphone recording is committed. Synthetic speech is not a substitute for live testing. Cached reopen with downloads disabled is not a network-disconnection test.

## Live testing already performed

Development hardware: Apple silicon Mac with an S24R35xFZ secondary display.

- Producer and talent display separation confirmed by the user.
- Manual wheel/drag/keyboard positioning, playback, guide positioning, and focus layout exercised.
- Follow script tested with changes in speaking speed and skipped words; the user reported improved following.
- Adaptive pace retested after slowing acceleration and adding script-position guardrails; the user reported improved comfort.
- Main-window voice controls and one-click model setup implemented; header voice-settings duplication removed.
- Candidate UI smoke check: manual scroll in each voice mode retained the active microphone and showed the retake hold; explicit Pause followed by scrolling kept the mic off. Fresh-phrase resumption still requires live reader acceptance.

These observations describe this development setup, not every supported Mac or audio interface.

## Outstanding before general production release

- [ ] Live reader acceptance of automatic retakes in both voice modes: backward scroll, fresh phrase resumes, repeated retakes, explicit Pause stays paused.
- [ ] Presenter/guest isolation with the intended Mac Studio and physical RØDECaster configuration; confirm channel choice and acoustic bleed behavior.
- [ ] Monitor unplug/reconnect and audio-device unplug recovery on the candidate build.
- [ ] Clean-account installation: permission denial/recovery, interrupted model download/retry, first launch, relaunch, and offline prompting after setup.
- [ ] Runtime validation on macOS 13.3 or raise the advertised minimum to the oldest validated version.
- [ ] Developer ID signature, successful notarization, stapled ticket, and Gatekeeper acceptance on the exact ZIP candidate.
- [ ] Download and open that candidate on a second Mac without development tools or an existing model cache.
- [ ] Attach matching source revision, ZIP, SHA-256 checksum, build metadata, and honest prerelease notes.

Small English is available as an optional model, but its live latency has not been accepted for this release. Base English remains the default. Intel builds, phone remotes, recording, and network collaboration are outside the first beta's validated scope.


## Script editor and Markdown storage

The core checks include Unicode emphasis and cues, Markdown escaping, legacy JSON migration with an unchanged backup, a metadata-only index, missing-script recovery, cue shifts after insertion/deletion, and bold/underline for all four display fonts. RTF import/export emphasis is checked as well. Before release, exercise the native editor’s selection formatting, typing and undo/redo, cue renaming/repositioning/removal, script switching, and relaunch persistence. Confirm formatting on the physical talent monitor and perform a voice-following pass with heavily emphasized text, since bold can change line wrapping.

Native smoke check (2026-09-19): selected bold + underline, cleared and restored emphasis with undo, deleted text before a cue and verified undo/redo, renamed/moved/removed a cue and undid the changes, reopened the library, jumped to the emphasized passage, and changed typeface through the expanded dropdown. All three original local scripts and their display settings were compared after migration and remained unchanged; the migration backup matched the original JSON byte for byte. Talent output was restored to the connected S24R35xFZ. A fresh spoken voice-following test remains a release gate.

## In-app update checks

`check.sh` validates the embedded Sparkle helpers and runs `test-update-feed.py`. Release promotion additionally verifies the archive’s Ed25519 signature before extraction, Apple code signing, stapled notarization, and Gatekeeper acceptance. Test the menu’s busy-state gating, no-update result, network failure, cancellation, and a full Install & Relaunch between two signed/notarized builds before public distribution. Preserve the user’s library and model cache throughout. See [UPDATES.md](UPDATES.md).

Development check (2026-09-19): the native update window read the public GitHub feed and reported the installed version up to date. The menu command was disabled during playback and enabled again when paused. Sparkle generated an appcast signed with the release Mac’s Keychain key; verification against the app’s pinned public key accepted the original archive and rejected a same-size tampered copy. The automated cryptographic self-test also rejects truncation and the wrong signing key. These checks used a local development archive; full signed/notarized installation, cancellation, and network-failure testing remain outstanding.


## Deferred experiment: hands-free commands (excluded from release)

The core checks cover the complete wake phrase, rejection of shorter/interrupted phrases, bounded command parsing, negation and extra-instruction rejection, partial windows, revised recognition, repeat suppression, fresh repeated commands, activation cutoffs, silence/timeout handling, and rendered-line/paragraph/cue destinations. `swift run -c release WhisperCheck --commands` uses synthesized audio with the actual local Base English model in rolling windows; navigation, paragraph restart, and font-size commands each execute once, while the short wake phrase and ordinary conversation execute none. It never opens the microphone.

Before release, test a live presenter with the selected microphone in both Follow script and Adaptive pace: wake detection and response time, pause/resume, commands at script end, repeated retakes, font reflow, cue boundaries, noise and guest speech, unknown commands, Stop listening/Esc, and mirrored talent feedback. The full wake phrase is “Hey Teleprompter”; the originally considered product-name phrase was misrecognized in the synthetic speech test. Synthetic success does not establish a live false-activation rate.

Native smoke check (2026-09-19): enabled Hands-free commands, started microphone-only listening while paused, played and paused without stopping capture, and confirmed Stop listening returned to Mic off. The right panel shows the wake phrase and command examples. Live speaker recognition and command feedback on the talent display still require presenter acceptance.

### Deferred natural commands experiment

- [ ] On a clean Mac, download command AI with the app button, cancel partway, retry, then relaunch and use it with the network disconnected.
- [ ] Say “Hey, Teleprompter” plus varied requests, including corrections, incomplete commands, background conversation, unsupported actions, and negation.
- [ ] Manually scroll, pause, switch scripts, turn off Natural commands, or stop the mic while “Understanding your command…” is visible; no late action should execute.
- [ ] Check model warmup, sustained prompting, RAM pressure, and interpretation latency on an 8 GB Apple silicon Mac and the oldest supported macOS version.
- [ ] Verify visible confirmations on the talent output, including mirroring and blackout. Neither download nor model interpretation should modify the script text.

## First tester release scope

Ordinary builds compile out command activation, interpretation, and both command settings panels. The command AI runtime is absent from the app bundle and executable dependencies; the packaging script rejects experimental builds. Follow script and Adaptive pace still use local Whisper. The opt-in speech trace is disabled in ordinary builds.

Live command testing on 2026-09-19 found incorrect actions for paragraph counts and numbered cues, false refusals, and “Q point” transcription rejected by validation. Those findings supersede the narrow command fixture benchmark as release evidence. Commands are deferred until their action schema and live behavior are improved.

Tester updates use a separate feed. Promotion verifies the downloaded archive against the pinned Ed25519 key before extraction, then checks app signature integrity, identity, versions, and feed URL. Tester promotion permits non-notarized prereleases; stable promotion still requires notarization and Gatekeeper acceptance.

### 0.1.0 tester release evidence · 2026-09-19

- Release source: `a7df6af77dc446d14d07c75b162dbbca4ac78b96`, build 3. [Hosted CI passed](https://github.com/codebooker/StudioPrompter/actions/runs/35467691204); 289 deterministic assertions, channel isolation, bundle checks, feed validation, and cryptographic tamper rejection passed locally as well.
- Fresh Base English download, cached reopen with downloads disabled, and quiet rolling-window speech following passed again.
- Native release UI: hands-free controls and command AI setup absent in both panels. Play starts local Whisper; Pause returns to Mic off. The shipped bundle has no llama framework or command activation/interpretation entry points.
- The public ZIP was downloaded without GitHub authentication; its SHA-256 matched the uploaded checksum, and its Ed25519 signature verified against the app’s pinned key.
- [Automatic tester-feed promotion passed](https://github.com/codebooker/StudioPrompter/actions/runs/35467862234).
- Full local update smoke test: a separate app copy marked 0.0.9/build 2 detected the published 0.1.0/build 3 through the public tester feed. **Install Update → Install and Relaunch** downloaded the GitHub archive and replaced the app successfully. The resulting binary matched the release binary, code-signature verification passed, and all four existing Markdown scripts retained identical content hashes. The existing Whisper cache remained in place.

This establishes the update path on the development Mac, using a deliberately older version label, not two independently shipped releases. It does not establish first-launch Gatekeeper approval, microphone permission recovery, or installation on the friend’s Mac. Those are still tester acceptance items.
