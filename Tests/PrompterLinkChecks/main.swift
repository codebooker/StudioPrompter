import Foundation
import Network
import PrompterCore
import PrompterLink

@main struct Checks {
    static func main() async throws {
        let packet = LinkMessage.hello(version: 1, name: "Test iPad")
        let frame = try LinkFraming.frame(packet)
        let payloadLength = try LinkFraming.length(Data(frame.prefix(4)))
        precondition(payloadLength == frame.count - 4)
        for bytes in [[UInt8](repeating: 0, count: 4), [255, 255, 255, 255], [0, 1]] {
            do { _ = try LinkFraming.length(Data(bytes)); fatalError("Accepted invalid frame") } catch {}
        }
        let decoded = try JSONDecoder().decode(LinkMessage.self, from: frame.dropFirst(4))
        if case .hello(let version, let name) = decoded { precondition(version == 1 && name == "Test iPad") } else { fatalError("Round-trip changed packet") }
        var document = RemoteDocument(script: Script(title: "Test", text: "Hello 👋 world"), lines: [RemoteLine(location: 0, length: 14, y: 0, height: 70)], textHeight: 70, lineHeight: 80)
        precondition(document.isValid)
        document.lines[0].length = Int.max; precondition(!document.isValid)
        document.lines = []; document.textHeight = .nan; precondition(!document.isValid)
        var motion = RemoteMotion()
        motion.add(progress: 0.1, at: 1, snap: true); motion.add(progress: 0.12, at: 1.1, snap: false)
        precondition(abs(motion.position(at: 1.15) - 0.11) < 0.00001)
        precondition(motion.position(at: 100) == 0.12, "Disconnected motion must not extrapolate")
        motion.add(progress: 0.01, at: 2, snap: true)
        precondition(motion.position(at: 2) == 0.01, "Retakes must replace queued motion")
        precondition(LinkSecurity.normalize("abcd-efgh-jklm") == "ABCDEFGHJKLM")
        precondition(LinkSecurity.newCode().count == 12)
        print("PASS: framing limits, packet round-trip, unsafe document rejection, retakes, and motion freeze")
        try pairingChecks()
        let success = await connectionCheck(wrongCode: false)
        precondition(success, "Encrypted loopback transfer failed")
        print("PASS: TLS pairing and framed document transport")
        let rejection = await connectionCheck(wrongCode: true)
        precondition(rejection, "Incorrect pairing code was not rejected")
        print("PASS: wrong pairing code cannot receive script data")
        let terminal = await connectionCheck(wrongCode: false, terminalOnly: true)
        precondition(terminal, "Removal notice was lost when the connection closed")
        print("PASS: final removal notice arrives before connection close")
    }
    static func pairingChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registryURL = directory.appendingPathComponent("mac.json")
        let clientURL = directory.appendingPathComponent("ipad.json")
        var registry = MacPairings()
        let initialCode = registry.pairingCode
        let a = try registry.pair(name: "First iPad", code: initialCode)
        let b = try registry.pair(name: "Second iPad", code: initialCode)
        precondition(a.token != b.token && a.token.count == 64)
        try PairingStorage.save(registry, to: registryURL)
        var restarted = try PairingStorage.load(MacPairings.self, from: registryURL)!
        precondition(restarted.access(id: a.id, token: a.token) == .allowed)
        precondition(restarted.access(id: a.id, token: b.token) == .unknown)
        let client = SavedMac(hostID: registry.hostID, name: "Studio Mac", serviceName: registry.serviceName, deviceID: a.id, token: a.token)
        try PairingStorage.save(client, to: clientURL)
        let resumed = try PairingStorage.load(SavedMac.self, from: clientURL)!
        precondition(resumed == client)
        // Remove an offline device, then restart both sides from disk.
        restarted.remove(id: a.id)
        try PairingStorage.save(restarted, to: registryURL)
        restarted = try PairingStorage.load(MacPairings.self, from: registryURL)!
        precondition(restarted.access(id: resumed.deviceID, token: resumed.token) == .removed)
        precondition(restarted.access(id: b.id, token: b.token) == .allowed)
        precondition(restarted.transportKeys.contains(a.token), "Removed device must still be able to receive an authenticated denial")
        precondition(!restarted.transportKeys.contains(initialCode), "Old enrollment code must stop working")
        do { _ = try restarted.pair(name: "Removed client", code: initialCode); fatalError("Revoked enrollment code was accepted") } catch {}
        let fresh = try restarted.pair(name: "Repaired iPad", code: restarted.pairingCode)
        precondition(restarted.access(id: fresh.id, token: fresh.token) == .allowed)
        precondition(restarted.access(id: a.id, token: a.token) == .removed)
        let attrs = try FileManager.default.attributesOfItem(atPath: registryURL.path)
        precondition((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try PairingStorage.forget(at: clientURL)
        let forgotten = try PairingStorage.load(SavedMac.self, from: clientURL)
        precondition(forgotten == nil)
        print("PASS: saved pairings survive restarts; offline removal persists, other devices retain access, old codes fail, and Forget clears credentials")
    }
    @MainActor static func connectionCheck(wrongCode: Bool, terminalOnly: Bool = false) async -> Bool {
        await withCheckedContinuation { continuation in
            let check = Loopback(wrongCode: wrongCode, terminalOnly: terminalOnly, completion: { continuation.resume(returning: $0) })
            check.start()
        }
    }
}

final class Loopback {
    let wrongCode: Bool
    let terminalOnly: Bool
    let completion: (Bool) -> Void
    var listener: NWListener?
    var client: LinkConnection?
    var server: LinkConnection?
    var hold: Loopback?
    var finished = false
    let document = RemoteDocument(script: Script(title: "Transport check", text: String(repeating: "Hello 👋 world\n", count: 8000)), lines: [], textHeight: 70, lineHeight: 80)
    var receivedDocument = false
    init(wrongCode: Bool, terminalOnly: Bool, completion: @escaping (Bool) -> Void) {
        self.wrongCode = wrongCode; self.terminalOnly = terminalOnly; self.completion = completion
    }
    func start() {
        hold = self
        do {
            let listener = try NWListener(using: LinkSecurity.parameters(keys: ["ANOTHERKEY123", "ABCDEFGHJKLM"]), on: .any)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] incoming in
                guard let self else { return }
                let server = LinkConnection(incoming); self.server = server
                server.onMessage = { [weak self, weak server] message in
                    guard let self else { return }
                    if self.wrongCode { self.finish(false); return }
                    if case .hello = message {
                        if self.terminalOnly { server?.finish(with: .removed); return }
                        server?.send(.document(self.document))
                        server?.send(.playback(RemotePlayback(revision: self.document.revision, progress: 0.42, playing: true, blackout: false, countdown: 0, notice: nil)))
                    }
                }
                server.start()
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, case .ready = state, let port = listener.port else { return }
                let client = LinkConnection(NWConnection(host: "127.0.0.1", port: port,
                    using: LinkSecurity.parameters(code: self.wrongCode ? "WRONGCODE123" : "ABCDEFGHJKLM")))
                self.client = client
                client.onReady = { [weak client] in client?.send(.hello(version: 1, name: "Test iPad")) }
                client.onMessage = { [weak self] message in
                    guard let self else { return }
                    switch message {
                    case .removed: self.finish(self.terminalOnly && !self.wrongCode)
                    case .document(let received):
                        self.receivedDocument = received.isValid && received.script == self.document.script && received.revision == self.document.revision
                    case .playback(let state):
                        self.finish(!self.wrongCode && self.receivedDocument && state.revision == self.document.revision && state.progress == 0.42)
                    default: self.finish(false)
                    }
                }
                client.onClose = { [weak self] in self?.finish(self?.wrongCode == true) }
                client.start()
            }
            listener.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.finish(false) }
        } catch { finish(false) }
    }
    func finish(_ success: Bool) {
        guard !finished else { return }; finished = true
        client?.onClose = nil; client?.close(); server?.close(); listener?.cancel()
        completion(success); hold = nil
    }
}
