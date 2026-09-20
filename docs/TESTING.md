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

## Command experiment, second pass (not published)

The command contract now distinguishes relative paragraph movement, absolute paragraph/cue numbers, the last paragraph, exact font size, and prompting-mode changes. The model receives a request-specific grammar: only actions consistent with explicit units, counts, directions, and destinations are offered, along with `unknown`. A separate post-validation step still checks the output. The app rejects nonexistent numbered destinations instead of navigating to a different one. “Stop for now” pauses with command listening available; explicitly stopping listening turns off the microphone.

Whisper's `Q point`, `Q-point`, and `Qpoint` spellings normalize to cue point. Active command collection can extend beyond six seconds, with a twelve-second hard cap. Timestamped prefix retention keeps the start of a command when it leaves Whisper's rolling window; overlapping hypotheses replace earlier words so corrections can settle before execution.

The expanded text regression corpus includes the recorded failure phrases plus unrelated/ambiguous/negated requests. It is used during development and is not an independent estimate of real-world accuracy. Synthetic spoken fixtures additionally cover counted paragraphs, paragraph ten, cue two, exact font size, mode switching, and stopping while keeping listening available. Repeat the original live pass before considering release promotion.

Second-pass development checks: 336 deterministic assertions passed, the expanded local-model text corpus matched 69/69 cases with zero incorrect actions (median approximately 0.38 seconds), and all 20 synthesized Whisper-to-command fixtures passed. Ordinary release checks confirmed the experiment is still excluded; the opt-in experimental app compiled and signed successfully. The live pass below followed those development checks.


## Command experiment, third pass (not published)

The second live pass on 2026-09-19 successfully executed counted/numbered paragraph navigation, first/second cue selection, exact font sizes, full-name mode switching, and pause/resume. No incorrect executed action was observed during that pass, but several requests were declined or timed out. Short pauses caused incomplete instructions to be submitted; repeated wake phrases sometimes remained in the request; mode aliases and polite “go ahead and” were too strict. Appearance requests were unsupported. This is observational testing, not a measured false-activation rate.

A synthetic pause fixture also exposed Whisper words timestamped more than 25 seconds beyond the available audio, including `[BLANK_AUDIO]` padding. Command routing now ignores non-finite, inverted, negative, or future word times rather than allowing them to extend the command deadline.

The third revision adds timing/retry regressions, contextual Whisper aliases, polite-prefix handling, prompting-mode aliases, and bounded appearance actions. Appearance changes preserve the reading anchor and current play/pause state. Actual compound/negated commands still decline. Synthetic speech includes 1.5-second pauses after “go back up” and “switch from adaptive pace to.”

Quitting the second-pass app with the local command model loaded produced a llama.cpp Metal resource assertion. The third revision defers application termination until cancelled preparation and model unloading finish. Native checks passed on the development Mac: quitting with “Command AI ready · offline” visible exited with status 0; quitting immediately after “Preparing command model…” appeared also exited with status 0. The app reopened successfully after both checks.

Third-pass automated results: 378 deterministic assertions passed; the local-model corpus matched 97/97 cases with zero incorrect actions (median approximately 0.48 seconds, excluding Whisper and end-of-command settling); all 30 synthetic speech fixtures passed, including both mid-command pauses. These remain development regression fixtures. Another live presenter pass is required to accept timing and natural phrasing.

Ordinary release checks passed after these changes, including exclusion of command activation and the llama runtime. The experimental bundle built, signed, and reopened successfully. The microphone remained off during model shutdown checks.

### Guide-height and line-height wording follow-up

The command contract now supports guide-height increases/decreases and exact 1–3-line heights. “Line height” maps to text line spacing; “reading guide height” maps to the reading area. Regression fixtures include the presenter’s variants: “increase the line height,” “increase the line height a little bit,” “up the line height,” “can you make the line height bigger,” “increase the reading guide height,” and “make the reading guide bigger.” Checks reject wrong-control substitutions, movement interpreted as sizing, and unsupported guide heights.

Follow-up results: 420 deterministic assertions passed; all 120 local-model text cases matched with zero unexpected actions; all 39 synthetic speech cases passed. Ordinary release checks and the signed experimental build passed. The first-token confidence cutoff is relaxed only while collecting a command after a confirmed wake phrase; ordinary script transcription retains its existing cutoff and segment/word filters still apply.

### Camera view (development build)

The compact floating window shares script progress and controls with the producer workspace. Geometry checks cover notched built-in screens, notch-free external screens with negative coordinates, and constrained screen sizes. The initial placement uses the built-in screen when available and respects its camera safe area. Width and height are independent; a native drag handle allows placement beneath an external webcam, and a center button restores top-center placement on the current screen.

Native checks on the MacBook passed for opening Camera view, displaying the current script and microphone state, and changing the width/height from 580×240 to 360×180 using the sliders. The compact footer remained readable at the minimum size. The presenter began hands-free playback during this check, so further UI automation was stopped to avoid interrupting that pass. Native drag/recenter, reopen retention, and external-webcam placement remain live acceptance checks; external hardware was disconnected. Camera view and these command changes have not been published as a release.

### Camera resizing follow-up

The presenter’s screen recording showed the SwiftUI size popover moving with the camera footer and flipping above it while resizing. Replaced the anchored popover with an independent native utility panel, positioned once when opened. Changing the camera frame does not reposition the controls. Closing Camera view also closes its size panel.

The experimental build and bundle signature checks passed. Native accessibility slider checks exercised 1000×600 and 360×180, then restored 580×240. Window-server bounds confirmed that the controls stayed at exactly the same origin and size throughout while Camera view changed size. Done returned focus to Camera view. Continuous physical pointer dragging still needs the presenter’s acceptance pass; the automated coordinate drag did not reliably target the utility panel. No speech-processing or published-release changes are included in this fix.

