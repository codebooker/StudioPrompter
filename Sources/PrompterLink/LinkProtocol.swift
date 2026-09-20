import Foundation
import PrompterCore

public struct RemoteLine: Codable {
    public var location: Int
    public var length: Int
    public var y: Double
    public var height: Double
    public init(location: Int, length: Int, y: Double, height: Double) {
        self.location = location; self.length = length; self.y = y; self.height = height
    }
}

public struct RemoteDocument: Codable {
    public var revision: UUID
    public var script: Script
    public var lines: [RemoteLine]
    public var textHeight: Double
    public var lineHeight: Double
    public init(script: Script, lines: [RemoteLine], textHeight: Double, lineHeight: Double) {
        revision = UUID(); self.script = script; self.lines = lines
        self.textHeight = textHeight; self.lineHeight = lineHeight
    }
    public var isValid: Bool {
        let count = (script.text as NSString).length
        let s = script.settings
        return count <= 500_000 && lines.count <= 100_000 &&
            textHeight.isFinite && (0...10_000_000).contains(textHeight) &&
            lineHeight.isFinite && (1...1000).contains(lineHeight) &&
            s.fontSize.isFinite && (1...200).contains(s.fontSize) &&
            s.margin.isFinite && (0...450).contains(s.margin) &&
            s.guidePosition.isFinite && (0...1).contains(s.guidePosition) &&
            s.guideLines.isFinite && (1...3).contains(s.guideLines) &&
            lines.allSatisfy { $0.location >= 0 && $0.length >= 0 && $0.location <= count && $0.length <= count - $0.location && $0.y.isFinite && (0...10_000_000).contains($0.y) && $0.height.isFinite && (0...1000).contains($0.height) }
    }
}

public struct RemotePlayback: Codable {
    public var revision: UUID
    public var progress: Double
    public var playing: Bool
    public var blackout: Bool
    public var countdown: Int
    public var notice: String?
    public init(revision: UUID, progress: Double, playing: Bool, blackout: Bool, countdown: Int, notice: String?) {
        self.revision = revision; self.progress = progress; self.playing = playing
        self.blackout = blackout; self.countdown = countdown; self.notice = notice
    }
    public var isValid: Bool { progress.isFinite && (0...1).contains(progress) && (0...10).contains(countdown) && (notice?.utf8.count ?? 0) <= 4096 }
}

public enum LinkMessage: Codable {
    case hello(version: Int, name: String)
    case document(RemoteDocument)
    case playback(RemotePlayback)
    case stopped
    case pair(version: Int, name: String, code: String)
    case resume(version: Int, deviceID: UUID, token: String)
    case paired(SavedMac)
    case removed
    case unavailable(String)
    public static let version = 2
    public static let service = "_studioprompt._tcp"
    public static let maximumBytes = 8 * 1024 * 1024
}

/// A bounded length prefix prevents partial TCP reads from becoming partial messages.
public enum LinkFraming {
    public static func frame(_ message: LinkMessage) throws -> Data {
        let data = try JSONEncoder().encode(message)
        guard !data.isEmpty, data.count <= LinkMessage.maximumBytes else { throw LinkError.invalidMessage }
        var length = UInt32(data.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + data
    }
    public static func length(_ header: Data) throws -> Int {
        guard header.count == 4 else { throw LinkError.invalidMessage }
        let value = header.reduce(0) { ($0 << 8) | Int($1) }
        guard value > 0, value <= LinkMessage.maximumBytes else { throw LinkError.invalidMessage }
        return value
    }
}
public enum LinkError: Error { case invalidMessage }

/// Interpolate behind the last few samples; never extrapolate through a dropped connection.
public struct RemoteMotion {
    private var samples: [(time: Double, progress: Double)] = []
    public init() {}
    public mutating func add(progress: Double, at time: Double, snap: Bool) {
        if snap || samples.last.map({ abs($0.progress - progress) > 0.035 }) == true { samples.removeAll() }
        samples.append((time, progress))
        samples = Array(samples.suffix(8))
    }
    public func position(at time: Double) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        let target = time - 0.10
        if target <= first.time { return first.progress }
        for (a, b) in zip(samples, samples.dropFirst()) where target <= b.time {
            let mix = min(1, max(0, (target - a.time) / max(0.001, b.time - a.time)))
            return a.progress + (b.progress - a.progress) * mix
        }
        return last.progress
    }
}
