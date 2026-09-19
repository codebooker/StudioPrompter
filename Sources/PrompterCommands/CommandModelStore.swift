import Foundation
import CryptoKit

/// Weights only: the executable runtime is signed and shipped inside the app.
public actor CommandModelStore {
    public static let fileName = "qwen2.5-1.5b-instruct-q4_k_m.gguf"
    public static let byteCount: Int64 = 1_117_320_736
    public static let sha256 = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
    public static let remote = URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/91cad51170dc346986eccefdc2dd33a9da36ead9/qwen2.5-1.5b-instruct-q4_k_m.gguf")!
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Prompter/CommandModel", isDirectory: true)
    }
    public static var isDownloaded: Bool { hasModel(in: directory) }
    public static func hasModel(in directory: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(fileName).path)
        return (attributes?[.size] as? NSNumber)?.int64Value == byteCount
    }
    private let directory: URL
    public init(directory: URL = CommandModelStore.directory) { self.directory = directory }
    public func prepare(allowDownload: Bool, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try Task.checkCancellation()
        let file = directory.appendingPathComponent(Self.fileName)
        if FileManager.default.fileExists(atPath: file.path) {
            if try verify(file) { progress(1); return file }
            guard allowDownload else { throw StoreError.corrupt }
        }
        guard allowDownload else { throw StoreError.missing }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let delegate = DownloadProgress(progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: Self.remote, delegate: delegate)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200, try verify(temporary) else { throw StoreError.corrupt }
        try Task.checkCancellation()
        // Same-directory staging + rename means a cancelled download never looks installed.
        let staging = directory.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: temporary, to: staging)
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: staging)
        } else { try FileManager.default.moveItem(at: staging, to: file) }
        progress(1)
        return file
    }
    private func verify(_ file: URL) throws -> Bool {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == Self.byteCount else { return false }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == Self.sha256
    }
    public enum StoreError: LocalizedError {
        case missing, corrupt
        public var errorDescription: String? {
            switch self {
            case .missing: return "Download the command model first."
            case .corrupt: return "The command model is incomplete or damaged. Download it again."
            }
        }
    }
}
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(_ progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(min(0.99, Double(totalBytesWritten) / Double(CommandModelStore.byteCount)))
    }
}
