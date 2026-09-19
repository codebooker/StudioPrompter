import Foundation
import PrompterCore
import AppKit
import PrompterLayout

final class TransportTests {
    func testCountdownConsumesOnlyItsShareOfTheTick() {
        var transport = Transport()
        transport.play(countdown: 3, hasContent: true)
        transport.tick(seconds: 2, duration: 100)
        expectEqual(transport.progress, 0)
        expectEqual(transport.countdownRemaining, 1)
        transport.tick(seconds: 2, duration: 100)
        expectEqual(transport.progress, 0.01, accuracy: 0.0001)
        expectEqual(transport.elapsed, 1)
    }
    func testPlaybackIsIndependentOfFrameRate() {
        var a = Transport(), b = Transport()
        a.play(countdown: 0, hasContent: true)
        b.play(countdown: 0, hasContent: true)
        a.tick(seconds: 30, duration: 60)
        for _ in 0..<1800 { b.tick(seconds: 1.0 / 60, duration: 60) }
        expectEqual(a.progress, b.progress, accuracy: 0.00001)
    }
    func testEndStopsAtFinalLineAndReplayResets() {
        var transport = Transport()
        transport.play(countdown: 0, hasContent: true)
        transport.tick(seconds: 120, duration: 60)
        expectEqual(transport.progress, 1)
        expectEqual(transport.elapsed, 60)
        expectFalse(transport.isPlaying)
        transport.play(countdown: 0, hasContent: true)
        expectEqual(transport.progress, 0)
        expectEqual(transport.elapsed, 0)
        expectTrue(transport.isPlaying)
    }
    func testPauseAndManualSeekDoNotAdvanceTime() {
        var transport = Transport()
        transport.play(countdown: 3, hasContent: true)
        transport.pause()
        transport.seek(to: 0.4)
        transport.tick(seconds: 5, duration: 60)
        expectEqual(transport.progress, 0.4)
        expectEqual(transport.elapsed, 0)
        expectEqual(transport.countdownRemaining, 0)
        transport.seek(to: -4)
        expectEqual(transport.progress, 0)
        transport.seek(to: 3)
        expectEqual(transport.progress, 1)
    }
    func testEmptyScriptCannotPlay() {
        var transport = Transport()
        transport.play(countdown: 3, hasContent: false)
        expectFalse(transport.isPlaying)
        expectEqual(transport.countdownRemaining, 0)
    }
    func testSpeedChangeAffectsSubsequentMotionOnly() {
        var transport = Transport()
        transport.play(countdown: 0, hasContent: true)
        transport.tick(seconds: 10, duration: 100)
        transport.tick(seconds: 10, duration: 50)
        expectEqual(transport.progress, 0.3, accuracy: 0.00001)
        expectEqual(transport.elapsed, 20)
    }
}

