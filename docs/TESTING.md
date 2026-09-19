# Beta validation and release gates

Candidate: **0.1.0-beta.1**, Apple silicon, macOS deployment target 13.

A green automated build is necessary, but does not establish comfortable live prompting or clean-machine installation. The first public download remains gated on the unfinished items below.

## Automated checks

| Area | Repeatable check | Current evidence |
| --- | --- | --- |
| Transport and persistence | `swift run PrompterChecks` | 181 assertions pass: countdown, frame independence, pause/end, library round-trip, legacy font migration, typeface persistence, corrupt-file preservation, Markdown migration/round-trip, emphasis, cue anchors, and rich-text round-trip |
| Speech matching and motion | Same runner | Skipped/filler words, unrelated speech rejection, recognition corrections, quiet-speech recovery logic, cadence smoothing, bounded motion, layout and focus geometry |
| Retake control | Same runner | Active playback preserved, countdown cancelled, old/far location rejected, scrolling-settle gate, fresh nearby match releases hold, explicit pause preserved |
| Input isolation | `swift run -c release WhisperCheck --channels` | Synthetic 20-channel planar/interleaved input: selected host channel reaches mono recognition, other channels remain silent, invalid channel rejected |
| First model setup | `./scripts/check-speech.sh` | Fresh Base English download, local preparation, cache detection, reopen with model download disabled, synthetic transcription |
| Real Whisper streaming | Same script | Quiet synthetic speech at −50 dB RMS, rolling eight-second windows; passage must reach its final eight words |
| Bundle | `./scripts/check.sh` | Release compilation, plist lint, code-signature integrity, only system runtime dependencies |
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

## Required before publishing the first downloadable beta

- [ ] Live reader acceptance of automatic retakes in both voice modes: backward scroll, fresh phrase resumes, repeated retakes, explicit Pause stays paused.
- [ ] Presenter/guest isolation with the intended Mac Studio and physical RØDECaster configuration; confirm channel choice and acoustic bleed behavior.
- [ ] Monitor unplug/reconnect and audio-device unplug recovery on the candidate build.
- [ ] Clean-account installation: permission denial/recovery, interrupted model download/retry, first launch, relaunch, and offline prompting after setup.
- [ ] Runtime validation on macOS 13 or raise the advertised minimum to the oldest validated version.
- [ ] Developer ID signature, successful notarization, stapled ticket, and Gatekeeper acceptance on the exact ZIP candidate.
- [ ] Download and open that candidate on a second Mac without development tools or an existing model cache.
- [ ] Attach matching source revision, ZIP, SHA-256 checksum, build metadata, and honest prerelease notes.

Small English is available as an optional model, but its live latency has not been accepted for this release. Base English remains the default. Intel builds, phone remotes, recording, and network collaboration are outside the first beta's validated scope.


## Script editor and Markdown storage

The core checks include Unicode emphasis and cues, Markdown escaping, legacy JSON migration with an unchanged backup, a metadata-only index, missing-script recovery, cue shifts after insertion/deletion, and bold/underline for all four display fonts. RTF import/export emphasis is checked as well. Before release, exercise the native editor’s selection formatting, typing and undo/redo, cue renaming/repositioning/removal, script switching, and relaunch persistence. Confirm formatting on the physical talent monitor and perform a voice-following pass with heavily emphasized text, since bold can change line wrapping.

Native smoke check (2026-09-19): selected bold + underline, cleared and restored emphasis with undo, deleted text before a cue and verified undo/redo, renamed/moved/removed a cue and undid the changes, reopened the library, jumped to the emphasized passage, and changed typeface through the expanded dropdown. All three original local scripts and their display settings were compared after migration and remained unchanged; the migration backup matched the original JSON byte for byte. Talent output was restored to the connected S24R35xFZ. A fresh spoken voice-following test remains a release gate.
