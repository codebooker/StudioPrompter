# StudioPrompter user guide

## Two-screen setup

Use an extended desktop in macOS Display settings. Keep the producer workspace on your primary display, then choose **Send to display** and select the talent monitor. Both screens share a script position and line wrapping. Talent output is borderless; the main window retains standard macOS window controls.

Mirror and flip affect only talent output and the rehearsal window. **B** blacks out the talent monitor while leaving the producer preview visible. Stop output from the right panel or the Prompt menu. Disconnecting the selected display closes its output and pauses playback.

With one monitor, use **Open Rehearsal Window** to inspect the talent view.

## Reading and retakes

Choose System, Avenir Next, Verdana, or Georgia in the right panel. Avenir Next uses a medium weight; Verdana offers wider letter shapes. Typeface choices save per script and apply to both displays. Adjust size, line spacing, and margins below the typeface picker. Move the reading guide with its orange arrow or the Guide position slider; Guide height covers one to three lines. Focus highlighting includes complete intersecting lines.

Scroll the producer preview with a wheel or trackpad, drag it, use the position slider, or press the arrow keys. In fixed-speed mode, this pauses automatic playback.

During active voice prompting, manual movement keeps the microphone on. After scrolling settles, **Ready for retake—read from here** appears. Read a short phrase from the new reading area; the app discards speech buffered before the move and resumes once it finds your place. Both Follow script and Adaptive pace use this retake hold. A single common word is not enough to release it. Pause, Reset, reaching the end, and changing scripts stop the mic. Scrolling while paused does not start listening.

Use Follow script when wording matters. Adaptive pace is useful when delivery varies, but it can continue by cadence when a fresh script match is unavailable. Silence and stale recognition hold movement. Both modes remain experimental; use manual control whenever needed.

## Microphones and mixers

Turn on **Voice prompting**, select the mode, microphone, and input channel. If the device exposes multiple channels, select one explicitly. The meter and speech engine receive that same channel. Device/channel controls are locked while listening; pause to change them.

For an interview, route the host's isolated microphone to a USB input channel and select it in the app. Have the host speak, then the guest, and check the meter. A combined stereo mix will include both people. Channel isolation does not remove acoustic bleed into the host's microphone.

For a RØDECaster Pro II, enable USB multitrack and use its current channel map. Do not assume a numbered channel always corresponds to a particular microphone; routing depends on mixer configuration and firmware. See RØDE's [multitrack setup](https://help.rode.com/hc/en-us/articles/6790371865359-How-to-Setup-Multitrack-with-the-R%C3%98DECaster-Pro-II-Duo) and [channel layout](https://help.rode.com/hc/en-us/articles/15412830674959-The-R%C3%98DECaster-Pro-II-Duo-Multitrack-Channel-Layout).

## Model setup

Click **Download model** in the main panel. Leave the app open while files download and prepare locally. Initial preparation can take longer than subsequent starts. If setup fails, check internet access and free disk space, then choose **Retry setup**.

Base English is the default. Advanced voice settings offers only Base English and Small English; switching to an uninstalled model requires its own download. Model selection and tuning are session-only in this beta.

Play starts the selected microphone and prompting together. Pause stops both. Advanced settings also offers a microphone-only test: closing that window leaves the test active, with the main-window microphone indicator visible. Choose Stop microphone or Pause to stop capture.

The recent transcript can revise itself as Whisper recognizes more context. It is diagnostic text, not a recording or final transcript export.

## Scripts, cues, and storage

Scripts autosave locally. Imports preserve text, not document styling or images. Export TXT or RTF from File → Export Script.

Add a cue at the current position to jump back later. Right-click to remove a cue. Cues store relative positions, so recreate them after major script or layout changes. Time remaining is an estimate; elapsed time excludes pauses and countdowns.

- Library: `~/Library/Application Support/Prompter/library.json`
- Models and tokenizer: `~/Library/Application Support/Prompter/Whisper`

The library is ordinary local JSON, not encrypted storage. An unreadable library is preserved; export any new work before quitting recovery mode. Back up the library before replacing or reinstalling a development build.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Space / ⌘Return | Play / pause |
| ↑ / ↓ | Pace ±5 wpm |
| ← / → | Scroll backward / forward |
| R / ⌘R | Reset |
| B / ⌘⇧B | Talent blackout |
| ⌘B | Add cue |
| ⌘← / ⌘→ | Previous / next cue |
| ⌘E | Edit script |
| ⌘N | New script |
| ⌘O | Import |
| ⌘S | Save |
| ⌘⇧L | Advanced voice settings |
| ⌘⇧P | Rehearsal window |
| ⌘⇧. | Stop talent output |
| ⌃⌘F | Main-window full screen |

Single-key controls leave text entry alone when an editor or text field has focus. Click the preview to return keyboard control to prompting.
