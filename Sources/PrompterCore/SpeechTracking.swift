import Foundation

/// A producer owns the position during a retake. Resume only after scrolling
/// settles and fresh speech matches the newly selected reading area.
public struct RetakeGate {
    public private(set) var isWaiting = false
    public private(set) var minimumSpeechTime = 0.0
    private var settledAt = 0.0
    private var progress = 0.0
    public init() {}
    public mutating func begin(now: Double, audioEnd: Double, progress: Double) {
        isWaiting = true
        settledAt = now + 0.35
        minimumSpeechTime = audioEnd + 0.35
        self.progress = progress
    }
    public mutating func accept(target: Double, lineStep: Double, now: Double) -> Bool {
        guard isWaiting else { return true }
        guard now >= settledAt, target.isFinite, lineStep > 0,
              target >= progress - lineStep, target <= progress + 1.5 * lineStep else { return false }
        isWaiting = false
        return true
    }
}

public struct ScriptWord {
    public let text: String
    public let characterOffset: Int
}
public struct ScriptMatch {
    public let wordIndex: Int
    public let characterOffset: Int
    public let confidence: Double
}

public enum ScriptMatcher {
    public static func words(in text: String) -> [ScriptWord] {
        let expression = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+(?:['’][\\p{L}\\p{N}]+)?")
        let source = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
            ScriptWord(text: source.substring(with: $0.range).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US")).replacingOccurrences(of: "’", with: "'"), characterOffset: $0.range.location)
        }
    }

    /// Local sequence alignment, allowing missing script words and extra spoken words.
    /// Strong multiword evidence is required; a single common word cannot cause a jump.
    public static func match(_ spoken: String, script: [ScriptWord], near anchor: Int) -> ScriptMatch? {
        let heard = Array(words(in: spoken).suffix(16))
        guard heard.count >= 3, !script.isEmpty else { return nil }
        var best = align(heard, script: script, near: anchor)
        // A bad beginning in the rolling window must not drown out a clean new
        // phrase. Short recovery matches stay close and require stronger evidence.
        for count in [8, 5, 3] where heard.count > count {
            let suffix = Array(heard.suffix(count))
            guard let candidate = align(suffix, script: script, near: anchor),
                  candidate.confidence >= (count == 3 ? 0.999 : 0.85),
                  candidate.wordIndex >= anchor, candidate.wordIndex <= anchor + 32,
                  best == nil || candidate.wordIndex > best!.wordIndex else { continue }
            if count == 3 {
                let lower = max(0, anchor - 12), upper = min(script.count - 2, anchor + 33)
                let occurrences = lower < upper ? (lower..<upper).filter { index in
                    (0..<3).allSatisfy { script[index + $0].text == suffix[$0].text }
                }.count : 0
                guard occurrences == 1 else { continue }
            }
            best = candidate
        }
        return best
    }

    private static func align(_ heard: [ScriptWord], script: [ScriptWord], near anchor: Int) -> ScriptMatch? {
        let lower = max(0, anchor - 36), upper = min(script.count, anchor + 70)
        guard lower < upper else { return nil }
        let target = Array(script[lower..<upper])
        let rows = heard.count, columns = target.count
        var costs = Array(repeating: Array(repeating: 0.0, count: columns + 1), count: rows + 1)
        var matches = Array(repeating: Array(repeating: 0, count: columns + 1), count: rows + 1)
        var lastHeard = Array(repeating: Array(repeating: -1, count: columns + 1), count: rows + 1)
        var lastScript = lastHeard
        for i in 1...rows {
            costs[i][0] = Double(i) * 0.9
            for j in 1...columns {
                let equal = heard[i - 1].text == target[j - 1].text
                let diagonal = costs[i - 1][j - 1] + (equal ? 0 : 1)
                let insertion = costs[i - 1][j] + 0.9
                let deletion = costs[i][j - 1] + 0.65
                if diagonal <= insertion && diagonal <= deletion {
                    costs[i][j] = diagonal
                    matches[i][j] = matches[i - 1][j - 1] + (equal ? 1 : 0)
                    lastHeard[i][j] = equal ? i - 1 : lastHeard[i - 1][j - 1]
                    lastScript[i][j] = equal ? j - 1 : lastScript[i - 1][j - 1]
                } else if insertion <= deletion {
                    costs[i][j] = insertion
                    matches[i][j] = matches[i - 1][j]
                    lastHeard[i][j] = lastHeard[i - 1][j]
                    lastScript[i][j] = lastScript[i - 1][j]
                } else {
                    costs[i][j] = deletion
                    matches[i][j] = matches[i][j - 1]
                    lastHeard[i][j] = lastHeard[i][j - 1]
                    lastScript[i][j] = lastScript[i][j - 1]
                }
            }
        }
        var best: (index: Int, score: Double, confidence: Double)?
        for j in 1...columns {
            let lastExact = lastScript[rows][j]
            guard lastExact >= 0, rows - 1 - lastHeard[rows][j] <= 4 else { continue }
            let index = lower + lastExact
            let confidence = 1 - costs[rows][j] / Double(rows)
            guard matches[rows][j] >= max(3, Int(ceil(Double(rows) * 0.55))), confidence >= 0.63 else { continue }
            let score = costs[rows][j] + Double(abs(index - anchor)) * 0.012
            if best == nil || score < best!.score { best = (index, score, confidence) }
        }
        guard let best else { return nil }
        return ScriptMatch(wordIndex: best.index, characterOffset: script[best.index].characterOffset, confidence: best.confidence)
    }
}

/// Whisper can revise the same audio span. Timestamp-only de-duplication drops
/// useful corrections; old speech in an overlapping window must still expire.
public struct RecognitionUpdates {
    private var text = ""
    private var end = 0.0
    private var windowEnd = -1.0
    public init() {}
    public mutating func accept(text: String, wordEnd: Double, audioEnd: Double) -> Bool {
        guard !text.isEmpty, wordEnd.isFinite, audioEnd.isFinite,
              audioEnd - wordEnd <= 2, audioEnd > windowEnd else { return false }
        let boundedEnd = min(wordEnd, audioEnd)
        let newWords = boundedEnd > end + 0.15
        let correction = text != self.text && audioEnd - windowEnd >= 0.3
        guard newWords || correction else { return false }
        self.text = text; end = max(end, boundedEnd); windowEnd = audioEnd
        return true
    }
}

public struct PaceEstimator {
    public private(set) var wordsPerMinute: Double?
    private var lastSampleTime: Double?
    public init() {}
    public mutating func observe(wordCount: Int, span: Double, audioEnd: Double, smoothing: Double = 0.3) -> Double? {
        guard wordCount >= 4, span >= 2, span.isFinite, audioEnd.isFinite,
              lastSampleTime == nil || audioEnd > lastSampleTime! else { return wordsPerMinute }
        let rate = min(300, max(40, Double(wordCount) / span * 60))
        if let current = wordsPerMinute, let previousTime = lastSampleTime {
            // Overlapping Whisper revisions must not each count as a fresh
            // full-strength speed change. Ease by elapsed audio time instead.
            let elapsed = min(1, audioEnd - previousTime)
            let response = min(0.7, max(0.1, smoothing)) / 0.3
            let accelerating = rate > current
            let timeConstant = (accelerating ? 3.0 : 0.65) / response
            let adjustment = (rate - current) * (1 - exp(-elapsed / timeConstant))
            let limit = (accelerating ? 12.0 : 60.0) * elapsed
            wordsPerMinute = current + max(-limit, min(limit, adjustment))
        } else {
            // A compressed opening timestamp must not launch at sprint speed.
            wordsPerMinute = min(130, rate)
        }
        lastSampleTime = audioEnd
        return wordsPerMinute
    }
}

/// Follow a confirmed reading position without a second, competing pace clock.
/// The speed limit is in rendered lines, so long scripts catch up just as quickly.
public struct FollowMotion {
    public private(set) var velocity = 0.0
    public init() {}
    public mutating func advance(from current: Double, to target: Double, seconds: Double, lineStep: Double) -> Double {
        guard seconds > 0, seconds.isFinite, lineStep > 0 else { return current }
        let distance = max(0, min(1, target) - current)
        guard distance > 0 else { velocity = 0; return current }
        // Critically damped motion retains velocity when a new recognition arrives,
        // instead of immediately jumping to a new speed every fraction of a second.
        let omega = 10.0
        let decay = exp(-omega * seconds)
        let coefficient = velocity - omega * distance
        let eased = distance + (-distance + coefficient * seconds) * decay
        velocity = min(lineStep * 4, max(0, (velocity - omega * coefficient * seconds) * decay))
        let step = max(0, min(distance, min(lineStep * 4 * seconds, eased)))
        if step >= distance { velocity = 0 }
        return min(1, current + step)
    }
}

public enum ReadingPositions {
    /// Spread the travel to the next line over every word on this line. Mapping
    /// all words to their line's top creates long plateaus followed by jumps.
    public static func spread(lineStarts: [Double], lineStep: Double) -> [Double] {
        var result = lineStarts
        var first = 0
        while first < lineStarts.count {
            var next = first + 1
            while next < lineStarts.count, lineStarts[next] == lineStarts[first] { next += 1 }
            let end = next < lineStarts.count ? lineStarts[next] : 1
            for index in first..<next {
                // Center the reading line on the guide halfway through its words.
                // Without this offset the entire line moves above the guide too early.
                result[index] = max(0, lineStarts[first] + (end - lineStarts[first]) * Double(index - first) / Double(next - first) - lineStep / 2)
            }
            first = next
        }
        return result
    }
}
