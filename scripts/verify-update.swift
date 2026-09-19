import Foundation
import CryptoKit

final class SignatureReader: NSObject, XMLParserDelegate {
    var signature: Data?
    var expectedSize: Int?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "enclosure" {
            signature = attributes["sparkle:edSignature"].flatMap { Data(base64Encoded: $0) }
            expectedSize = attributes["length"].flatMap(Int.init)
        }
    }
}

func verify(plistURL: URL, feedURL: URL, archiveURL: URL) throws {
    let plist = try Data(contentsOf: plistURL)
    let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
    guard let encodedKey = info?["SUPublicEDKey"] as? String, let key = Data(base64Encoded: encodedKey) else { throw NSError(domain: "Missing update public key", code: 2) }
    let reader = SignatureReader()
    let parser = XMLParser(data: try Data(contentsOf: feedURL))
    parser.delegate = reader
    guard parser.parse(), let signature = reader.signature, let size = reader.expectedSize else { throw NSError(domain: "Missing update signature", code: 3) }
    let archive = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
    guard archive.count == size, publicKey.isValidSignature(signature, for: archive) else { throw NSError(domain: "Update signature or archive size is invalid", code: 4) }
}

func selfTest() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    // Ephemeral test key: no Keychain access or private-key file is needed by CI.
    let key = Curve25519.Signing.PrivateKey()
    let archive = Data("StudioPrompter signature test".utf8)
    let signature = try key.signature(for: archive)
    let plist = folder.appendingPathComponent("Info.plist")
    let feed = folder.appendingPathComponent("appcast.xml")
    let zip = folder.appendingPathComponent("test.zip")
    try PropertyListSerialization.data(fromPropertyList: ["SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString()], format: .xml, options: 0).write(to: plist)
    let xml = "<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel><item><enclosure length=\"\(archive.count)\" sparkle:edSignature=\"\(signature.base64EncodedString())\"/></item></channel></rss>"
    try Data(xml.utf8).write(to: feed)
    try archive.write(to: zip)
    try verify(plistURL: plist, feedURL: feed, archiveURL: zip)
    func reject() throws {
        do {
            try verify(plistURL: plist, feedURL: feed, archiveURL: zip)
        } catch { return }
        throw NSError(domain: "Signature test accepted an invalid update", code: 5)
    }
    var altered = archive; altered[0] ^= 1
    try altered.write(to: zip); try reject() // same-size tampering
    try Data(archive.dropLast()).write(to: zip); try reject() // truncated download
    try archive.write(to: zip)
    let wrongKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
    try PropertyListSerialization.data(fromPropertyList: ["SUPublicEDKey": wrongKey.base64EncodedString()], format: .xml, options: 0).write(to: plist)
    try reject()
    print("PASS: valid signature accepted; tampering, truncation, and wrong signing key rejected")
}

do {
    if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
        try selfTest()
    } else {
        guard CommandLine.arguments.count == 4 else { throw NSError(domain: "Usage: verify-update.swift Info.plist appcast.xml archive.zip", code: 1) }
        try verify(plistURL: URL(fileURLWithPath: CommandLine.arguments[1]), feedURL: URL(fileURLWithPath: CommandLine.arguments[2]), archiveURL: URL(fileURLWithPath: CommandLine.arguments[3]))
        print("PASS: update archive matches the pinned Ed25519 public key and byte count")
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