final class LibraryTests {
    func testUnicodeTextSettingsCuesAndSelectionRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/library.json")
        var script = Script(title: "Podcast — épisode ①", text: "Hello 👋\n\nCafé\tworld", cues: [Cue(title: "Start", progress: 0), Cue(title: "Close", progress: 0.8)])
        script.settings.mirrorHorizontal = true
        script.settings.wordsPerMinute = 175
        script.settings.guidePosition = 0.51
        script.settings.guideLines = 2
        try LibraryStore.save(Library(scripts: [script]), to: url)
        let loaded = try LibraryStore.load(from: url)
        expectEqual(loaded.scripts, [script])
        expectEqual(loaded.selectedID, script.id)
        expectEqual(script.wordCount, 4)
    }
    func testCorruptedLibraryIsNotChangedOnRead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("broken library".utf8)
        try original.write(to: url)
        expectThrows(try LibraryStore.load(from: url))
        expectEqual(try Data(contentsOf: url), original)
    }
    func testDurationAndEmptyWhitespace() {
        var script = Script(title: "Test", text: "one two three four")
        script.settings.wordsPerMinute = 120
        expectEqual(script.duration, 2)
        script.text = " \n\t "
        expectEqual(script.duration, 0)
    }
    func testExistingSettingsGainGuideDefaultsWithoutLosingPreferences() throws {
        var original = PromptSettings()
        original.fontSize = 64
        original.mirrorHorizontal = true
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        json.removeValue(forKey: "guidePosition")
        json.removeValue(forKey: "guideLines")
        let decoded = try JSONDecoder().decode(PromptSettings.self, from: JSONSerialization.data(withJSONObject: json))
        expectEqual(decoded.guidePosition, 0.32)
        expectEqual(decoded.guideLines, 1)
        expectEqual(decoded.fontSize, 64)
        expectTrue(decoded.mirrorHorizontal)
    }
    func testTypefaceMigrationAndPersistence() throws {
        let decoder = JSONDecoder()
        let legacySerif = try decoder.decode(PromptSettings.self, from: Data(#"{"serifFont":true,"fontSize":64}"#.utf8))
        expectEqual(legacySerif.typeface, .georgia)
        expectEqual(legacySerif.fontSize, 64)
        expectEqual(try decoder.decode(PromptSettings.self, from: Data(#"{"serifFont":false}"#.utf8)).typeface, .system)
        expectEqual(try decoder.decode(PromptSettings.self, from: Data("{}".utf8)).typeface, .system)
        expectEqual(try decoder.decode(PromptSettings.self, from: Data(#"{"typeface":"future-font"}"#.utf8)).typeface, .system)
        expectEqual(try decoder.decode(PromptSettings.self, from: Data(#"{"typeface":"verdana","serifFont":true}"#.utf8)).typeface, .verdana)
        for typeface in ScriptTypeface.allCases {
            var settings = PromptSettings()
            settings.typeface = typeface
            settings.fontSize = 58
            let data = try JSONEncoder().encode(settings)
            expectEqual(try decoder.decode(PromptSettings.self, from: data), settings)
        }
    }
}


private var failures = 0
private var assertions = 0
private func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    assertions += 1
    if !value { failures += 1; print("FAIL \(file):\(line)") }
}
private func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    expectTrue(!value, file: file, line: line)
}
private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    expectTrue(lhs == rhs, file: file, line: line)
}
private func expectEqual(_ lhs: Double, _ rhs: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) {
    expectTrue(abs(lhs - rhs) <= accuracy, file: file, line: line)
}
private func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try expression(); expectTrue(false, file: file, line: line) }
    catch { expectTrue(true) }
}

@main enum CoreChecks {
    static func main() throws {
        let transport = TransportTests()
        transport.testCountdownConsumesOnlyItsShareOfTheTick()
        transport.testPlaybackIsIndependentOfFrameRate()
        transport.testEndStopsAtFinalLineAndReplayResets()
        transport.testPauseAndManualSeekDoNotAdvanceTime()
        transport.testEmptyScriptCannotPlay()
        transport.testSpeedChangeAffectsSubsequentMotionOnly()
        let library = LibraryTests()
        try library.testUnicodeTextSettingsCuesAndSelectionRoundTrip()
        try library.testCorruptedLibraryIsNotChangedOnRead()
        library.testDurationAndEmptyWhitespace()
        try library.testExistingSettingsGainGuideDefaultsWithoutLosingPreferences()
        try library.testTypefaceMigrationAndPersistence()
        try editorChecks()
        speechChecks()
        followChecks()
        adaptiveChecks()
        recognitionRecoveryChecks()
        retakeChecks()
        layoutChecks()
        print("\(assertions) assertions across playback, persistence, speech alignment, and cadence checks; \(failures) failures")
        if failures > 0 { exit(1) }
    }
}

private func layoutChecks() {
    var settings = PromptSettings()
    settings.fontSize = 64; settings.lineSpacing = 1.3
    let source = "End of paragraph.\n \n\nNext paragraph 👋."
    let storage = NSTextStorage(attributedString: ScriptTypography.text(source, settings: settings))
    expectEqual(storage.string, source)
    expectEqual(storage.length, (source as NSString).length)
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for: container)
    let first = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
    let nextOffset = (source as NSString).range(of: "Next").location
    let next = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: nextOffset), effectiveRange: nil)
    let lineHeight = layout.defaultLineHeight(for: ScriptTypography.font(settings)) + settings.fontSize * (settings.lineSpacing - 1)
    expectTrue(next.minY - first.minY < lineHeight * 1.5)
    let nominal = CGRect(x: 0, y: 100, width: 1000, height: lineHeight * 2 + 12)
    let top = CGRect(x: 100, y: 70, width: 800, height: 80)
    let bottom = CGRect(x: 100, y: nominal.maxY - 20, width: 800, height: 80)
    let outside = CGRect(x: 100, y: nominal.maxY + 100, width: 800, height: 80)
    let band = FocusGeometry.band(nominal: nominal, textLines: [top, bottom, outside])
    expectTrue(band.contains(top))
    expectTrue(band.contains(bottom))
    expectFalse(band.intersects(outside))
    expectEqual(FocusGeometry.band(nominal: nominal, textLines: []), nominal)
}

private func retakeChecks() {
    var transport = Transport()
    transport.play(countdown: 3, hasContent: true)
    transport.reposition(to: 0.4, preservingPlayback: true)
    expectTrue(transport.isPlaying)
    expectEqual(transport.countdownRemaining, 0)
    expectEqual(transport.progress, 0.4)
    var gate = RetakeGate()
    gate.begin(now: 10, audioEnd: 8, progress: 0.4)
    expectTrue(gate.isWaiting)
    expectTrue(gate.minimumSpeechTime > 8) // Discard buffered/in-flight pre-seek audio.
    expectFalse(gate.accept(target: 0.405, lineStep: 0.01, now: 10.2))
    expectFalse(gate.accept(target: 0.5, lineStep: 0.01, now: 11)) // Old location.
    transport.follow(seconds: 2, target: gate.isWaiting ? nil : 0.5, lineStep: 0.01)
    expectEqual(transport.progress, 0.4)
    gate.begin(now: 11, audioEnd: 9, progress: 0.2) // Another scroll restarts settling.
    expectFalse(gate.accept(target: 0.205, lineStep: 0.01, now: 11.1))
    expectTrue(gate.accept(target: 0.205, lineStep: 0.01, now: 11.5))
    expectFalse(gate.isWaiting)
    transport.reposition(to: 0.2, preservingPlayback: true)
    transport.follow(seconds: 0.5, target: 0.205, lineStep: 0.01)
    expectTrue(transport.progress > 0.2)
    transport.pause()
    transport.reposition(to: 0.1, preservingPlayback: true)
    expectFalse(transport.isPlaying) // Explicit pause cannot be undone by a scroll.
    transport.play(countdown: 0, hasContent: true)
    transport.reposition(to: 0.3, preservingPlayback: false)
    expectFalse(transport.isPlaying) // Fixed-speed prompting keeps manual pause.
    transport.play(countdown: 0, hasContent: true)
    transport.reposition(to: 1, preservingPlayback: true)
    expectFalse(transport.isPlaying)
    expectEqual(transport.progress, 1)
}

private func recognitionRecoveryChecks() {
    let script = ScriptMatcher.words(in: "Good morning everyone Today I want to talk to you about something important It's about the small things we do every day These small things can make a big difference")
    let badPrefix = "some of the things that you have been doing which are not the right words "
    let recovered = ScriptMatcher.match(badPrefix + "about something important", script: script, near: 10)
    expectEqual(recovered?.wordIndex, 12)
    let continuing = ScriptMatcher.match(badPrefix + "It's about the small things we do every day", script: script, near: recovered?.wordIndex ?? 10)
    expectEqual(continuing?.wordIndex, 21)
    expectEqual(ScriptMatcher.match("These small things can make a big", script: script, near: 21)?.wordIndex, 28)
    expectTrue(ScriptMatcher.match(badPrefix + "the weather tomorrow", script: script, near: 10) == nil)
    var updates = RecognitionUpdates()
    expectTrue(updates.accept(text: "incorrect words", wordEnd: 5, audioEnd: 5.2))
    expectTrue(updates.accept(text: "about something important", wordEnd: 5, audioEnd: 5.9))
    expectFalse(updates.accept(text: "about something important", wordEnd: 5, audioEnd: 6.5))
    expectFalse(updates.accept(text: "old revised speech", wordEnd: 5, audioEnd: 8))
    expectTrue(updates.accept(text: "the next sentence", wordEnd: 9, audioEnd: 9.2))
    // A hallucinated future timestamp must not block every subsequent result.
    var future = RecognitionUpdates()
    expectTrue(future.accept(text: "bad timestamp", wordEnd: 30, audioEnd: 3))
    expectTrue(future.accept(text: "corrected", wordEnd: 4, audioEnd: 4.2))
}

private func adaptiveChecks() {
    var transport = Transport()
    transport.play(countdown: 0, hasContent: true)
    for _ in 0..<60 { transport.adapt(seconds: 1.0 / 60, duration: 100, speaking: true, target: nil, lineStep: 0.01) }
    expectEqual(transport.progress, 0.01, accuracy: 0.00001)
    let held = transport.progress
    transport.adapt(seconds: 1, duration: 100, speaking: false, target: 0.1, lineStep: 0.01)
    expectEqual(transport.progress, held)
    // Fast cadence cannot push recognized text above the reading area.
    for _ in 0..<60 { transport.adapt(seconds: 1.0 / 60, duration: 10, speaking: true, target: held, lineStep: 0.01) }
    expectTrue(transport.progress <= held + 0.002501)
    // A match ahead catches up smoothly even if cadence underestimates speech.
    let before = transport.progress
    transport.adapt(seconds: 1.0 / 60, duration: 1000, speaking: true, target: before + 0.02, lineStep: 0.01)
    expectTrue(transport.progress - before < 0.0003)
    for _ in 0..<60 { transport.adapt(seconds: 1.0 / 60, duration: 1000, speaking: true, target: before + 0.02, lineStep: 0.01) }
    expectTrue(transport.progress >= before + 0.017)
    expectTrue(transport.progress <= before + 0.022501)
    let ahead = transport.progress
    transport.adapt(seconds: 0.1, duration: 100, speaking: true, target: 0, lineStep: 0.01)
    expectEqual(transport.progress, ahead)
    transport.pause()
    transport.adapt(seconds: 1, duration: 10, speaking: true, target: 0.5, lineStep: 0.01)
    expectEqual(transport.progress, ahead)
    transport.reset(); transport.play(countdown: 3, hasContent: true)
    transport.adapt(seconds: 3, duration: 100, speaking: true, target: nil, lineStep: 0.01)
    expectEqual(transport.progress, 0)
    transport.adapt(seconds: 1, duration: 100, speaking: true, target: nil, lineStep: 0.01)
    expectEqual(transport.progress, 0.01, accuracy: 0.00001)
}

private func followChecks() {
    // Two lines of recognition lag should be nearly gone within one second,
    // independent of whether the script contains 100 or 1,000 rendered lines.
    for lines in [100.0, 1000.0] {
        var position = 0.2
        var motion = FollowMotion()
        let target = position + 2 / lines
        for _ in 0..<60 { position = motion.advance(from: position, to: target, seconds: 1.0 / 60, lineStep: 1 / lines) }
        expectTrue((target - position) * lines < 0.1)
        expectTrue(position <= target)
    }
    var motion = FollowMotion()
    expectEqual(motion.advance(from: 0.4, to: 0.3, seconds: 1, lineStep: 0.01), 0.4)
    expectTrue(motion.advance(from: 0, to: 0.8, seconds: 0.1, lineStep: 0.01) <= 0.0041)
    var a = 0.0, b = 0.0
    var motionA = FollowMotion(), motionB = FollowMotion()
    for _ in 0..<30 { a = motionA.advance(from: a, to: 0.01, seconds: 1.0 / 30, lineStep: 0.01) }
    for _ in 0..<60 { b = motionB.advance(from: b, to: 0.01, seconds: 1.0 / 60, lineStep: 0.01) }
    expectEqual(a, b, accuracy: 0.00001)
    let spread = ReadingPositions.spread(lineStarts: [0, 0, 0, 0, 0.1, 0.1, 0.1, 0.1, 0.2], lineStep: 0.1)
    expectEqual(spread[1], 0, accuracy: 0.00001)
    expectEqual(spread[3], 0.025, accuracy: 0.00001)
    expectEqual(spread[4] - spread[3], spread[3] - spread[2], accuracy: 0.00001)
    expectTrue(zip(spread, spread.dropFirst()).allSatisfy { $0 <= $1 })
    expectEqual(spread[6], 0.1, accuracy: 0.00001)
    expectEqual(ReadingPositions.spread(lineStarts: [], lineStep: 0.1), [])
    // A newly recognized line must not cause an immediate speed jump.
    var smooth = FollowMotion()
    let firstStep = smooth.advance(from: 0, to: 0.01, seconds: 1.0 / 60, lineStep: 0.01)
    expectTrue(firstStep < 0.0002)
    let oldVelocity = smooth.velocity
    _ = smooth.advance(from: firstStep, to: 0.02, seconds: 1.0 / 60, lineStep: 0.01)
    expectTrue(smooth.velocity - oldVelocity < 0.03)
    // Reach 90% of a newly confirmed line within 0.4 seconds, without overshoot.
    var responsive = FollowMotion()
    var caughtUp = 0.0
    for _ in 0..<24 { caughtUp = responsive.advance(from: caughtUp, to: 0.01, seconds: 1.0 / 60, lineStep: 0.01) }
    expectTrue(caughtUp >= 0.009 && caughtUp <= 0.01)
    var transport = Transport()
    transport.play(countdown: 3, hasContent: true)
    transport.follow(seconds: 3, target: 0.3, lineStep: 0.01)
    expectEqual(transport.progress, 0)
    transport.follow(seconds: 5, target: nil, lineStep: 0.01)
    expectEqual(transport.progress, 0)
    expectEqual(transport.elapsed, 0)
    transport.follow(seconds: 0.5, target: 0.01, lineStep: 0.01)
    expectTrue(transport.progress > 0.008)
    let held = transport.progress
    transport.follow(seconds: 5, target: nil, lineStep: 0.01)
    expectEqual(transport.progress, held)
    transport.pause()
    transport.seek(to: 0.6)
    transport.follow(seconds: 1, target: 0.7, lineStep: 0.01)
    expectEqual(transport.progress, 0.6)
    transport.play(countdown: 0, hasContent: true)
    for _ in 0..<1200 { transport.follow(seconds: 1.0 / 60, target: 1, lineStep: 0.01) }
    expectEqual(transport.progress, 1)
    expectFalse(transport.isPlaying)
}

private func speechChecks() {
    let script = ScriptMatcher.words(in: "Every great idea starts with a little room. Room to be curious. Room to try something different.")
    let exact = ScriptMatcher.match("Every great idea starts with a little room", script: script, near: 0)
    expectEqual(exact?.wordIndex, 7)
    let skipped = ScriptMatcher.match("Every idea starts with a room", script: script, near: 0)
    expectEqual(skipped?.wordIndex, 7)
    let filler = ScriptMatcher.match("Every great idea um starts with a little room", script: script, near: 0)
    expectEqual(filler?.wordIndex, 7)
    expectTrue(ScriptMatcher.match("The weather is sunny in Paris", script: script, near: 0) == nil)
    expectTrue(ScriptMatcher.match("room", script: script, near: 0) == nil)
    let phrase = ScriptMatcher.words(in: "They can help us feel happier and more ready for life. Every day we face many choices.")
    let misheard = ScriptMatcher.match("They can help us feel happier and more ready for a lot of time", script: phrase, near: 0)
    expectTrue(misheard != nil)
    expectTrue((misheard?.wordIndex ?? 100) <= 10)
    expectEqual(ScriptMatcher.match("Every day we face many choices", script: phrase, near: misheard?.wordIndex ?? 0)?.wordIndex, 16)
    expectTrue(ScriptMatcher.match("how many licks to the center of a tootsie pop the world may never know", script: phrase, near: 9) == nil)
    let punctuation = ScriptMatcher.words(in: "Hello, CAFÉ! It’s ready.")
    expectEqual(punctuation.map(\.text), ["hello", "cafe", "it's", "ready"])
    var pace = PaceEstimator()
    expectTrue(pace.observe(wordCount: 1, span: 0.2, audioEnd: 0.2) == nil)
    expectEqual(pace.observe(wordCount: 10, span: 5, audioEnd: 5), 120)
    let burst = pace.observe(wordCount: 20, span: 5, audioEnd: 5.3)!
    expectTrue(burst <= 123.601)
    expectEqual(pace.observe(wordCount: 20, span: 5, audioEnd: 5.3), burst)
    expectEqual(pace.observe(wordCount: 0, span: 0, audioEnd: 6), burst)
    expectEqual(pace.observe(wordCount: 100, span: 1, audioEnd: 6), burst)
    let slower = pace.observe(wordCount: 5, span: 5, audioEnd: 5.8)!
    expectTrue(burst - slower > 20)
    var frequent = PaceEstimator(), sparse = PaceEstimator()
    _ = frequent.observe(wordCount: 10, span: 5, audioEnd: 5)
    _ = sparse.observe(wordCount: 10, span: 5, audioEnd: 5)
    for tick in 1...10 { _ = frequent.observe(wordCount: 20, span: 5, audioEnd: 5 + Double(tick) / 10) }
    for tick in 1...2 { _ = sparse.observe(wordCount: 20, span: 5, audioEnd: 5 + Double(tick) / 2) }
    expectEqual(frequent.wordsPerMinute!, sparse.wordsPerMinute!, accuracy: 0.001)
    expectEqual(frequent.wordsPerMinute!, 132, accuracy: 0.001)
    var opening = PaceEstimator()
    expectEqual(opening.observe(wordCount: 10, span: 2, audioEnd: 2), 130)
}


private func editorChecks() throws {
    let text = "Hello 👋 Café — **literal** <u>literal</u> \\end\nRead this carefully."
    var script = Script(title: "Emphasis and cues", text: text)
    let cafe = (text as NSString).range(of: "Café")
    let passage = (text as NSString).range(of: "Read this carefully.")
    script.emphasis = [TextEmphasis(location: cafe.location, length: cafe.length, bold: true, underline: true), TextEmphasis(location: passage.location, length: passage.length, underline: true)]
    script.cues = [Cue(title: "Say Café — <!-- safely -->", progress: 0.15, characterOffset: cafe.location), Cue(title: "Closing", progress: 0.8, characterOffset: passage.location), Cue(title: "End", progress: 1, characterOffset: (text as NSString).length)]
    let markdown = try ScriptMarkdown.encode(script)
    expectTrue(markdown.contains("**<u>Café</u>**"))
    expectTrue(markdown.contains("studioprompter-cue"))
    expectEqual(try ScriptMarkdown.encode(Script(title: "Plain", text: "Hello. A natural sentence!")), "Hello. A natural sentence!")
    let punctuation = "# Heading\n1. Number\n- List\nA &copy; literal = value."
    expectEqual(ScriptMarkdown.decode(try ScriptMarkdown.encode(Script(title: "Literal", text: punctuation)), title: "Literal").text, punctuation)
    let decoded = ScriptMarkdown.decode(markdown, title: script.title)
    expectEqual(decoded.text, text)
    expectEqual(decoded.emphasis, script.emphasis)
    expectEqual(decoded.cues, script.cues)
    let edited = ScriptMarkdown.decode("An opening. " + markdown, title: script.title)
    expectEqual(edited.cues.first?.characterOffset, cafe.location + 12)
    expectEqual(edited.emphasis.first?.location, cafe.location + 12)
    let plain = ScriptMarkdown.decode("A **bold** word and <u>underlined</u> words.", title: "Test")
    expectEqual(plain.text, "A bold word and underlined words.")
    expectEqual(plain.emphasis.count, 2)
    expectTrue(plain.emphasis[0].bold)
    expectTrue(plain.emphasis[1].underline)
    expectEqual(ScriptMarkdown.decode("unclosed ** and <u>literal", title: "Test").text, "unclosed ** and <u>literal")
    var multiline = Script(title: "Multiline", text: " First line\nSecond line ")
    multiline.emphasis = [TextEmphasis(location: 0, length: (multiline.text as NSString).length, bold: true)]
    let multilineMarkdown = try ScriptMarkdown.encode(multiline)
    expectTrue(multilineMarkdown.hasPrefix("<strong>"))
    expectEqual(ScriptMarkdown.decode(multilineMarkdown, title: "Multiline").emphasis, multiline.emphasis)
    let invalid = "<!-- studioprompter-cue invalid -->"
    expectEqual(ScriptMarkdown.decode(invalid, title: "Test").text, invalid)
    expectTrue(TextEmphasis(location: -1, length: 4, bold: true).range(in: "hello") == nil)
    expectEqual(TextEmphasis(location: 3, length: Int.max, bold: true).range(in: "hello"), NSRange(location: 3, length: 2))

    let inserted = CueAnchors.replacing(script.cues, range: NSRange(location: 0, length: 0), replacementLength: 3)
    expectEqual(inserted[0].characterOffset, cafe.location + 3)
    let atCue = CueAnchors.replacing(script.cues, range: NSRange(location: cafe.location, length: 0), replacementLength: 4)
    expectEqual(atCue[0].characterOffset, cafe.location + 4)
    let deleted = CueAnchors.replacing(script.cues, range: NSRange(location: cafe.location - 1, length: 6), replacementLength: 0)
    expectEqual(deleted[0].characterOffset, cafe.location - 1)
    expectEqual(deleted[1].characterOffset, passage.location - 6)
    let legacyCue = Cue(title: "Legacy", progress: 0.5)
    expectEqual(CueAnchors.replacing([legacyCue], range: NSRange(location: 0, length: 2), replacementLength: 4), [legacyCue])

    for typeface in ScriptTypeface.allCases {
        script.settings.typeface = typeface
        let rich = ScriptTypography.text(script.text, settings: script.settings, emphasis: script.emphasis)
        let font = rich.attribute(.font, at: cafe.location, effectiveRange: nil) as! NSFont
        expectTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        expectEqual(rich.attribute(.underlineStyle, at: cafe.location, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        let cues = ScriptCueLayout(script)
        expectTrue(cues.progress(at: passage.location) >= cues.progress(at: cafe.location))
    }
    let editor = ScriptTypography.editorText(script)
    expectEqual(ScriptTypography.emphasis(in: editor), script.emphasis)
    let rtf = try editor.data(from: NSRange(location: 0, length: editor.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    let imported = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
    expectEqual(imported.string, text)
    expectEqual(ScriptTypography.emphasis(in: imported), script.emphasis)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("library.json")
    let library = Library(scripts: [script])
    // A real version-1 payload without the new emphasis/anchor fields still loads.
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as! [String: Any]
    var scripts = legacy["scripts"] as! [[String: Any]]
    scripts[0].removeValue(forKey: "emphasis")
    scripts[0]["cues"] = [["id": legacyCue.id.uuidString, "title": legacyCue.title, "progress": legacyCue.progress]]
    legacy["scripts"] = scripts
    let original = try JSONSerialization.data(withJSONObject: legacy)
    try original.write(to: url)
    let oldLibrary = try LibraryStore.load(from: url)
    expectEqual(oldLibrary.scripts[0].text, text)
    expectEqual(oldLibrary.scripts[0].emphasis, [])
    expectEqual(oldLibrary.scripts[0].cues, [legacyCue])
    try LibraryStore.save(library, to: url)
    expectEqual(try Data(contentsOf: directory.appendingPathComponent("library-before-markdown.json")), original)
    expectEqual(try LibraryStore.load(from: url).scripts, [script])
    let index = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    expectEqual(index["version"] as? Int, 2)
    expectTrue((index["scripts"] as! [[String: Any]])[0]["text"] == nil)
    let folder = directory.appendingPathComponent("Scripts").appendingPathComponent(index["generation"] as! String)
    let mdURL = folder.appendingPathComponent(script.id.uuidString + ".md")
    expectEqual(try String(contentsOf: mdURL, encoding: .utf8), markdown)
    // A missing script fails closed instead of silently saving an empty replacement.
    try FileManager.default.removeItem(at: mdURL)
    let savedIndex = try Data(contentsOf: url)
    expectThrows(try LibraryStore.load(from: url))
    expectEqual(try Data(contentsOf: url), savedIndex)
    try LibraryStore.save(library, to: url)
    expectEqual(try Data(contentsOf: directory.appendingPathComponent("library-before-markdown.json")), original)
    expectEqual(try LibraryStore.load(from: url).scripts, [script])
    expectFalse(FileManager.default.fileExists(atPath: folder.path))
}
