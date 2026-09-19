import Foundation
import PrompterSpeech
import PrompterCore
import WhisperKit

if CommandLine.arguments.dropFirst().first == "--channels" {
    do { try runAudioChannelChecks(); exit(0) }
    catch { print("Audio channel check failed: \(error)"); exit(1) }
}

Task {
    do {
        if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--download-check" {
            let cache = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            guard !FileManager.default.fileExists(atPath: cache.path) else {
                print("Download check requires a new, empty cache path"); exit(2)
            }
            let fresh = WhisperService(cacheDirectory: cache)
            guard !WhisperService.isDownloaded(model: "base.en", cacheDirectory: cache) else { exit(3) }
            do {
                try await fresh.prepare(model: "base.en", allowDownload: false) { _ in }
                print("FAIL: model reported ready before download"); exit(3)
            } catch { print("PASS: missing model requires explicit download") }
            try await fresh.prepare(model: "base.en") { progress in
                if progress >= 1 { print("Model files downloaded; preparing local recognition…") }
            }
            guard WhisperService.isDownloaded(model: "base.en", cacheDirectory: cache) else {
                print("FAIL: completed setup did not include all cached assets"); exit(3)
            }
            let reopened = WhisperService(cacheDirectory: cache)
            try await reopened.prepare(model: "base.en", allowDownload: false) { _ in }
            if CommandLine.arguments.count > 3 {
                let result = try await reopened.transcribeFile(CommandLine.arguments[3])
                guard result.words.count >= 20 else { print("FAIL: newly downloaded model did not transcribe the fixture"); exit(3) }
                print("PASS: freshly downloaded model transcribed the synthetic fixture")
            }
            print("PASS: cloud download, local preparation, complete cache detection, and reopen without model download")
            exit(0)
        }
        let service = WhisperService()
        print("Preparing local Whisper base.en…")
        // The progress closure only prints coarse milestones; no audio is captured.
        try await service.prepare(model: "base.en") { progress in
            if progress >= 1 { print("Model files ready") }
        }
        print("Whisper is loaded locally.")
        if CommandLine.arguments.dropFirst().first == "--commands" {
            try await runVoiceCommandChecks(service: service)
        } else if CommandLine.arguments.count > 3, CommandLine.arguments[1] == "--stream" {
            let raw = try AudioProcessor.loadAudioAsFloatArray(fromPath: CommandLine.arguments[2])
            let script = ScriptMatcher.words(in: try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8))
            let rms = sqrt(raw.reduce(0.0) { $0 + Double($1 * $1) } / Double(raw.count))
            // Quiet synthetic speech, intentionally below the old -42 dB cutoff.
            let samples = raw.map { $0 * Float(pow(10, -50.0 / 20) / max(0.000001, rms)) }
            var updates = RecognitionUpdates()
            var anchor = 0
            for frame in stride(from: 16000, through: samples.count, by: 4800) {
                let lower = max(0, frame - 8 * 16000)
                let speech = try await service.transcribe(Array(samples[lower..<frame]))
                guard let last = speech.words.last,
                      updates.accept(text: speech.text, wordEnd: Double(lower) / 16000 + last.end, audioEnd: Double(frame) / 16000) else { continue }
                if let match = ScriptMatcher.match(speech.words.map(\.text).joined(separator: " "), script: script, near: anchor) {
                    anchor = max(anchor, match.wordIndex)
                    print(String(format: "%.1fs: matched word %d/%d, %d%%", Double(frame) / 16000, anchor + 1, script.count, Int(match.confidence * 100)))
                } else { print(String(format: "%.1fs: finding phrase — %@", Double(frame) / 16000, speech.text)) }
            }
            guard anchor >= script.count - 8 else { print("FAIL: quiet streaming recognition stalled at \(anchor)"); exit(3) }
            print("PASS: quiet rolling-window recognition recovered and followed the paragraph")
        } else if CommandLine.arguments.count > 1 {
            let start = Date()
            let result = try await service.transcribeFile(CommandLine.arguments[1])
            print("TRANSCRIPT: \(result.text)")
            print("Words with timestamps: \(result.words.count), inference seconds: \(Date().timeIntervalSince(start))")
            guard !result.words.isEmpty else { exit(2) }
        }
        exit(0)
    } catch { print("Whisper check failed: \(error)"); exit(1) }
}
dispatchMain()
