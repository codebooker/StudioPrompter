import Foundation
import PrompterCore
import PrompterSpeech
import WhisperKit

/// Synthetic audio only. Exercises the actual model and rolling-window router;
/// it does not open the microphone or replace live-reader acceptance testing.
func runVoiceCommandChecks(service: WhisperService) async throws {
    let fixtures: [(String, VoiceCommand?)] = [
        ("Hey Teleprompter, go back two lines.", .lines(-2)),
        ("Hey, Teleprompter, start this paragraph over.", .paragraph(0)),
        ("Hey Teleprompter, increase the font size.", .font(4)),
        ("Hey Prompter, go back two lines.", nil),
        ("In our studio the prompter helps us read. We can go back two lines if needed.", nil)
    ]
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for (index, fixture) in fixtures.enumerated() {
        let file = folder.appendingPathComponent("\(index).aiff")
        let speech = Process()
        speech.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        speech.arguments = ["-v", "Samantha", "-r", "155", "-o", file.path, fixture.0]
        try speech.run(); speech.waitUntilExit()
        guard speech.terminationStatus == 0 else { throw NSError(domain: "VoiceCommandChecks", code: 1) }
        let raw = try AudioProcessor.loadAudioAsFloatArray(fromPath: file.path)
        let samples = raw + [Float](repeating: 0, count: 32000)
        var router = VoiceCommandRouter()
        var actions: [VoiceCommand] = []
        var lastText = ""
        for frame in stride(from: 16000, through: samples.count, by: 4800) {
            let lower = max(0, frame - 8 * 16000)
            let result = try await service.transcribe(Array(samples[lower..<frame]))
            lastText = result.text
            let words = result.words.map { CommandWord($0.text, start: Double(lower) / 16000 + $0.start, end: Double(lower) / 16000 + $0.end) }
            let event = router.consume(words, audioEnd: Double(frame) / 16000, quiet: frame >= raw.count + 10400)
            if case .execute(let command) = event { actions.append(command) }
        }
        let expected = fixture.1.map { [$0] } ?? []
        guard actions == expected else {
            print("FAIL: \(fixture.0) — expected \(expected), got \(actions); final transcript: \(lastText)")
            throw NSError(domain: "VoiceCommandChecks", code: 2)
        }
        print("PASS: \(fixture.0) — \(actions.count) action(s)")
    }
}
