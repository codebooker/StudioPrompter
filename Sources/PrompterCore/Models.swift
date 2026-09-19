import Foundation

public enum ScriptTypeface: String, Codable, CaseIterable, Identifiable {
    case system, avenirNext, verdana, georgia
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .system: return "System"
        case .avenirNext: return "Avenir Next"
        case .verdana: return "Verdana"
        case .georgia: return "Georgia"
        }
    }
}

public struct PromptSettings: Codable, Equatable {
    public var wordsPerMinute: Double = 140
    public var fontSize: Double = 54
    public var lineSpacing: Double = 1.45
    public var margin: Double = 100
    public var countdown: Int = 3
    public var mirrorHorizontal = false
    public var mirrorVertical = false
    public var showGuide = true
    public var guidePosition: Double = 0.32
    public var guideLines: Double = 1
    public var focusMode = true
    public var typeface: ScriptTypeface = .system
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case wordsPerMinute, fontSize, lineSpacing, margin, countdown, mirrorHorizontal, mirrorVertical, showGuide, guidePosition, guideLines, focusMode, typeface
    }
    private enum LegacyCodingKeys: String, CodingKey { case serifFont }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        wordsPerMinute = try values.decodeIfPresent(Double.self, forKey: .wordsPerMinute) ?? 140
        fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? 54
        lineSpacing = try values.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 1.45
        margin = try values.decodeIfPresent(Double.self, forKey: .margin) ?? 100
        countdown = try values.decodeIfPresent(Int.self, forKey: .countdown) ?? 3
        mirrorHorizontal = try values.decodeIfPresent(Bool.self, forKey: .mirrorHorizontal) ?? false
        mirrorVertical = try values.decodeIfPresent(Bool.self, forKey: .mirrorVertical) ?? false
        showGuide = try values.decodeIfPresent(Bool.self, forKey: .showGuide) ?? true
        guidePosition = try values.decodeIfPresent(Double.self, forKey: .guidePosition) ?? 0.32
        guideLines = try values.decodeIfPresent(Double.self, forKey: .guideLines) ?? 1
        focusMode = try values.decodeIfPresent(Bool.self, forKey: .focusMode) ?? true
        if let savedFont = try values.decodeIfPresent(String.self, forKey: .typeface) {
            typeface = ScriptTypeface(rawValue: savedFont) ?? .system
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            typeface = (try legacy.decodeIfPresent(Bool.self, forKey: .serifFont) ?? false) ? .georgia : .system
        }
    }
}

public struct Cue: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var progress: Double
    public init(title: String, progress: Double) {
        id = UUID()
        self.title = title
        self.progress = min(1, max(0, progress))
    }
}

public struct Script: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var text: String
    public var modified: Date
    public var settings: PromptSettings
    public var cues: [Cue]
    public init(title: String, text: String, cues: [Cue] = []) {
        id = UUID()
        self.title = title
        self.text = text
        modified = Date()
        settings = PromptSettings()
        self.cues = cues
    }
    public var wordCount: Int { Self.countWords(text) }
    public static func countWords(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
    public var duration: Double { Double(wordCount) / max(1, settings.wordsPerMinute) * 60 }
}

public struct Library: Codable {
    public var version = 1
    public var scripts: [Script]
    public var selectedID: UUID?
    public init(scripts: [Script], selectedID: UUID? = nil) {
        self.scripts = scripts
        self.selectedID = selectedID ?? scripts.first?.id
    }
}

public enum LibraryStore {
    public static func load(from url: URL) throws -> Library {
        let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: url))
        guard library.version == 1 else { throw StoreError.unsupportedVersion }
        return library
    }
    public static func save(_ library: Library, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: url, options: .atomic)
    }
    public enum StoreError: Error { case unsupportedVersion }
}

