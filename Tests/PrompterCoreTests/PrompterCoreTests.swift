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
        completedLineChecks()
        bottomGuideMotionChecks()
        voiceCommandChecks()
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

private func completedLineChecks() {
    var settings = PromptSettings()
    settings.fontSize = 58; settings.lineSpacing = 1.3; settings.margin = 110
    let source = "Every day, we face many choices. Some choices are big. But most are small. These little choices add up over time. They shape how we feel and how we see the world. Sometimes, it’s the tiny things that change everything.\n\nThink about your morning routine. How you start your day can set the tone. Simple actions like drinking water, stretching, or taking a deep breath matter."
    let words = ScriptMatcher.words(in: source)
    let storage = NSTextStorage(attributedString: ScriptTypography.text(source, settings: settings))
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 1000 - settings.margin * 2, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for: container)
    let travel = max(1, layout.usedRect(for: container).height - settings.fontSize * 1.2)
    let lineHeight = layout.defaultLineHeight(for: ScriptTypography.font(settings)) + settings.fontSize * (settings.lineSpacing - 1)
    let lineStarts = words.map { layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: $0.characterOffset), effectiveRange: nil).minY / travel }
    let positions = ReadingPositions.spread(lineStarts: lineStarts, lineStep: lineHeight / travel)
    let ending = words.firstIndex { $0.text == "everything" }!
    let next = ending + 1
    let match = ScriptMatcher.match("the tiny things that change everything", script: words, near: ending - 5)
    expectEqual(match?.wordIndex, ending)
    expectEqual(words[next].text, "think")
    // Once the final word is recognized, the next unread line must enter the
    // reading band without requiring the presenter to read dimmed text first.
    for (height, guide) in [(500.0, 0.38), (174.0 / 0.58, 0.095), (114.0 / 0.36, 0.095)] {
        var transport = Transport()
        transport.seek(to: positions[max(0, ending - 1)])
        transport.play(countdown: 0, hasContent: true)
        for _ in 0..<60 { transport.follow(seconds: 1.0 / 60, target: positions[ending], lineStep: lineHeight / travel) }
        let guideY = height * guide
        let origin = guideY - settings.fontSize * 0.2 - transport.progress * travel
        let glyph = layout.glyphIndexForCharacter(at: words[next].characterOffset)
        let nextLine = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).offsetBy(dx: settings.margin, dy: origin)
        let nominal = CGRect(x: 0, y: guideY - 8, width: 1000, height: lineHeight + 12)
        let band = FocusGeometry.band(nominal: nominal, textLines: [nextLine])
        expectTrue(band.contains(nextLine))
        expectTrue(nextLine.minY >= 0 && nextLine.maxY <= height)
        let stopped = transport.progress
        for _ in 0..<120 { transport.follow(seconds: 1.0 / 60, target: nil, lineStep: lineHeight / travel) }
        expectEqual(transport.progress, stopped)
    }
}

