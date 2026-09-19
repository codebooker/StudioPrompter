import Foundation
import WhisperKit

public struct HeardWord: Sendable {
    public let text: String
    public let start: Double
    public let end: Double
}

public struct HeardSpeech: Sendable {
    public let text: String
    public let words: [HeardWord]
}

/// Serializes model loading and inference. Only model assets are downloaded;
/// the audio arrays passed here are processed locally by Core ML.
public actor WhisperService {
    private var engine: WhisperKit?
    private var loadedModel: String?
    private var busy = false
    private let cacheDirectory: URL
    public init(cacheDirectory: URL = WhisperService.cache) { self.cacheDirectory = cacheDirectory }
    public static var cache: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Prompter/Whisper", isDirectory: true)
    }
    private static func cachedFolder(model: String, cacheDirectory: URL) -> URL? {
        let marker = cacheDirectory.appendingPathComponent("\(model)-path.txt")
        guard let path = try? String(contentsOf: marker, encoding: .utf8) else { return nil }
        let folder = URL(fileURLWithPath: path)
        guard ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy({ name in
            ["mlmodelc", "mlpackage"].contains { FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(name).\($0)").path) }
        }) else { return nil }
        return folder
    }
    public static func isDownloaded(model: String, cacheDirectory: URL = WhisperService.cache) -> Bool {
        guard cachedFolder(model: model, cacheDirectory: cacheDirectory) != nil else { return false }
        let tokenizer = cacheDirectory.appendingPathComponent("Tokenizers/models/openai/whisper-\(model)")
        return ["tokenizer.json", "tokenizer_config.json", "config.json"].allSatisfy {
            FileManager.default.fileExists(atPath: tokenizer.appendingPathComponent($0).path)
        }
    }
    public func prepare(model: String, allowDownload: Bool = true, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard ["base.en", "small.en"].contains(model) else {
            throw NSError(domain: "Prompter", code: 1, userInfo: [NSLocalizedDescriptionKey: "This model is not supported for live prompting."])
        }
        try await enter()
        defer { busy = false }
        if loadedModel == model, engine != nil { return }
        guard allowDownload || Self.isDownloaded(model: model, cacheDirectory: cacheDirectory) else {
            throw NSError(domain: "Prompter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Download the speech model before starting voice prompting."])
        }
        let marker = cacheDirectory.appendingPathComponent("\(model)-path.txt")
        let folder: URL
        if let cached = Self.cachedFolder(model: model, cacheDirectory: cacheDirectory) {
            folder = cached
            progress(1)
        } else {
            folder = try await WhisperKit.download(variant: "openai_whisper-\(model)", downloadBase: cacheDirectory) { value in
                progress(value.fractionCompleted)
            }
        }
        try Task.checkCancellation()
        engine = nil
        let config = WhisperKitConfig(modelFolder: folder.path, tokenizerFolder: cacheDirectory.appendingPathComponent("Tokenizers"), verbose: false, prewarm: false, load: true, download: false)
        engine = try await WhisperKit(config)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try folder.path.write(to: marker, atomically: true, encoding: .utf8)
        loadedModel = model
    }
    public func transcribe(_ samples: [Float]) async throws -> HeardSpeech {
        try await enter()
        defer { busy = false }
        guard let engine else { throw NSError(domain: "Prompter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Load a Whisper model first."]) }
        let options = DecodingOptions(language: "en", temperatureFallbackCount: 0, sampleLength: 160, skipSpecialTokens: true, wordTimestamps: true, suppressBlank: true, concurrentWorkerCount: 1)
        let results = try await engine.transcribe(audioArray: samples, decodeOptions: options)
        let segments = results.flatMap(\.segments).filter { $0.noSpeechProb < 0.65 && $0.avgLogprob > -1.2 }
        let words = segments.flatMap { $0.words ?? [] }.filter { $0.probability > 0.15 }.map { HeardWord(text: $0.word, start: Double($0.start), end: Double($0.end)) }
        return HeardSpeech(text: segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines), words: words)
    }
    public func transcribeFile(_ path: String) async throws -> HeardSpeech {
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
        return try await transcribe(samples)
    }
    private func enter() async throws {
        while busy { try await Task.sleep(nanoseconds: 50_000_000) }
        try Task.checkCancellation()
        busy = true
    }
}