### Completed-line handoff

A live reader reported stopping after “the tiny things that change everything” in both Camera view and the producer workspace. A layout regression using that paragraph, the presenter’s 58-point font/1.3 line spacing/11% margins, and a one-line guide reproduced the problem: even a correct match on “everything” left the next unread line outside the focus band. All three viewport checks failed before the fix.

The last recognized word of each rendered line now targets the beginning of the next line minus the existing half-line offset. Earlier word targets remain unchanged; movement still uses the existing damped follower and holds without a new target. This also covers one-word lines and paragraph spacing. All 436 deterministic assertions pass, including the reported paragraph at producer, standard Camera view, and minimum Camera view dimensions; the next line becomes fully highlighted and remains visible without requiring speech from outside the guide. A quiet synthetic Whisper streaming check recognized the passage through word 40/40 (“everything”). Live-reader acceptance remains separate from these regression checks.

### Bookmark terminology

Renamed visible cue-point labels to bookmarks throughout the sidebar, editor, transport tooltips, menu commands, help, undo descriptions, and voice feedback/examples. Saved marker identifiers, offsets, JSON fields, and Markdown comment format are unchanged. Existing cue-point commands remain aliases. The fast parser accepts bookmark navigation, request normalization handles “book mark,” and the local model prompt names bookmarks explicitly.

Validation: 442 deterministic assertions passed; all 130 local-model text cases matched with zero unexpected actions; four synthetic Whisper-to-command bookmark cases each executed exactly once (previous, next, number two, first). The experimental app built and passed signature verification. Native checks confirmed the new sidebar/editor/menu labels and both existing Test Script bookmarks, with all four scripts still present. Microphone remained off during UI checks.

Live follow-up on the MacBook (2026-09-19, build from `41a8845`): started Follow script at “But most are small. These little choices…” with Base English, System default / Channel 1, reading lead zero, font 58, and a one-line guide. The presenter opened Camera view and read through the previously stalled “the tiny things that change everything” transition. Observations showed continued movement into “routine. How you start your day…” and then “may feel calmer. This calmness can stay with you all day.” Asked whether new words entered the focus area soon enough without rushing, the presenter answered “Yes, that felt right.” Playback was paused and Microphone off verified afterward. This accepts that passage in Camera view on this MacBook; it is not a general accuracy or external-display timing guarantee.

### Camera guide movement

Removed the fixed 3.75–16.25% Camera view guide range and inverse mapping into the main window’s setting. Camera view now holds its own guide position. Its available range is calculated from canvas height and the actual reading band, including expansion to complete text lines. Rendering and drag hit testing use the resolved position; oversized guides align at the top until more space is available. Main/talent guide limits are unchanged.

All 450 deterministic assertions passed, including lower-edge fitting, taller windows, expanded line bands, and oversized/empty viewport cases. The experimental app compiled and its bundle signature verified. Native inspection showed the guide below the former limit in Camera view with the microphone off. UI interaction was interrupted by concurrent user resizing; remaining drag feel is subject to the presenter’s live feedback.


### Bottom-edge Camera guide motion

The presenter reported jerky movement between lines with the guide at its lowest position. The previous fitting calculation used the focus band expanded around moving text lines. When the set of highlighted lines changed, it changed the allowed guide position and therefore shifted the entire text origin. The range now depends only on viewport and configured guide geometry. Whole-line highlighting is clipped to the camera viewport without feeding back into scroll positioning.

All 462 deterministic assertions passed. The new motion regression exercises actual AppKit line layout across three viewport heights and two guide heights, verifies that focus-band line boundaries are crossed, and checks that the guide remains stationary while the text advances by the requested amount each frame. The experimental app built and passed bundle signature verification. It reopened successfully after a Finder “application is not open anymore” alert during the rebuild; no newer crash report was found. Native inspection showed playback with the guide near the lower edge and microphone off. Concurrent presenter interaction interrupted the automated drag, so smoothness acceptance remains with the presenter. No release was published.


### Unified prompter output selection

Renamed Camera view to Webcam Layout throughout the visible controls, menus, window title, accessibility labels, and guide-command feedback. Removed the separate toolbar button. The top-right Prompter Output dropdown lists Webcam Layout alongside external monitors, marks the active choice, and offers Stop output for either destination. Switching destinations closes the previous output without resetting playback; returning to producer controls keeps Webcam Layout open. Native window closure also clears its selected state.

The experimental build and bundle signature verification passed. Native checks confirmed selection from the top-right dropdown, the renamed window and footer, an active checkmark, synchronized workspace/inspector status, returning to producer controls with the output retained, and Stop output clearing the selection. Microphone stayed off. A physical monitor was disconnected, so live switching between monitor and webcam outputs remains a hardware acceptance check. No release was published.


### Rehearsal window removal

Removed the redundant rehearsal output from Prompter Output and the Prompt menu, including its Command-Shift-P shortcut and unused window/view implementation. The producer preview supports practice, and Webcam Layout provides the compact solo-reading output. Current help and keyboard documentation now describe those paths. Historical release notes retain their original descriptions.

Validation: the experimental app compiled, passed bundle signature verification, and reopened. Native inspection confirmed the rehearsal entry is absent from both the output dropdown and Prompt menu; Webcam Layout remains available. The microphone stayed off. No release was published.


### Single output selector

Removed the duplicate sidebar output dropdown, status/Stop row, and instructional copy. Output selection and stopping remain in the top-right Prompter Output menu; mirror and flip retain a dedicated sidebar section. The experimental app built and passed signature verification. Native inspection of the reopened workspace confirmed exactly one output dropdown and both mirror/flip controls.