/// A clock-independent transport; all motion is based on elapsed time, not frame count.
public struct Transport {
    public private(set) var progress: Double = 0
    public private(set) var elapsed: Double = 0
    public private(set) var isPlaying = false
    public private(set) var countdownRemaining: Double = 0
    private var followMotion = FollowMotion()
    public init() {}
    public mutating func play(countdown: Int, hasContent: Bool) {
        guard hasContent else { return }
        if progress >= 1 { reset() }
        countdownRemaining = Double(max(0, countdown))
        isPlaying = true
    }
    public mutating func pause() { isPlaying = false; countdownRemaining = 0; followMotion = FollowMotion() }
    public mutating func reposition(to value: Double, preservingPlayback: Bool) {
        let resume = preservingPlayback && isPlaying
        pause()
        seek(to: value)
        if resume && progress < 1 { play(countdown: 0, hasContent: true) }
    }
    public mutating func reset() { progress = 0; elapsed = 0; pause() }
    public mutating func seek(to value: Double) { followMotion = FollowMotion(); progress = min(1, max(0, value)); if progress >= 1 { pause() } }
    public mutating func follow(seconds: Double, target: Double?, lineStep: Double) {
        guard isPlaying, seconds > 0, seconds.isFinite else { return }
        let countdownTime = min(countdownRemaining, seconds)
        countdownRemaining -= countdownTime
        let remaining = seconds - countdownTime
        guard remaining > 0, let target else { followMotion = FollowMotion(); return }
        elapsed += remaining
        progress = followMotion.advance(from: progress, to: target, seconds: remaining, lineStep: lineStep)
        if target >= 1, 1 - progress < 0.000001 { progress = 1; pause() }
    }
    public mutating func adapt(seconds: Double, duration: Double, speaking: Bool, target: Double?, lineStep: Double) {
        guard isPlaying, seconds > 0, seconds.isFinite else { return }
        let countdownTime = min(countdownRemaining, seconds)
        countdownRemaining -= countdownTime
        let remaining = seconds - countdownTime
        guard remaining > 0, speaking else { followMotion = FollowMotion(); return }
        guard duration > 0, duration.isFinite else { pause(); return }
        let previous = progress
        var next = previous + remaining / duration
        if let target, target.isFinite, lineStep > 0 {
            // Cadence drives ordinary scrolling. A confirmed phrase keeps the
            // reader within a quarter line, correcting drift without a jump.
            let lower = max(0, target - lineStep * 0.25)
            let correction = followMotion.advance(from: previous, to: lower, seconds: remaining, lineStep: lineStep)
            next = max(next, correction)
            next = min(next, max(previous, target + lineStep * 0.25))
        } else { followMotion = FollowMotion() }
        progress = min(1, next)
        if progress > previous { elapsed += remaining }
        if progress >= 1 { pause() }
    }
    public mutating func tick(seconds: Double, duration: Double) {
        followMotion = FollowMotion()
        guard isPlaying, seconds > 0, seconds.isFinite else { return }
        var remaining = seconds
        if countdownRemaining > 0 {
            let consumed = min(countdownRemaining, remaining)
            countdownRemaining -= consumed
            remaining -= consumed
        }
        guard remaining > 0 else { return }
        guard duration > 0, duration.isFinite else { pause(); return }
        let consumed = min(remaining, (1 - progress) * duration)
        elapsed += consumed
        progress = min(1, progress + consumed / duration)
        if progress >= 1 - 0.0000001 { progress = 1; pause() }
    }
}

public enum Samples {
    public static let scripts: [Script] = [
        Script(title: "A little room for big ideas", text: """
        Every great idea starts with a little room.

        Room to be curious. Room to try something different. And room to get it wonderfully, unexpectedly wrong.

        Today, I want to talk about what happens when we give ourselves that space.

        We spend so much of our time waiting for the right moment. The perfect plan. The invitation that says we're finally ready.

        But the people who make things happen rarely begin with certainty. They begin with a question.

        What if we made this simpler?

        What if we tried it together?

        What if the thing we've been putting off is exactly the thing we need to start?

        Here's what I've learned: you don't need to see the whole path to take the first step.

        Start small. Write the first page. Have the conversation. Make something you can hold in your hands, even if it isn't quite what you imagined.

        Then listen. Pay attention to what works, and be honest about what doesn't. The next version will be better because you made this one.

        And remember to bring other people in. The best ideas get stronger when they have somewhere to go, and someone to challenge them.

        So here's my invitation to you today.

        Pick one idea. Give it a little room. Spend twenty minutes moving it forward.

        You might be surprised by what happens next.

        Thank you.
        """, cues: [Cue(title: "Opening", progress: 0), Cue(title: "The first step", progress: 0.48), Cue(title: "The invitation", progress: 0.84)]),
        Script(title: "The weekly update", text: """
        Hi everyone. Welcome to this week's update.

        Let's start with what we've accomplished. We took a complicated problem, broke it into smaller pieces, and made real progress together.

        A special thank you to everyone who shared feedback early. Your questions helped us focus on the things that matter.

        This week, we have three priorities.

        First, finish the work that's already in motion. Second, make time to test our assumptions. And third, keep each other informed along the way.

        If something is blocking you, please reach out. You don't have to figure it out alone.

        That's all from me. Thanks for the care you bring to your work, and have a great week.
        """),
        Script(title: "Before you press record", text: """
        Take a breath. Let your shoulders drop.

        You're talking to one person, not a room full of strangers. Picture someone who's interested in what you have to say.

        Speak a little slower than feels natural. Leave room between your thoughts.

        If you stumble, pause and start the sentence again. You can always make another take.

        You know this material. You have something worth sharing.

        Ready? Let's begin.
        """)
    ]
}
