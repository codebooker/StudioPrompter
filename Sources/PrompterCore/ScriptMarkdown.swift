import Foundation

/// A deliberately small, lossless script dialect: bold, underline, and hidden cues.
/// Other Markdown constructs remain readable script text; this is not a web renderer.
public enum ScriptMarkdown {
    private static let cuePrefix = "<!-- studioprompter-cue "

    public static func encode(_ script: Script) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var cues: [Int: [String]] = [:]
        let count = (script.text as NSString).length
        for cue in script.cues {
            // Escaping hyphens and angle brackets prevents a title from closing its comment.
            let json = String(decoding: try encoder.encode(cue), as: UTF8.self)
                .replacingOccurrences(of: "-", with: "\\u002D")
                .replacingOccurrences(of: "<", with: "\\u003C")
                .replacingOccurrences(of: ">", with: "\\u003E")
            let offset = min(count, max(0, cue.characterOffset ?? count))
            cues[offset, default: []].append(cuePrefix + json + " -->")
        }
        let validMarks = script.emphasis.compactMap { mark -> (TextEmphasis, NSRange)? in
            mark.range(in: script.text).map { (mark, $0) }
        }
        var result = "", offset = 0, bold = false, underline = false
        var linePrefix = "", boldClosing = "**"
        let boundaries = Set(validMarks.flatMap { [$0.1.location, $0.1.location + $0.1.length] } + Array(cues.keys) + [count]).sorted()
        func close() {
            if underline { result += "</u>" }; if bold { result += boldClosing }
            bold = false; underline = false
        }
        for scalar in script.text.unicodeScalars {
            let marks = validMarks.filter { NSLocationInRange(offset, $0.1) }.map { $0.0 }
            let nextBold = marks.contains { $0.bold }, nextUnderline = marks.contains { $0.underline }
            if cues[offset] != nil || bold != nextBold || underline != nextUnderline {
                close()
                result += cues[offset, default: []].joined()
                if nextBold {
                    let end = boundaries.first(where: { $0 > offset }) ?? count
                    let passage = (script.text as NSString).substring(with: NSRange(location: offset, length: end - offset))
                    // CommonMark rejects ** delimiters next to whitespace. HTML
                    // strong is valid Markdown too and preserves those selections.
                    let html = passage.first?.isWhitespace == true || passage.last?.isWhitespace == true || passage.contains("\n") || passage.contains("\r")
                    result += html ? "<strong>" : "**"
                    boldClosing = html ? "</strong>" : "**"
                }
                if nextUnderline { result += "<u>" }
                bold = nextBold; underline = nextUnderline
            }
            // Keep ordinary prose readable while escaping actual Markdown syntax.
            let atLineStart = linePrefix.allSatisfy { $0 == " " || $0 == "\t" }
            let orderedList = (scalar == "." || scalar == ")") && !linePrefix.isEmpty && linePrefix.trimmingCharacters(in: .whitespaces).allSatisfy { $0.isNumber }
            if "\\`*_[]<>|&".unicodeScalars.contains(scalar) || (atLineStart && "#+-=".unicodeScalars.contains(scalar)) || orderedList { result += "\\" }
            result.unicodeScalars.append(scalar)
            if scalar == "\n" || scalar == "\r" { linePrefix = "" } else { linePrefix.unicodeScalars.append(scalar) }
            offset += scalar.utf16.count
        }
        close()
        result += cues[count, default: []].joined()
        return result
    }

    public static func decode(_ markdown: String, title: String) -> Script {
        var script = Script(title: title, text: "")
        var index = markdown.startIndex, bold = false, underline = false, offset = 0
        var marks: [TextEmphasis] = []
        func append(_ value: String) {
            let length = (value as NSString).length
            script.text += value
            if bold || underline {
                if let last = marks.last, last.location + last.length == offset, last.bold == bold, last.underline == underline {
                    marks[marks.count - 1].length += length
                } else { marks.append(TextEmphasis(location: offset, length: length, bold: bold, underline: underline)) }
            }
            offset += length
        }
        while index < markdown.endIndex {
            let remaining = markdown[index...]
            if remaining.hasPrefix("\\") {
                let next = markdown.index(after: index)
                if next < markdown.endIndex, "\\`*_{}[]<>()#+-.!|>&=".contains(markdown[next]) {
                    append(String(markdown[next])); index = markdown.index(after: next); continue
                }
            }
            if remaining.hasPrefix(cuePrefix), let end = remaining.range(of: " -->") {
                let start = markdown.index(index, offsetBy: cuePrefix.count)
                if var cue = try? JSONDecoder().decode(Cue.self, from: Data(markdown[start..<end.lowerBound].utf8)) {
                    if cue.characterOffset != nil { cue.characterOffset = offset }
                    script.cues.append(cue); index = end.upperBound; continue
                }
            }
            if remaining.hasPrefix("<strong>"), remaining.range(of: "</strong>") != nil {
                bold = true; index = markdown.index(index, offsetBy: 8); continue
            }
            if bold, remaining.hasPrefix("</strong>") {
                bold = false; index = markdown.index(index, offsetBy: 9); continue
            }
            if remaining.hasPrefix("**") {
                let next = markdown.index(index, offsetBy: 2)
                if bold || markdown[next...].range(of: "**") != nil {
                    bold.toggle(); index = next; continue
                }
            }
            if remaining.hasPrefix("<u>"), remaining.range(of: "</u>") != nil {
                underline = true; index = markdown.index(index, offsetBy: 3); continue
            }
            if underline, remaining.hasPrefix("</u>") {
                underline = false; index = markdown.index(index, offsetBy: 4); continue
            }
            append(String(markdown[index])); index = markdown.index(after: index)
        }
        script.emphasis = marks
        return script
    }
}
