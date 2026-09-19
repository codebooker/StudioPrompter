import Foundation
import PrompterCore
import PrompterSpeech
import PrompterCommands
import WhisperKit

/// Synthetic audio only. Exercises the actual model and rolling-window router;
/// it does not open the microphone or replace live-reader acceptance testing.
func runVoiceCommandChecks(service: WhisperService, commandModelPath: String? = nil) async throws {
    let model = CommandModel()
    if let path = commandModelPath { try await model.load(path: path) }
    var fixtures: [(String, VoiceCommand?)] = [
        ("Hey Teleprompter, go back two lines.", .lines(-2)),
        ("Hey, Teleprompter, start this paragraph over.", .paragraph(0)),
        ("Hey Teleprompter, increase the font size.", .font(4)),
        ("Hey Prompter, go back two lines.", nil),
        ("In our studio the prompter helps us read. We can go back two lines if needed.", nil)
    ]
    if commandModelPath != nil {
        fixtures += [
            ("Hey Teleprompter, take me back a couple of lines.", .lines(-2)),
            ("Hey Teleprompter, the words are too big, shrink them a little.", .font(-4)),
            ("Hey Teleprompter, hold it for a second.", .pause),
            ("Hey Teleprompter, okay carry on from here.", .resume),
            ("Hey Teleprompter, go back a bit.", nil),
            ("Hey Teleprompter, go back twenty lines.", nil)
        ]
    }
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
            let event = router.consume(words, audioEnd: Double(frame) / 16000, quiet: frame >= raw.count + 10400, interpretUnknown: commandModelPath != nil)
            if case .execute(let command) = event { actions.append(command) }
            if case .interpret(let request) = event {
                let output = try await model.classify(request)
                print("Interpreted: \(request) => \(output)")
                if let command = CommandIntent.interpret(output, request: request) { actions.append(command) }
            }
        }
        let expected = fixture.1.map { [$0] } ?? []
        guard actions == expected else {
            print("FAIL: \(fixture.0) — expected \(expected), got \(actions); final transcript: \(lastText)")
            throw NSError(domain: "VoiceCommandChecks", code: 2)
        }
        print("PASS: \(fixture.0) — \(actions.count) action(s)")
    }
}
