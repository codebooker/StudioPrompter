import Foundation

public enum VoiceCommand: Equatable, Sendable {
    case lines(Int), paragraph(Int), paragraphNumber(Int), lastParagraph, top, cue(Int), cueNumber(Int), font(Int), fontSize(Int), followScript, adaptivePace, toggleVoiceMode, typeface(ScriptTypeface), lineSpacing(Int), margins(Int), guideVisible(Bool), guidePosition(Int), focusLine(Bool), pause, resume, cancel, stopListening

    /// Applies bounded appearance changes. The app preserves the current reading anchor.
    public func applyAppearance(to settings: inout PromptSettings) -> String? {
        switch self {
        case .font(let delta): settings.fontSize = min(90, max(32, settings.fontSize + Double(delta)))
        case .fontSize(let size): settings.fontSize = min(90, max(32, Double(size)))
        case .typeface(let font): settings.typeface = font
        case .lineSpacing(let direction): settings.lineSpacing = min(2, max(1.1, settings.lineSpacing + Double(direction.signum()) * 0.1))
        case .margins(let direction): settings.margin = min(220, max(55, settings.margin + Double(direction.signum()) * 10))
        case .guideVisible(let visible): settings.showGuide = visible
        case .guidePosition(let direction): settings.guidePosition = min(0.65, max(0.15, settings.guidePosition + Double(direction.signum()) * 0.03))
        case .focusLine(let enabled): settings.focusMode = enabled
        default: return nil
        }
        switch self {
        case .font, .fontSize: return "Text size \(Int(settings.fontSize))"
        case .typeface: return "Typeface · \(settings.typeface.name)"
        case .lineSpacing: return String(format: "Line spacing · %.1f×", settings.lineSpacing)
        case .margins: return "Side margins · \(Int(settings.margin / 10))%"
        case .guideVisible: return "Reading guide \(settings.showGuide ? "on" : "off")"
        case .guidePosition: return "Guide position · \(Int((settings.guidePosition * 100).rounded()))%"
        case .focusLine: return "Focus current line \(settings.focusMode ? "on" : "off")"
        default: return nil
        }
    }

    public static func parse(_ text: String) -> VoiceCommand? {
        var phrase = requestTokens(text).joined(separator: " ")
        let prefixes = ["can we ", "can you ", "could you ", "would you ", "please ", "lets ", "let us "]
        while let prefix = prefixes.first(where: { phrase.hasPrefix($0) }) { phrase.removeFirst(prefix.count) }
        if phrase.hasSuffix(" please") { phrase.removeLast(7) }
        switch phrase {
        case "pause", "pause the script", "stop", "stop scrolling", "stop for now": return .pause
        case "start", "start the script", "go", "resume", "resume the script", "continue", "keep going", "start scrolling", "play", "play the script", "get this started": return .resume
        case "cancel", "never mind", "nevermind": return .cancel
        case "stop listening", "turn off the microphone", "turn off the mic": return .stopListening
        case "start from the top", "start from the top of the document", "start from the top of the script", "go to the top", "back to the top", "start over", "restart the script": return .top
        case "start this paragraph over", "start the paragraph over", "restart this paragraph", "restart the paragraph", "repeat this paragraph": return .paragraph(0)
        case "next paragraph", "go to the next paragraph", "move to the next paragraph", "skip this paragraph": return .paragraph(1)
        case "last paragraph": return .lastParagraph
        case "previous paragraph", "go back a paragraph", "go back one paragraph", "go to the previous paragraph": return .paragraph(-1)
        case "last cue", "previous cue", "last cue point", "go back to the last cue point", "go back to the last cue", "go to the previous cue", "go to the previous cue point": return .cue(-1)
        case "next cue", "next cue point", "go to the next cue", "go to the next cue point": return .cue(1)
        case "increase the font size", "increase font size", "bigger text", "larger text", "make the text bigger", "make the font bigger": return .font(4)
        case "decrease the font size", "decrease font size", "smaller text", "make the text smaller", "make the font smaller": return .font(-4)
        default: break
        }
        if phrase.hasPrefix("rewind ") { phrase = "back " + phrase.dropFirst(7) }
        let pattern = "^(?:go |scroll |move |rewind )?(back(?: up)?|up|forward|down) (a|one|two|to|three|four|five|six|seven|eight|nine|ten|[1-9]|10) lines?$"
        let regex = try! NSRegularExpression(pattern: pattern)
        let source = phrase as NSString
        guard let match = regex.firstMatch(in: phrase, range: NSRange(location: 0, length: source.length)) else { return nil }
        let direction = source.substring(with: match.range(at: 1))
        let quantity = source.substring(with: match.range(at: 2))
        let names = ["a": 1, "one": 1, "two": 2, "to": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]
        let count = names[quantity] ?? Int(quantity) ?? 1
        return .lines(["forward", "down"].contains(direction) ? count : -count)
    }
    /// Normalize speech artifacts only in their command context, never in script text.
    public static func requestTokens(_ text: String) -> [String] {
        var phrase = tokens(text).joined(separator: " ")
        let prefixes = ["can we ", "can you ", "could we ", "could you ", "would you ", "please ", "okay ", "lets ", "let us ", "go ahead and "]
        while let prefix = prefixes.first(where: { phrase.hasPrefix($0) }) { phrase.removeFirst(prefix.count) }
        var words = phrase.split(separator: " ").map(String.init)
        for i in words.indices where i > 0 && i + 1 < words.count {
            if words[i] == "to", ["up", "down", "back", "forward"].contains(words[i - 1]), ["lines", "paragraphs"].contains(words[i + 1]) { words[i] = "two" }
        }
        return words
    }
    /// Do not submit an obviously unfinished instruction during a mid-sentence pause.
    public static func isIncomplete(_ text: String) -> Bool {
        let words = requestTokens(text)
        guard let last = words.last, parse(text) == nil else { return false }
        if words.contains("guide"), ["up", "down"].contains(last) { return false }
        if ["to", "from", "the", "a", "an", "by", "up", "down", "back", "forward", "with", "and", "of"].contains(last) { return true }
        if words.contains("from"), !words.contains("to"), !Set(words).isDisjoint(with: ["switch", "change"]) { return true }
        let countEnding = Int(last) != nil || ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"].contains(last)
        if countEnding && !Set(words).isDisjoint(with: ["back", "up", "down", "forward"]) &&
            Set(words).isDisjoint(with: ["line", "lines", "paragraph", "paragraphs", "cue", "cues", "font", "size"]) { return true }
        return false
    }
    public static func tokens(_ text: String) -> [String] {
        let raw = text.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "let's", with: "lets")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return raw.indices.flatMap { index -> [String] in
            if raw[index] == "qpoint" { return ["cue", "point"] }
            if ["q", "key"].contains(raw[index]), index + 1 < raw.count, ["point", "points"].contains(raw[index + 1]) { return ["cue"] }
            return [raw[index]]
        }
    }
}

