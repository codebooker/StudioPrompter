import Foundation

public enum VoiceCommand: Equatable, Sendable {
    case lines(Int), paragraph(Int), paragraphNumber(Int), lastParagraph, top, cue(Int), cueNumber(Int), font(Int), fontSize(Int), followScript, adaptivePace, pause, resume, cancel, stopListening

    public static func parse(_ text: String) -> VoiceCommand? {
        var phrase = tokens(text).joined(separator: " ")
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
    public static func tokens(_ text: String) -> [String] {
        let raw = text.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "let's", with: "lets")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return raw.indices.flatMap { index -> [String] in
            if raw[index] == "qpoint" { return ["cue", "point"] }
            if raw[index] == "q", index + 1 < raw.count, ["point", "points"].contains(raw[index + 1]) { return ["cue"] }
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
        let tokens = words.flatMap { word in VoiceCommand.tokens(word.text).map { CommandWord($0, start: word.start, end: word.end) } }
        if !isListening {
            let fresh = tokens.filter { $0.start >= consumedThrough }
            if fresh.count >= 2, let index = (0..<(fresh.count - 1)).first(where: {
                fresh[$0].text == "hey" && fresh[$0 + 1].text == "teleprompter" && fresh[$0 + 1].end - fresh[$0].start < 2
            }) {
                isListening = true
                wakeEnd = fresh[index + 1].end
                deadline = audioEnd + 6
                hardDeadline = audioEnd + 12
                commandWords = []
                candidate = ""; candidateSince = audioEnd
            } else { return .reading }
        }
        // A wake phrase can arrive alone; later windows complete its instruction.
        let tail = tokens.filter { $0.start >= wakeEnd - 0.05 && $0.end > wakeEnd + 0.05 }
        // Retain the beginning when a longer request leaves Whisper's rolling window.
        // Replace overlapping hypotheses so corrected words/counts remain authoritative.
        if let first = tail.first {
            commandWords = commandWords.filter { $0.end < first.start - 0.05 } + tail
            if let last = tail.last { deadline = min(hardDeadline, max(deadline, last.end + 2)) }
        }
        let phrase = commandWords.map(\.text).joined(separator: " ")
        if phrase != candidate { candidate = phrase; candidateSince = audioEnd }
        let settled = audioEnd < hardDeadline && !tail.isEmpty && !phrase.isEmpty && quiet && audioEnd - (commandWords.last?.end ?? audioEnd) >= 0.45 && audioEnd - candidateSince >= 0.25
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