private func bottomGuideMotionChecks() {
    var settings = PromptSettings()
    settings.fontSize = 58; settings.lineSpacing = 1.3; settings.margin = 110
    let source = "The guide should stay still while these words scroll smoothly into view. A line transition must not move the camera reading position.\n\nThe next paragraph continues at the same steady pace."
    let storage = NSTextStorage(attributedString: ScriptTypography.text(source, settings: settings))
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 780, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for: container)
    let lineHeight = layout.defaultLineHeight(for: ScriptTypography.font(settings)) + settings.fontSize * (settings.lineSpacing - 1)
    var lines: [CGRect] = []
    layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, used, _, _, _ in lines.append(used) }
    for height in [200.0, 300.0, 550.0] {
        for count in [1.0, 2.0] {
            let guideY = CameraViewGeometry.guideRange(viewportHeight: height, lineHeight: lineHeight, guideLines: count).upperBound * height
            let nominal = CGRect(x: 0, y: guideY - 8, width: 1000, height: lineHeight * count + 12)
            var previousOrigin: Double?
            var previousBand: CGRect?
            var changedLines = false
            var steady = true
            for frame in 0..<360 {
                let shift = Double(frame) * 0.8
                let currentGuideY = CameraViewGeometry.guideRange(viewportHeight: height, lineHeight: lineHeight, guideLines: count).upperBound * height
                let origin = currentGuideY - settings.fontSize * 0.2 - shift
                let movingLines = lines.map { $0.offsetBy(dx: settings.margin, dy: origin) }
                let band = FocusGeometry.band(nominal: nominal, textLines: movingLines)
                if let previousBand, abs(band.maxY - previousBand.maxY) > lineHeight / 2 { changedLines = true }
                if let previousOrigin, abs(origin - previousOrigin + 0.8) > 0.000001 { steady = false }
                if abs(currentGuideY - guideY) > 0.000001 { steady = false }
                previousOrigin = origin; previousBand = band
            }
            expectTrue(changedLines) // The fixture really crosses focus-band line boundaries.
            expectTrue(steady)       // Text still advances by exactly the requested amount.
        }
    }
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
    expectEqual(spread[3], 0.05, accuracy: 0.00001)
    expectEqual(spread[4], spread[3], accuracy: 0.00001)
    expectTrue(zip(spread, spread.dropFirst()).allSatisfy { $0 <= $1 })
    expectEqual(spread[6], 0.1, accuracy: 0.00001)
    expectEqual(ReadingPositions.spread(lineStarts: [], lineStep: 0.1), [])
    let shortLines = ReadingPositions.spread(lineStarts: [0, 0, 0.1, 0.23, 0.23, 0.23, 0.33], lineStep: 0.1)
    expectEqual(shortLines[0], 0)
    expectEqual(shortLines[1], 0.05, accuracy: 0.00001)
    expectEqual(shortLines[2], 0.18, accuracy: 0.00001)
    expectEqual(shortLines[3], shortLines[2], accuracy: 0.00001)
    expectTrue(zip(shortLines, shortLines.dropFirst()).allSatisfy { $0 <= $1 })
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


