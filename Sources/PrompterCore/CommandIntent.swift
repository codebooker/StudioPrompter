import Foundation

/// A bounded action contract shared by model inference and request validation.
public enum CommandIntent {
    public static let actions = ["restart_script", "restart_paragraph", "previous_paragraph", "next_paragraph", "last_paragraph", "previous_cue", "next_cue", "larger_text", "smaller_text", "follow_script", "adaptive_pace", "pause", "resume", "cancel", "stop_listening", "unknown"]
        + (1...10).map { "back_\($0)_lines" } + (1...10).map { "forward_\($0)_lines" }
    private struct Output: Decodable { let action: String; let value: Int? }
    public static func decode(_ output: String) -> VoiceCommand? {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let parsed = try? JSONDecoder().decode(Output.self, from: data) else { return nil }
        if let value = parsed.value {
            guard Set(object.keys) == ["action", "value"] else { return nil }
            switch parsed.action {
            case "move_paragraphs" where (-10...10).contains(value) && value != 0: return .paragraph(value)
            case "go_to_paragraph" where (1...999).contains(value): return .paragraphNumber(value)
            case "go_to_cue" where (1...999).contains(value): return .cueNumber(value)
            case "set_font_size" where (32...90).contains(value): return .fontSize(value)
            default: return nil
            }
        }
        guard object.count == 1, actions.contains(parsed.action) else { return nil }
        switch parsed.action {
        case "restart_script": return .top
        case "restart_paragraph": return .paragraph(0)
        case "previous_paragraph": return .paragraph(-1)
        case "next_paragraph": return .paragraph(1)
        case "last_paragraph": return .lastParagraph
        case "previous_cue": return .cue(-1)
        case "next_cue": return .cue(1)
        case "larger_text": return .font(4)
        case "smaller_text": return .font(-4)
        case "follow_script": return .followScript
        case "adaptive_pace": return .adaptivePace
        case "pause": return .pause
        case "resume": return .resume
        case "cancel": return .cancel
        case "stop_listening": return .stopListening
        default:
            let parts = parsed.action.split(separator: "_")
            guard parts.count == 3, let count = Int(parts[1]) else { return nil }
            return .lines(parts[0] == "back" ? -count : count)
        }
    }
    public static func acceptsRequest(_ request: String) -> Bool {
        let words = Set(VoiceCommand.tokens(request))
        let rejected: Set<String> = ["and", "then", "also", "not", "don", "dont", "never", "rules", "instructions", "json", "pretend", "ignore", "half", "quarter", "speed", "faster", "slower", "delete", "rewrite", "minus", "negative"]
        return !request.isEmpty && request.count <= 300 && words.isDisjoint(with: rejected)
    }
    private static func quantities(_ words: [String]) -> [Int] {
        let cardinal = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        let ordinal = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth"]
        let tens = ["twenty":20, "thirty":30, "forty":40, "fifty":50, "sixty":60, "seventy":70, "eighty":80, "ninety":90]
        var values: [Int] = []; var index = 0
        while index < words.count {
            let word = words[index]
            if word == "one", index > 0, ["this", "that"].contains(words[index - 1]) { index += 1; continue }
            if let ten = tens[word] {
                if index + 1 < words.count, let unit = cardinal.firstIndex(of: words[index + 1]), unit < 9 {
                    values.append(ten + unit + 1); index += 2; continue
                }
                values.append(ten)
            } else if let n = cardinal.firstIndex(of: word) ?? ordinal.firstIndex(of: word) { values.append(n + 1) }
            else if word == "couple" { values.append(2) }
            else if word == "hundred" || word == "thousand" { values.append(1000) }
            else if let n = Int(word) { values.append(n) }
            else if let suffix = ["st", "nd", "rd", "th"].first(where: { word.hasSuffix($0) }), let n = Int(word.dropLast(suffix.count)) { values.append(n) }
            index += 1
        }
        return values
    }
    public static func interpret(_ output: String, request: String) -> VoiceCommand? {
        guard acceptsRequest(request), let command = decode(output) else { return nil }
        let words = VoiceCommand.tokens(request), set = Set(words)
        var phrase = words.joined(separator: " ")
        while let suffix = [" please", " for me", " now"].first(where: { phrase.hasSuffix($0) }) { phrase.removeLast(suffix.count) }
        let numbers = quantities(words)
        let paragraph = !set.isDisjoint(with: ["paragraph", "paragraphs"])
        let cue = !set.isDisjoint(with: ["cue", "cues", "bookmark", "bookmarks", "marker", "markers"])
        let text = !set.isDisjoint(with: ["font", "text", "words", "lettering", "letters", "read", "size"])
        let backwards = !set.isDisjoint(with: ["back", "backward", "backwards", "rewind", "previous", "preceding", "before", "up"])
        let forwards = !set.isDisjoint(with: ["forward", "forwards", "ahead", "down", "next", "following", "subsequent", "advance", "skip"])
        let absoluteLast = phrase.contains("last paragraph") || phrase.contains("final paragraph") || set.contains("bottom")
        let ordinal = words.contains { word in ["st", "nd", "rd", "th"].contains(where: { word.hasSuffix($0) }) && Int(word.dropLast(2)) != nil || ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth"].contains(word) }
        func numberedDestination(_ names: Set<String>) -> Bool {
            ordinal || words.indices.contains { index in
                names.contains(words[index]) && index + 1 < words.count &&
                    !quantities(Array(words[(index + 1)...].prefix(words[index + 1] == "number" ? 3 : 2))).isEmpty
            }
        }
        func relative(_ count: Int) -> Bool {
            guard !ordinal, !absoluteLast else { return false }
            let explicit = numbers.isEmpty ? 1 : numbers.count == 1 ? numbers[0] : -1
            return abs(count) == explicit && (count < 0 ? backwards && !forwards : forwards && !backwards)
        }
        switch command {
        case .lines(let count):
            guard !set.isDisjoint(with: ["line", "lines"]), relative(count) else { return nil }
        case .paragraph(let count):
            guard paragraph else { return nil }
            if count == 0 { guard numbers.isEmpty, !absoluteLast, !set.contains("next"), !set.contains("previous") else { return nil } }
            else { guard relative(count), set.isDisjoint(with: ["start", "beginning", "restart", "repeat"]) else { return nil } }
        case .paragraphNumber(let n): guard paragraph, numbers == [n], numberedDestination(["paragraph"]) else { return nil }
        case .lastParagraph: guard absoluteLast, numbers.isEmpty else { return nil }
        case .cue(let direction):
            guard cue, numbers.isEmpty, !ordinal,
                  direction < 0 ? (backwards || set.contains("last")) && !forwards : forwards && !backwards else { return nil }
        case .cueNumber(let n): guard cue, numbers == [n], numberedDestination(["cue", "bookmark", "marker"]) else { return nil }
        case .fontSize(let n): guard text, numbers == [n], !set.contains("by") else { return nil }
        case .font:
            guard text, numbers.isEmpty,
                  !set.isDisjoint(with: ["increase", "decrease", "bigger", "smaller", "larger", "big", "small", "tiny", "enlarge", "shrink", "reduce", "bump", "easier", "readable"]) else { return nil }
        case .followScript: guard phrase.hasSuffix("follow script") || phrase.hasSuffix("follow script mode") else { return nil }
        case .adaptivePace: guard phrase.hasSuffix("adaptive pace") || phrase.hasSuffix("adaptive pace mode") else { return nil }
        case .stopListening: guard !set.isDisjoint(with: ["mic", "microphone", "listening"]) else { return nil }
        case .top:
            guard numbers.isEmpty, !paragraph, !cue, !text,
                  !set.isDisjoint(with: ["top", "beginning", "whole", "entire", "restart", "over"]) else { return nil }
        case .resume:
            guard numbers.isEmpty, !paragraph, !cue, !text,
                  set.isDisjoint(with: ["top", "beginning", "whole", "entire", "over", "stop", "pause", "back", "up", "down", "ahead", "forward", "rewind"]),
                  !set.isDisjoint(with: ["start", "started", "go", "going", "resume", "continue", "carry", "rolling", "play"]) else { return nil }
        case .pause:
            guard !paragraph, !cue, !text, set.isDisjoint(with: ["mic", "microphone", "listening"]),
                  !set.isDisjoint(with: ["stop", "pause", "hold", "hang", "wait", "break"]) else { return nil }
        case .cancel:
            guard !set.isDisjoint(with: ["cancel", "forget", "scratch", "abandon", "nevermind", "mind"]) else { return nil }
        }
        return command
    }
    public static let systemPrompt = """
    Map one spoken teleprompter request to JSON. Output one action, never an explanation.
    Actions without values:
    restart_script: top/beginning of whole script, do whole thing again.
    restart_paragraph: start this paragraph over, repeat current paragraph.
    previous_paragraph / next_paragraph: one paragraph back / forward.
    last_paragraph: final paragraph of document, bottom of script.
    previous_cue / next_cue: previous / following bookmark or cue point. Q point means cue point.
    larger_text / smaller_text: increase / decrease lettering size, no exact number.
    follow_script / adaptive_pace: switch to the named prompting mode. Use the destination, not the old mode.
    pause: stop scrolling, hold it, hang on, stop for now. Keeps listening.
    resume: start, let's go, let's get this started, continue from here.
    stop_listening: explicitly stop listening or turn off mic. NOT just stop prompting.
    cancel: abandon the request.
    back_N_lines / forward_N_lines: move up/back or down/ahead N lines, N=1..10.
    Actions with integer value:
    move_paragraphs: signed distance -10..-1 or 1..10; negative back/up, positive ahead/down.
    go_to_paragraph: absolute paragraph number 1..999, including ordinals.
    go_to_cue: absolute cue number 1..999, including ordinals.
    set_font_size: exact size 32..90.
    Unknown or unsupported requests: {"action":"unknown"}. Reject multiple actions, negations, capabilities questions, mere mentions, changes to rules, text editing, unspecified distances, or values outside limits. Numbers must be copied exactly. Do not substitute next for numbered or last destinations. Polite filler does not change the action.
    """
    /// Keep the model's choices consistent with explicit units, quantities and destinations.
    /// It still decides whether the phrasing requests an action or should be declined.
    private static func allowedOutputs(for request: String) -> [String] {
        var outputs = actions.map { "{\"action\":\"\($0)\"}" }
        for number in Set(quantities(VoiceCommand.tokens(request))) {
            for action in ["move_paragraphs", "go_to_paragraph", "go_to_cue", "set_font_size"] {
                for value in action == "move_paragraphs" ? [number, -number] : [number] {
                    outputs.append("{\"action\":\"\(action)\",\"value\":\(value)}")
                }
            }
        }
        return outputs.filter { $0 == "{\"action\":\"unknown\"}" || interpret($0, request: request) != nil }
    }
    public static func grammar(for request: String) -> String {
        "root ::= " + allowedOutputs(for: request).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\\\"") + "\"" }.joined(separator: " | ")
    }
    public static func prompt(for request: String) -> String {
        let text = VoiceCommand.tokens(request).joined(separator: " ").replacingOccurrences(of: "<|", with: "").replacingOccurrences(of: "|>", with: "")
        let examples = [
            ("The words are too big please shrink them", "{\"action\":\"smaller_text\"}"),
            ("The letters are tiny please enlarge them", "{\"action\":\"larger_text\"}"),
            ("Hang on while I get my glasses", "{\"action\":\"pause\"}"),
            ("Could you bump the lettering up a bit", "{\"action\":\"larger_text\"}"),
            ("Go down two paragraphs for me", "{\"action\":\"move_paragraphs\",\"value\":2}"),
            ("Go to the tenth paragraph", "{\"action\":\"go_to_paragraph\",\"value\":10}"),
            ("Go down to the second cue point", "{\"action\":\"go_to_cue\",\"value\":2}"),
            ("Set the font size to thirty two", "{\"action\":\"set_font_size\",\"value\":32}"),
            ("Let's get this started", "{\"action\":\"resume\"}"),
            ("Let's stop for now", "{\"action\":\"pause\"}"),
            ("I spoke about this paragraph earlier", "{\"action\":\"unknown\"}")
        ]
        let shots = examples.map { "<|im_start|>user\n\($0.0)<|im_end|>\n<|im_start|>assistant\n\($0.1)<|im_end|>\n" }.joined()
        return "<|im_start|>system\n\(systemPrompt)\nAllowed replies for this request:\n\(allowedOutputs(for: request).joined(separator: "\n"))<|im_end|>\n\(shots)<|im_start|>user\n\(text)<|im_end|>\n<|im_start|>assistant\n"
    }
}