public struct CommandWord: Sendable {
    public let text: String
    public let start: Double
    public let end: Double
    public init(_ text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
}

/// Routes rolling/revised Whisper windows before pace or script matching.
/// Absolute audio timestamps prevent a completed wake phrase from firing again.
public struct VoiceCommandRouter {
    public enum Event: Equatable { case reading, listening, execute(VoiceCommand), interpret(String), unrecognized }
    public private(set) var isListening = false
    public private(set) var consumedThrough: Double
    private var wakeEnd = 0.0
    private var deadline = 0.0
    private var hardDeadline = 0.0
    private var commandWords: [CommandWord] = []
    private var candidate = ""
    private var candidateSince = 0.0
    public init(after time: Double = 0) { consumedThrough = time }

    public mutating func consume(_ words: [CommandWord], audioEnd: Double, quiet: Bool, interpretUnknown: Bool = false) -> Event {
        // Whisper occasionally timestamps padding/hallucinated words beyond the audio window.
        // Such words must not postpone completion or extend a command's deadline.
        let valid = words.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start && $0.end <= audioEnd + 0.1 }
        let tokens = valid.flatMap { word in VoiceCommand.tokens(word.text).map { CommandWord($0, start: word.start, end: word.end) } }
        // Use the latest fresh wake phrase, including a repeated wake during a retry.
        // Slice by token order when it is visible: Whisper can revise word timestamps.
        let wakeIndex = tokens.count < 2 ? nil : (0..<(tokens.count - 1)).last(where: {
            tokens[$0].start >= consumedThrough && tokens[$0].text == "hey" &&
            tokens[$0 + 1].text == "teleprompter" && tokens[$0 + 1].end - tokens[$0].start < 2
        })
        if !isListening {
            guard let index = wakeIndex else { return .reading }
            isListening = true
            wakeEnd = tokens[index + 1].end
            deadline = audioEnd + 6
            hardDeadline = audioEnd + 12
            commandWords = []; candidate = ""; candidateSince = audioEnd
        }
        let tail: [CommandWord]
        if let index = wakeIndex {
            let revisedEnd = tokens[index + 1].end
            if tokens[index].start > wakeEnd + 0.5 {
                // A newly spoken wake replaces an unfinished request, within the same hard limit.
                deadline = min(hardDeadline, audioEnd + 6)
                candidate = ""; candidateSince = audioEnd
            }
            wakeEnd = revisedEnd
            tail = Array(tokens.dropFirst(index + 2))
            commandWords = tail
        } else {
            tail = tokens.filter { $0.start >= wakeEnd - 0.05 && $0.end > wakeEnd + 0.05 }
            // Retain a longer instruction's prefix after it leaves the rolling window.
            if let first = tail.first {
                commandWords = commandWords.filter { $0.end < first.start - 0.05 } + tail
            }
        }
        if let last = tail.last { deadline = min(hardDeadline, max(deadline, last.end + 2)) }
        let phrase = commandWords.map(\.text).joined(separator: " ")
        if phrase != candidate { candidate = phrase; candidateSince = audioEnd }
        let complete = !VoiceCommand.isIncomplete(phrase)
        let settleTime = VoiceCommand.parse(phrase) == nil ? 0.4 : 0.25
        let settled = complete && audioEnd < hardDeadline && !tail.isEmpty && !phrase.isEmpty && quiet && audioEnd - (commandWords.last?.end ?? audioEnd) >= 0.45 && audioEnd - candidateSince >= settleTime
        if settled || audioEnd >= deadline {
            let command = settled ? VoiceCommand.parse(phrase) : nil
            isListening = false
            consumedThrough = audioEnd
            candidate = ""
            if let command { return .execute(command) }
            return settled && interpretUnknown ? .interpret(phrase) : .unrecognized
        }
        return .listening
    }
}
