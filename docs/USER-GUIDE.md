# StudioPrompter user guide

## Two-screen setup

Use an extended desktop in macOS Display settings. Keep the producer workspace on your primary display, then choose **Prompter Output** and select the talent monitor. Both screens share a script position and line wrapping. Talent output is borderless; the main window retains standard macOS window controls.

Mirror and flip affect only talent output. **B** blacks out the talent monitor while leaving the producer preview visible. Stop output from the right panel or the Prompt menu. Disconnecting the selected display closes its output and pauses playback.

With one monitor, use the producer preview or choose **Prompter Output → Webcam Layout** to read near your webcam (development build).

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

Play starts the selected microphone and prompting together. Pause stops both. Advanced settings also offers a microphone-only test: closing that window leaves the test active, with the main-window microphone indicator visible. Choose Stop microphone to stop capture; Pause also stops capture.

The recent transcript can revise itself as Whisper recognizes more context. It is diagnostic text, not a recording or final transcript export.

## Scripts, bookmarks, and storage

Bookmarks were called **cue points** in 0.1.0. Existing saved positions carry over automatically. Experimental voice commands accept both names, including “go to the next bookmark” and “go to bookmark number two.”

Scripts autosave as Markdown files. Import TXT, MD/Markdown, RTF, RTFD, DOC, or DOCX. Markdown imports understand `**bold**` (or `<strong>`), `<u>underline</u>`, and StudioPrompter bookmark comments; other Markdown constructs remain literal script text. Word and rich-text imports retain bold and underline while using your prompter’s typography. Images and other document styling are omitted. PDF import is not currently supported.

Choose **Edit script**, select a passage, and use **B** or **U** (⌘B / ⌘U) to add emphasis. Both can be applied together. **Clear emphasis** removes them. Formatting appears in the producer preview and talent display, and voice following uses the same layout. Typing, formatting, and bookmark changes support undo/redo within the current editing session. Switching scripts or leaving the editor starts a new undo history.

Export from **File → Export Script**: Markdown preserves emphasis and bookmark comments, RTF preserves emphasis, and TXT contains only spoken text. Markdown uses `<u>` because standard Markdown has no underline syntax, and `<strong>` for bold selections spanning line breaks or boundary spaces. Bookmark comments are hidden from the editor and prompter; they are never spoken text.

In the editor, place the text cursor at a passage and choose **Add bookmark** (⌘⌥B). Orange numbered markers beside the text match the bookmark list; a small flag marks each exact anchor, including bookmarks placed between words or on blank lines. Click a bookmark number or **Find** to reveal and highlight its location. If several bookmarks share a visual line, the gutter badge shows the first number plus a count; clicking it cycles through those bookmarks. Rename bookmarks in the list, use **Move here** to move one to the current text cursor, or use the trash button to remove it. These editor markers do not appear on the talent display or become script text. Bookmarks follow their passage when text is inserted before it. Deleting a bookmark’s passage leaves the bookmark at the start of the replacement. Undo restores the previous passage and bookmark together.

Outside the editor, Add bookmark saves the current reading position. Click a bookmark in the sidebar to jump to it. Older percentage-based bookmarks gain text anchors when their script is opened in the editor. Time remaining is an estimate; elapsed time excludes pauses and countdowns.

- Library index and display settings: `~/Library/Application Support/Prompter/library.json`
- Markdown scripts: `~/Library/Application Support/Prompter/Scripts/<generation>/<script-id>.md`
- Original library backup after migration: `~/Library/Application Support/Prompter/library-before-markdown.json`
- Models and tokenizer: `~/Library/Application Support/Prompter/Whisper`

The library is ordinary local Markdown plus a JSON index, not encrypted storage. Saves write a complete new generation of Markdown files before atomically switching the index; only then is the previous generation removed. Use Markdown export for a stable file to edit in another app, then import it again. Back up the entire `Prompter` folder, not just `library.json`.

Existing version-1 JSON libraries migrate automatically on save, with the original retained as `library-before-markdown.json`. Earlier app builds cannot read the new index. An unreadable library or missing Markdown file is preserved; export any new work before quitting recovery mode.


## Voice commands

“Hey Teleprompter” and natural-language commands are not included in the tester release. Follow script and Adaptive pace work normally using Play and Pause.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Space / ⌘Return | Play / pause |
| ↑ / ↓ | Pace ±5 wpm |
| ← / → | Scroll backward / forward |
| R / ⌘R | Reset |
| B / ⌘⇧B | Talent blackout |
| ⌘B / ⌘U | Bold / underline in the script editor |
| ⌘⌥B | Add bookmark |
| ⌘← / ⌘→ | Previous / next bookmark |
| ⌘E | Edit script |
| ⌘N | New script |
| ⌘O | Import |
| ⌘S | Save |
| ⌘⇧L | Advanced voice settings |
| ⌘⇧K | Webcam Layout |
| ⌘⇧. | Stop output |
| ⌃⌘F | Main-window full screen |

Single-key controls leave text entry alone when an editor or text field has focus. Click the preview to return keyboard control to prompting.

## Updating StudioPrompter

Pause prompting and stop the microphone, then choose **StudioPrompter → Check for Updates…** from the macOS menu bar. When a newer tester release is available, review its notes and choose Download, then Install & Relaunch. Your saved library and downloaded models stay on this Mac. Checks are manual; unpublished drafts are not offered. This build receives published tester releases from a separate feed. Older builds without this menu need one manual installation of an updater-enabled build.


## Webcam Layout (development build)

Choose **Prompter Output → Webcam Layout** from the top-right dropdown, alongside your connected monitors, or **Prompt → Open Webcam Layout** (⌘⇧K). Switching between a monitor and Webcam Layout closes the previous output without changing script progress. **Stop output** closes the active output. A checkmark identifies the active output in the dropdown. A compact reading window floats above other apps. It initially uses the built-in display when available; otherwise it uses the producer workspace’s display. Notched screens place the panel below the camera cutout. Other screens use a top-centered position.

Drag the grip beside “Webcam Layout” left, right, or down to align with your webcam. Use the resize button for independent **Width** and **Height** sliders in a stationary panel, or resize the window edges. The size panel stays in place while the camera window changes; choose **Done** when finished. The center button returns it to the top center of its current screen. Size and position are retained when you close and reopen the view during the same app session.

Scroll or drag the script manually. Play/Pause, Reset, Space, arrows, and Esc share the main window’s controls; Esc stops the microphone. The sliders button returns to producer controls while keeping Webcam Layout open. Configure your microphone, voice mode, and experimental hands-free commands there before opening Webcam Layout. The webcam layout stays unmirrored. Its reading guide starts near the top; drag the orange arrow down through the available reading area to suit your eyeline. Webcam Layout keeps its own guide position for the session, independent of the main window. The limit adjusts to the window, text size, and configured guide height so the guide stays above the controls and remains steady as lines scroll through it. Your saved script font and canonical line wrapping are unchanged. It does not require camera permission.

Webcam Layout is not in the published 0.1.0 tester release yet.
