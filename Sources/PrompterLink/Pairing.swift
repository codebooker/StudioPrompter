import Foundation
import Security

public struct PairedIPad: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var token: String
    public var removed: Bool
}

public struct SavedMac: Codable, Equatable {
    public var hostID: UUID
    public var name: String
    public var serviceName: String
    public var deviceID: UUID
    public var token: String
    public var removed: Bool = false
    public init(hostID: UUID, name: String, serviceName: String, deviceID: UUID, token: String) {
        self.hostID = hostID; self.name = name; self.serviceName = serviceName
        self.deviceID = deviceID; self.token = token
    }
}

public enum PairingAccess: Equatable { case allowed, removed, unknown }

/// Removed records retain only the credentials needed to authenticate a denial.
/// They can never authorize a script. This also works when removal happened offline.
public struct MacPairings: Codable {
    public var hostID = UUID()
    public var pairingCode = LinkSecurity.newCode()
    public private(set) var devices: [PairedIPad] = []
    public init() {}
    public var serviceName: String { "StudioPrompter-" + hostID.uuidString.prefix(8) }
    public var transportKeys: [String] { [pairingCode] + devices.map(\.token) }
    public mutating func pair(name: String, code: String) throws -> PairedIPad {
        guard LinkSecurity.normalize(code) == pairingCode, !name.isEmpty, name.utf8.count <= 128 else { throw LinkError.invalidMessage }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw LinkError.invalidMessage }
        let device = PairedIPad(id: UUID(), name: name, token: bytes.map { String(format: "%02X", $0) }.joined(), removed: false)
        devices.append(device)
        return device
    }
    public func access(id: UUID, token: String) -> PairingAccess {
        guard let device = devices.first(where: { $0.id == id }), device.token == token else { return .unknown }
        return device.removed ? .removed : .allowed
    }
    public mutating func remove(id: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == id }), !devices[index].removed else { return }
        devices[index].removed = true
        // An old enrollment code must not let a removed device pair itself again.
        pairingCode = LinkSecurity.newCode()
    }
}

/// Private application storage, never script exports or source-controlled files.
/// The directory and atomic replacement file are owner-only on macOS; iPad also
/// protects the file with its normal application sandbox and data protection.
public enum PairingStorage {
    public static func url(_ filename: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StudioPrompterPairing", isDirectory: true).appendingPathComponent(filename)
    }
    public static func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temp = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        defer { try? fm.removeItem(at: temp) }
        let data = try JSONEncoder().encode(value)
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        guard fm.createFile(atPath: temp.path, contents: data, attributes: attributes) else { throw CocoaError(.fileWriteUnknown) }
        if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: temp) }
        else { try fm.moveItem(at: temp, to: url) }
        var protectedURL = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? protectedURL.setResourceValues(values)
    }
    public static func forget(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
