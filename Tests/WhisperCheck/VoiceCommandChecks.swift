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
        ("Hey Teleprompter, start.", .resume),
        ("Hey Teleprompter, let's go.", .resume),
        ("Hey, Teleprompter, resume.", .resume),
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
            ("Hey Teleprompter, go back twenty lines.", nil),
            ("Hey Teleprompter, go down two paragraphs for me.", .paragraph(2)),
            ("Hey Teleprompter, go to the tenth paragraph.", .paragraphNumber(10)),
            ("Hey Teleprompter, go to the second cue point.", .cueNumber(2)),
            ("Hey Teleprompter, set the font size to thirty two.", .fontSize(32)),
            ("Hey Teleprompter, switch voice prompting from adaptive pace to follow script.", .followScript),
            ("Hey Teleprompter, let's stop for now.", .pause),
            ("Hey Teleprompter, go ahead and pause.", .pause),
            ("Hey Teleprompter, switch from adaptive pace to following.", .followScript),
            ("Hey Teleprompter, change the font to Georgia.", .typeface(.georgia)),
            ("Hey Teleprompter, increase line spacing a little bit.", .lineSpacing(1)),
            ("Hey Teleprompter, make the side margins smaller.", .margins(-1)),
            ("Hey Teleprompter, turn off the reading guide.", .guideVisible(false)),
            ("Hey Teleprompter, move the reading guide up a little.", .guidePosition(-1)),
            ("Hey Teleprompter, turn off focus current line.", .focusLine(false)),
            ("Hey Teleprompter, go back up | two paragraphs.", .paragraph(-2)),
            ("Hey Teleprompter, switch from adaptive pace to | follow script.", .followScript)
        ]
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let filter = ProcessInfo.processInfo.environment["STUDIO_COMMAND_FIXTURE_FILTER"]
    for (index, fixture) in fixtures.enumerated() where filter == nil || fixture.0.contains(filter!) {
        var raw: [Float] = []
        var pauses: [Range<Int>] = []
        for (part, phrase) in fixture.0.split(separator: "|").enumerated() {
            if part > 0 {
                let start = raw.count
                raw += [Float](repeating: 0, count: 24000)
                pauses.append(start..<raw.count)
            }
            let file = folder.appendingPathComponent("\(index)-\(part).aiff")
            let speech = Process()
            speech.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            speech.arguments = ["-v", "Samantha", "-r", "155", "-o", file.path, String(phrase)]
            try speech.run(); speech.waitUntilExit()
            guard speech.terminationStatus == 0 else { throw NSError(domain: "VoiceCommandChecks", code: 1) }
            raw += try AudioProcessor.loadAudioAsFloatArray(fromPath: file.path)
        }
        let samples = raw + [Float](repeating: 0, count: 32000)
        var router = VoiceCommandRouter()
        var actions: [VoiceCommand] = []
        var lastText = ""
        for frame in stride(from: 16000, through: samples.count, by: 4800) {
            let lower = max(0, frame - 8 * 16000)
            let result = try await service.transcribe(Array(samples[lower..<frame]))
            lastText = result.text
            let words = result.words.map { CommandWord($0.text, start: Double(lower) / 16000 + $0.start, end: Double(lower) / 16000 + $0.end) }
            let event = router.consume(words, audioEnd: Double(frame) / 16000, quiet: frame >= raw.count + 10400 || pauses.contains(where: { frame >= $0.lowerBound + 10400 && frame < $0.upperBound }), interpretUnknown: commandModelPath != nil)
            if filter != nil { print("FRAME \(Double(frame) / 16000) \(event) \(words.map { "\($0.text):\($0.start)-\($0.end)" })") }
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