private func voiceCommandChecks() {
    expectEqual(VoiceCommand.parse("Go back to the last bookmark"), .cue(-1))
    expectEqual(VoiceCommand.parse("Go to the next bookmark"), .cue(1))
    expectEqual(VoiceCommand.parse("Can you go to the previous book mark?"), .cue(-1))
    expectEqual(VoiceCommand.parse("Go to the next cue point"), .cue(1))
    expectFalse(VoiceCommand.isIncomplete("Move down to bookmark two"))
    expectEqual(CommandIntent.interpret("{\"action\":\"go_to_cue\",\"value\":2}", request: "Take me to bookmark number two"), .cueNumber(2))

    let accepted: [(String, VoiceCommand)] = [
        ("Can we go back up two lines?", .lines(-2)), ("Please scroll down 3 lines", .lines(3)), ("rewind two lines", .lines(-2)), ("go back to lines", .lines(-2)),
        ("Let's start this paragraph over", .paragraph(0)), ("Move to the next paragraph", .paragraph(1)),
        ("Go back one paragraph", .paragraph(-1)), ("Start from the top of the document", .top),
        ("Increase the font size", .font(4)), ("Decrease the font size", .font(-4)),
        ("Go back to the last cue point", .cue(-1)), ("Go to the next cue", .cue(1)),
        ("Start", .resume), ("Let’s go", .resume), ("Let us go", .resume), ("Start the script please", .resume),
        ("Pause", .pause), ("Resume please", .resume), ("Never mind", .cancel), ("Stop listening", .stopListening)
    ]
    for (text, command) in accepted { expectEqual(VoiceCommand.parse(text), command) }
    for text in ["don't pause", "do not start", "let’s go back two lines and pause", "go back two lines and delete this script", "go back twenty lines", "we should increase the font size sometime", "", "pause resume"] {
        expectTrue(VoiceCommand.parse(text) == nil)
    }
    func words(_ text: String, from start: Double = 0) -> [CommandWord] {
        text.split(separator: " ").enumerated().map { CommandWord(String($0.element), start: start + Double($0.offset) * 0.2, end: start + Double($0.offset + 1) * 0.2) }
    }
    for phrase in ["Hey Prompter pause", "Hey Studio Prompter pause", "Hey Studio Control pause", "Hey Studio pause", "Hey the Studio Control pause", "The studio prompter is ready", "Hey the studio prompter pause"] {
        var router = VoiceCommandRouter()
        expectEqual(router.consume(words(phrase), audioEnd: 3, quiet: true), .reading)
    }
    var router = VoiceCommandRouter()
    let full = words("Hey Teleprompter go back two lines")
    expectEqual(router.consume(Array(full.prefix(2)), audioEnd: 0.7, quiet: false), .listening)
    expectEqual(router.consume(Array(full.prefix(5)), audioEnd: 1.3, quiet: false), .listening)
    expectEqual(router.consume(full, audioEnd: 1.8, quiet: false), .listening)
    expectEqual(router.consume(full, audioEnd: 2.3, quiet: true), .execute(.lines(-2)))
    expectFalse(router.isListening)
    expectEqual(router.consume(full, audioEnd: 2.6, quiet: true), .reading)
    expectEqual(router.consume(full, audioEnd: 3, quiet: true), .reading)
    let again = words("Hey Teleprompter go back two lines", from: 3)
    expectEqual(router.consume(again, audioEnd: 4.5, quiet: true), .listening)
    expectEqual(router.consume(again, audioEnd: 4.9, quiet: true), .execute(.lines(-2)))
    // A corrected hypothesis must settle before executing its final count.
    var punctuation = VoiceCommandRouter()
    let punctuated = words("HEY, TELEPROMPTER! pause.")
    expectEqual(punctuation.consume(punctuated, audioEnd: 1.1, quiet: true), .listening)
    expectEqual(punctuation.consume(punctuated, audioEnd: 1.5, quiet: true), .execute(.pause))
    var revised = VoiceCommandRouter()
    expectEqual(revised.consume(full, audioEnd: 1.8, quiet: true), .listening)
    let correction = words("Hey Teleprompter go back three lines")
    expectEqual(revised.consume(correction, audioEnd: 2.1, quiet: true), .listening)
    expectEqual(revised.consume(correction, audioEnd: 2.5, quiet: true), .execute(.lines(-3)))
    var timeout = VoiceCommandRouter()
    expectEqual(timeout.consume(words("Hey Teleprompter"), audioEnd: 1, quiet: true), .listening)
    expectEqual(timeout.consume([], audioEnd: 7.1, quiet: true), .unrecognized)
    expectEqual(timeout.consume(words("Hey Teleprompter"), audioEnd: 7.4, quiet: true), .reading)
    var late = VoiceCommandRouter(after: 4)
    expectEqual(late.consume(full, audioEnd: 5, quiet: true), .reading)
    var unknown = VoiceCommandRouter()
    let invalid = words("Hey Teleprompter order a pizza")
    expectEqual(unknown.consume(invalid, audioEnd: 2, quiet: true), .listening)
    expectEqual(unknown.consume(invalid, audioEnd: 2.5, quiet: true), .unrecognized)
    var speaking = VoiceCommandRouter()
    expectEqual(speaking.consume(full, audioEnd: 2, quiet: false), .listening)
    expectEqual(speaking.consume(full, audioEnd: 9, quiet: false), .unrecognized)

    // Natural-language fallback requires a fresh wake + a settled phrase and opt-in.
    var natural = VoiceCommandRouter()
    let flexible = words("Hey, Teleprompter take me back a couple of lines")
    expectEqual(natural.consume(flexible, audioEnd: 3, quiet: true, interpretUnknown: true), .listening)
    expectEqual(natural.consume(flexible, audioEnd: 3.5, quiet: true, interpretUnknown: true), .interpret("take me back a couple of lines"))
    expectEqual(natural.consume(flexible, audioEnd: 4, quiet: true, interpretUnknown: true), .reading)
    var unfinished = VoiceCommandRouter()
    expectEqual(unfinished.consume(flexible, audioEnd: 3, quiet: false, interpretUnknown: true), .listening)
    expectEqual(unfinished.consume(flexible, audioEnd: 10, quiet: false, interpretUnknown: true), .unrecognized)
    var fast = VoiceCommandRouter()
    expectEqual(fast.consume(full, audioEnd: 2, quiet: true, interpretUnknown: true), .listening)
    expectEqual(fast.consume(full, audioEnd: 2.5, quiet: true, interpretUnknown: true), .execute(.lines(-2)))
    for output in ["{\"action\":\"delete_script\"}", "{\"action\":\"back_20_lines\"}", "{\"action\":\"pause\",\"extra\":\"resume\"}", "pause", "[{\"action\":\"pause\"}]", "{\"action\":2}"] {
        expectTrue(CommandIntent.decode(output) == nil)
    }
    for count in 1...10 {
        expectEqual(CommandIntent.decode("{\"action\":\"back_\(count)_lines\"}"), .lines(-count))
        expectEqual(CommandIntent.decode("{\"action\":\"forward_\(count)_lines\"}"), .lines(count))
    }
    expectEqual(CommandIntent.interpret("{\"action\":\"back_2_lines\"}", request: "Back a couple of lines"), .lines(-2))
    for request in ["Go back twenty lines", "Go back a bit", "Back two lines and change the font", "Do not go back two lines"] {
        expectTrue(CommandIntent.interpret("{\"action\":\"back_2_lines\"}", request: request) == nil)
    }
    expectTrue(CommandIntent.interpret("{\"action\":\"next_cue\"}", request: "Skip to the next question") == nil)

    // Real-session regressions: never silently substitute a relative destination or count.
    let structured: [(String, String, VoiceCommand)] = [
        ("Go down two paragraphs for me", "{\"action\":\"move_paragraphs\",\"value\":2}", .paragraph(2)),
        ("Go to the tenth paragraph", "{\"action\":\"go_to_paragraph\",\"value\":10}", .paragraphNumber(10)),
        ("Go to paragraph 15", "{\"action\":\"go_to_paragraph\",\"value\":15}", .paragraphNumber(15)),
        ("Go down to the second cue point", "{\"action\":\"go_to_cue\",\"value\":2}", .cueNumber(2)),
        ("Go to the next Q point", "{\"action\":\"next_cue\"}", .cue(1)),
        ("Go to the final paragraph", "{\"action\":\"last_paragraph\"}", .lastParagraph),
        ("Set the font size to thirty two", "{\"action\":\"set_font_size\",\"value\":32}", .fontSize(32)),
        ("Switch from adaptive pace to follow script", "{\"action\":\"follow_script\"}", .followScript),
        ("Switch from follow script to adaptive pace", "{\"action\":\"adaptive_pace\"}", .adaptivePace),
        ("Switch from follow script to adaptive pace for me please", "{\"action\":\"adaptive_pace\"}", .adaptivePace),
        ("Let's stop for now", "{\"action\":\"pause\"}", .pause)
    ]
    for (request, output, expected) in structured { expectEqual(CommandIntent.interpret(output, request: request), expected) }
    for (request, output) in [
        ("Go down two paragraphs", "{\"action\":\"next_paragraph\"}"),
        ("Go to the tenth paragraph", "{\"action\":\"next_paragraph\"}"),
        ("Go to the last paragraph", "{\"action\":\"next_paragraph\"}"),
        ("Go to the second cue", "{\"action\":\"next_cue\"}"),
        ("Go back one paragraph", "{\"action\":\"go_to_paragraph\",\"value\":1}"),
        ("Go up two paragraphs", "{\"action\":\"move_paragraphs\",\"value\":2}"),
        ("Go back a bit", "{\"action\":\"resume\"}"),
        ("Pick it up at the start of this paragraph", "{\"action\":\"previous_paragraph\"}"),
        ("Go to cue two", "{\"action\":\"go_to_cue\",\"value\":3}"),
        ("Let's get this started", "{\"action\":\"restart_paragraph\"}"),
        ("Let's stop for now", "{\"action\":\"stop_listening\"}"),
        ("Set font size to 32", "{\"action\":\"smaller_text\"}"),
        ("Increase font size by 40", "{\"action\":\"set_font_size\",\"value\":40}"),
        ("Switch from follow script to adaptive pace", "{\"action\":\"follow_script\"}")
    ] { expectTrue(CommandIntent.interpret(output, request: request) == nil) }
    for output in ["{\"action\":\"go_to_cue\",\"value\":0}", "{\"action\":\"move_paragraphs\",\"value\":11}", "{\"action\":\"set_font_size\",\"value\":31}", "{\"action\":\"go_to_paragraph\",\"value\":true}", "{\"action\":\"pause\",\"value\":1}"] {
        expectTrue(CommandIntent.decode(output) == nil)
    }
    expectEqual(VoiceCommand.parse("Let's stop for now"), .pause)
    expectEqual(VoiceCommand.parse("Go to the next Q-point"), .cue(1))
    expectEqual(VoiceCommand.parse("Go to the next Q, point"), .cue(1))
    expectFalse(CommandIntent.acceptsRequest("Go to paragraph minus two"))
    // Keep a longer command intact across rolling windows, without firing a partial prefix.
    var longer = VoiceCommandRouter()
    let lead = words("Hey Teleprompter switch voice prompting from adaptive pace", from: 0)
    expectEqual(longer.consume(lead, audioEnd: 2, quiet: false, interpretUnknown: true), .listening)
    let middle = words("to", from: 5)
    expectEqual(longer.consume(middle, audioEnd: 6, quiet: false, interpretUnknown: true), .listening)
    let ending = words("follow script", from: 7)
    expectEqual(longer.consume(ending, audioEnd: 7.5, quiet: false, interpretUnknown: true), .listening)
    expectEqual(longer.consume(ending, audioEnd: 8, quiet: true, interpretUnknown: true), .interpret("switch voice prompting from adaptive pace to follow script"))
    var bounded = VoiceCommandRouter()
    expectEqual(bounded.consume(lead, audioEnd: 2, quiet: false, interpretUnknown: true), .listening)
    expectEqual(bounded.consume(words("and more", from: 13), audioEnd: 14.1, quiet: false, interpretUnknown: true), .unrecognized)

    // Live regressions: polite conjunctions remain one action; real compound requests do not.
    expectEqual(VoiceCommand.parse("Could you go ahead and pause"), .pause)
    expectEqual(VoiceCommand.parse("Go ahead and resume"), .resume)
    expectFalse(CommandIntent.acceptsRequest("Go ahead and pause and change the font"))
    expectFalse(CommandIntent.acceptsRequest("Can this change the font to Georgia"))
    expectEqual(CommandIntent.interpret("{\"action\":\"move_paragraphs\",\"value\":2}", request: "Go down to paragraphs"), .paragraph(2))
    expectEqual(CommandIntent.interpret("{\"action\":\"go_to_cue\",\"value\":1}", request: "Go to the first key point"), .cueNumber(1))
    expectEqual(CommandIntent.interpret("{\"action\":\"follow_script\"}", request: "Switch from adaptive pace to the other mode"), .followScript)
    expectEqual(CommandIntent.interpret("{\"action\":\"follow_script\"}", request: "Switch to following"), .followScript)
    expectEqual(CommandIntent.interpret("{\"action\":\"toggle_voice_mode\"}", request: "Switch to the other mode"), .toggleVoiceMode)
    expectTrue(CommandIntent.interpret("{\"action\":\"adaptive_pace\"}", request: "Switch from adaptive pace to the other mode") == nil)
    expectTrue(CommandIntent.interpret("{\"action\":\"toggle_voice_mode\"}", request: "Switch from adaptive pace to the other mode") == nil)
    expectFalse(VoiceCommand.isIncomplete("Okay carry on from here"))
    expectTrue(VoiceCommand.isIncomplete("Switch from adaptive pace"))
    expectTrue(VoiceCommand.isIncomplete("Go back up two"))
    expectFalse(VoiceCommand.isIncomplete("Move the reading guide up"))
    var partial = VoiceCommandRouter()
    let prefix = words("Hey Teleprompter go back up")
    expectEqual(partial.consume(prefix, audioEnd: 2, quiet: true, interpretUnknown: true), .listening)
    expectEqual(partial.consume(prefix, audioEnd: 3, quiet: true, interpretUnknown: true), .listening)
    let completed = words("Hey Teleprompter go back up two paragraphs")
    expectEqual(partial.consume(completed, audioEnd: 3.5, quiet: true, interpretUnknown: true), .listening)
    expectEqual(partial.consume(completed, audioEnd: 4.1, quiet: true, interpretUnknown: true), .interpret("go back up two paragraphs"))
    var drift = VoiceCommandRouter()
    let badTiming = [CommandWord("Hey", start: 0, end: 0.2), CommandWord("Teleprompter", start: 0.2, end: 1.8)]
    expectEqual(drift.consume(badTiming, audioEnd: 2, quiet: true), .listening)
    let fixedTiming = words("Hey Teleprompter pause")
    expectEqual(drift.consume(fixedTiming, audioEnd: 2.4, quiet: true), .listening)
    expectEqual(drift.consume(fixedTiming, audioEnd: 2.8, quiet: true), .execute(.pause))
    expectEqual(drift.consume(fixedTiming, audioEnd: 3.2, quiet: true), .reading)
    var padding = VoiceCommandRouter()
    let padded = words("Hey Teleprompter go back two lines") + [CommandWord("[BLANK_AUDIO]", start: 32, end: 33)]
    expectEqual(padding.consume(padded, audioEnd: 2, quiet: true), .listening)
    expectEqual(padding.consume(padded, audioEnd: 2.6, quiet: true), .execute(.lines(-2)))
    expectEqual(padding.consume(padded, audioEnd: 3, quiet: true), .reading)
    var retry = VoiceCommandRouter()
    expectEqual(retry.consume(prefix, audioEnd: 2, quiet: true), .listening)
    let twice = prefix + words("Hey Teleprompter resume", from: 3)
    expectEqual(retry.consume(twice, audioEnd: 4, quiet: true), .listening)
    expectEqual(retry.consume(twice, audioEnd: 4.5, quiet: true), .execute(.resume))
    expectEqual(retry.consume(twice, audioEnd: 5, quiet: true), .reading)
    var settings = PromptSettings()
    expectEqual(VoiceCommand.typeface(.georgia).applyAppearance(to: &settings), "Typeface · Georgia")
    expectEqual(settings.typeface, .georgia)
    settings.lineSpacing = 2
    _ = VoiceCommand.lineSpacing(1).applyAppearance(to: &settings)
    expectEqual(settings.lineSpacing, 2)
    settings.margin = 55
    _ = VoiceCommand.margins(-1).applyAppearance(to: &settings)
    expectEqual(settings.margin, 55)
    settings.guidePosition = 0.15
    _ = VoiceCommand.guidePosition(-1).applyAppearance(to: &settings)
    expectEqual(settings.guidePosition, 0.15)
    _ = VoiceCommand.guideVisible(false).applyAppearance(to: &settings)
    _ = VoiceCommand.focusLine(false).applyAppearance(to: &settings)
    expectFalse(settings.showGuide)
    expectFalse(settings.focusMode)
    for (request, output) in [
        ("Move the reading guide up", "{\"action\":\"move_guide_down\"}"),
        ("Turn off focus current line", "{\"action\":\"focus_line_on\"}"),
        ("Make the margins smaller", "{\"action\":\"wider_margins\"}"),
        ("Change the font to Georgia", "{\"action\":\"font_verdana\"}"),
        ("Increase line spacing by two", "{\"action\":\"increase_line_spacing\"}")
    ] { expectTrue(CommandIntent.interpret(output, request: request) == nil) }

    for request in ["Increase the line height", "Increase the line height a little bit", "Up the line height", "Can you make the line height bigger", "Increase the line spacing"] {
        expectEqual(CommandIntent.interpret("{\"action\":\"increase_line_spacing\"}", request: request), .lineSpacing(1))
        expectTrue(CommandIntent.interpret("{\"action\":\"increase_guide_height\"}", request: request) == nil)
        expectTrue(CommandIntent.interpret("{\"action\":\"move_guide_up\"}", request: request) == nil)
    }
    for request in ["Increase the reading guide height", "Make the reading guide bigger"] {
        expectEqual(CommandIntent.interpret("{\"action\":\"increase_guide_height\"}", request: request), .guideHeight(1))
        expectTrue(CommandIntent.interpret("{\"action\":\"increase_line_spacing\"}", request: request) == nil)
    }
    expectFalse(VoiceCommand.isIncomplete("Turn the line height up"))
    // Guide height must not become guide movement or script navigation.
    for (request, output, expected) in [
        ("Make the reading guide taller", "{\"action\":\"increase_guide_height\"}", VoiceCommand.guideHeight(1)),
        ("Show fewer lines in the reading guide", "{\"action\":\"decrease_guide_height\"}", .guideHeight(-1)),
        ("Set guide height to two lines", "{\"action\":\"set_guide_height\",\"value\":2}", .guideLines(2)),
        ("Make the focus area taller", "{\"action\":\"increase_guide_height\"}", .guideHeight(1))
    ] { expectEqual(CommandIntent.interpret(output, request: request), expected) }
    for (request, output) in [
        ("Turn the guide height up", "{\"action\":\"move_guide_up\"}"),
        ("Move the guide up", "{\"action\":\"increase_guide_height\"}"),
        ("Set guide height to two lines", "{\"action\":\"forward_2_lines\"}"),
        ("Set guide height to two lines", "{\"action\":\"set_guide_height\",\"value\":3}"),
        ("Move the guide up two lines", "{\"action\":\"set_guide_height\",\"value\":2}"),
        ("Show more lines in the guide", "{\"action\":\"show_reading_guide\"}"),
        ("Set guide height to four lines", "{\"action\":\"set_guide_height\",\"value\":4}")
    ] { expectTrue(CommandIntent.interpret(output, request: request) == nil) }
    settings.guideLines = 1
    let preservedPosition = settings.guidePosition
    _ = VoiceCommand.guideHeight(-1).applyAppearance(to: &settings)
    expectEqual(settings.guideLines, 1)
    _ = VoiceCommand.guideHeight(1).applyAppearance(to: &settings)
    expectEqual(settings.guideLines, 2)
    _ = VoiceCommand.guideLines(3).applyAppearance(to: &settings)
    _ = VoiceCommand.guideHeight(1).applyAppearance(to: &settings)
    expectEqual(settings.guideLines, 3)
    expectEqual(settings.guidePosition, preservedPosition)
    expectFalse(settings.showGuide)

    let laptopScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)
    let laptopVisible = CGRect(x: 0, y: 64, width: 1470, height: 859)
    // Camera guide movement uses the available reading area, not the old 16% cap.
    let compactBand = CGRect(x: 0, y: -8, width: 1000, height: 92)
    let cameraGuideRange = CameraViewGeometry.guideRange(viewportHeight: 300, lineHeight: 80, guideLines: 1)
    expectTrue(cameraGuideRange.upperBound > 0.7)
    expectEqual(cameraGuideRange.upperBound * 300 + compactBand.maxY, 300, accuracy: 0.00001)
    expectEqual(cameraGuideRange.lowerBound * 300 + compactBand.minY, 0, accuracy: 0.00001)
    let expandedBand = CGRect(x: 0, y: -8, width: 1000, height: 172)
    let expandedRange = CameraViewGeometry.guideRange(viewportHeight: 300, lineHeight: 80, guideLines: 2)
    expectEqual(expandedRange.upperBound * 300 + expandedBand.maxY, 300, accuracy: 0.00001)
    expectTrue(expandedRange.upperBound > 0.1625)
    expectTrue(CameraViewGeometry.guideRange(viewportHeight: 600, lineHeight: 80, guideLines: 2).upperBound > expandedRange.upperBound)
    let oversizedRange = CameraViewGeometry.guideRange(viewportHeight: 100, lineHeight: 80, guideLines: 2)
    expectEqual(oversizedRange.lowerBound, oversizedRange.upperBound)
    expectEqual(CameraViewGeometry.guideRange(viewportHeight: 0, lineHeight: 80, guideLines: 2), 0...0)
    let cameraFrame = CameraViewGeometry.frame(screen: laptopScreen, visible: laptopVisible, safeTop: 32)
    expectTrue(laptopVisible.contains(cameraFrame))
    expectTrue(cameraFrame.maxY < laptopScreen.maxY - 32)
    expectEqual(cameraFrame.midX, laptopScreen.midX)
    let external = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let externalCamera = CameraViewGeometry.frame(screen: external, visible: external.insetBy(dx: 0, dy: 24), safeTop: 0)
    expectTrue(external.contains(externalCamera))
    expectEqual(externalCamera.midX, external.midX)
    let smallScreen = CGRect(x: 0, y: 0, width: 800, height: 600)
    let smallCamera = CameraViewGeometry.frame(screen: smallScreen, visible: smallScreen, safeTop: 0, size: CGSize(width: 1000, height: 900))
    expectTrue(smallScreen.contains(smallCamera))

    var script = Script(title: "Navigation", text: "First paragraph has enough words to wrap across several reading lines. Keep reading this opening.\n\nSecond paragraph is here with another sentence and more words.\n\nThird paragraph finishes the script.")
    script.settings.fontSize = 58
    let layout = ScriptCueLayout(script)
    let second = (script.text as NSString).range(of: "Second").location
    let third = (script.text as NSString).range(of: "Third").location
    expectEqual(VoiceNavigation.destination(for: .paragraph(1), script: script, progress: 0), layout.progress(at: second))
    expectEqual(VoiceNavigation.destination(for: .paragraph(0), script: script, progress: layout.progress(at: second) + 0.01), layout.progress(at: second))
    expectEqual(VoiceNavigation.destination(for: .paragraph(-1), script: script, progress: layout.progress(at: third)), layout.progress(at: second))
    expectEqual(VoiceNavigation.destination(for: .top, script: script, progress: 0.8), 0)
    expectEqual(VoiceNavigation.destination(for: .lines(-10), script: script, progress: 0), 0)
    let nextLine = VoiceNavigation.destination(for: .lines(1), script: script, progress: 0)!
    expectTrue(nextLine > 0 && nextLine < layout.progress(at: second))
    expectEqual(VoiceNavigation.destination(for: .lines(-1), script: script, progress: nextLine), 0)
    expectTrue(VoiceNavigation.destination(for: .cue(-1), script: script, progress: 0.8) == nil)
    script.cues = [Cue(title: "Second", progress: 0, characterOffset: second)]
    expectEqual(VoiceNavigation.destination(for: .cue(-1), script: script, progress: layout.progress(at: third)), layout.progress(at: second))
    expectEqual(VoiceNavigation.destination(for: .cue(1), script: script, progress: 0), layout.progress(at: second))
    script.cues.append(Cue(title: "Third", progress: 0, characterOffset: third))
    expectEqual(VoiceNavigation.destination(for: .cueNumber(2), script: script, progress: 0), layout.progress(at: third))
    expectTrue(VoiceNavigation.destination(for: .cueNumber(3), script: script, progress: 0) == nil)
    expectEqual(VoiceNavigation.destination(for: .paragraph(2), script: script, progress: 0), layout.progress(at: third))
    expectTrue(VoiceNavigation.destination(for: .paragraph(3), script: script, progress: 0) == nil)
    expectEqual(VoiceNavigation.destination(for: .paragraphNumber(2), script: script, progress: 0), layout.progress(at: second))
    expectEqual(VoiceNavigation.destination(for: .lastParagraph, script: script, progress: 0), layout.progress(at: third))
    expectTrue(VoiceNavigation.destination(for: .paragraphNumber(10), script: script, progress: 0) == nil)
    let empty = Script(title: "Empty", text: "")
    expectEqual(VoiceNavigation.destination(for: .lines(2), script: empty, progress: 0), 0)
    expectEqual(VoiceNavigation.destination(for: .paragraph(1), script: empty, progress: 0), 0)
}
