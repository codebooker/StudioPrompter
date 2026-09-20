import Foundation
import Combine
import Network
import UIKit
import PrompterLink

final class RemoteReceiver: ObservableObject {
    struct Host: Identifiable {
        let endpoint: NWEndpoint
        let name: String
        var id: String { String(describing: endpoint) }
    }
    @Published var hosts: [Host] = []
    @Published var status = "Looking for StudioPrompter on your Mac…"
    @Published var document: RemoteDocument?
    @Published var playback: RemotePlayback?
    @Published var connected = false
    @Published var connecting = false
    @Published private(set) var showControls = true
    @Published var code = ""
    @Published private(set) var pairedMac: SavedMac?
    private let pairingURL = PairingStorage.url("paired-mac.json")
    private var browser: NWBrowser?
    private var link: LinkConnection?
    private var heartbeat: Timer?
    private var controlsHideTask: DispatchWorkItem?
    private var lastMessage = 0.0
    private var autoReconnect = true
    var motion = RemoteMotion()

    init() {
        do {
            pairedMac = try PairingStorage.load(SavedMac.self, from: pairingURL)
            if pairedMac?.removed == true { status = Self.removedMessage }
        } catch { status = "Saved pairing could not be read. Enter the Mac’s pairing code to connect again." }
    }
    static let removedMessage = "This iPad was removed by the producer. Pair again to reconnect."
    func browse() {
        guard browser == nil else { return }
        let parameters = NWParameters.tcp; parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: LinkMessage.service, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            guard let self, self.browser === browser else { return }
            self.hosts = results.compactMap { result in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return Host(endpoint: result.endpoint, name: name)
            }.sorted { $0.name < $1.name }
            if self.autoReconnect, let saved = self.pairedMac, !saved.removed,
               self.hosts.contains(where: { $0.name.hasPrefix(saved.serviceName) }) {
                self.autoReconnect = false; self.reconnect()
            }
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            guard let self, self.browser === browser, !self.connected, !self.connecting, self.pairedMac?.removed != true else { return }
            switch state {
            case .waiting, .failed:
                self.status = "Search unavailable. Check Wi-Fi and Local Network access in Settings, then tap Search again."
            default: break
            }
        }
        self.browser = browser; browser.start(queue: .main)
    }
    func restartDiscovery() {
        browser?.cancel(); browser = nil; hosts = []
        if pairedMac?.removed != true { status = "Looking for StudioPrompter on your Mac…" }
        browse()
    }
    func connect(_ host: Host) {
        let clean = LinkSecurity.normalize(code)
        guard clean.count == 12 else { status = "Enter the 12-character code shown on your Mac."; return }
        open(host, key: clean, saved: nil)
    }
    private func open(_ host: Host, key: String, saved: SavedMac?) {
        disconnect(keepScript: true); connecting = true; status = "Connecting securely…"
        let connection = LinkConnection(NWConnection(to: host.endpoint, using: LinkSecurity.parameters(code: key)))
        link = connection; lastMessage = ProcessInfo.processInfo.systemUptime
        var authorized = false
        connection.onReady = { [weak connection] in
            if let saved { connection?.send(.resume(version: LinkMessage.version, deviceID: saved.deviceID, token: saved.token)) }
            else { connection?.send(.pair(version: LinkMessage.version, name: UIDevice.current.name, code: key)) }
        }
        connection.onMessage = { [weak self, weak connection] message in
            guard let self, self.link === connection else { return }
            self.lastMessage = ProcessInfo.processInfo.systemUptime
            switch message {
            case .paired(let pairing):
                guard !authorized, !pairing.removed, pairing.token.count == 64,
                      pairing.token.allSatisfy({ $0.isASCII && $0.isHexDigit }),
                      pairing.name.utf8.count <= 256, pairing.serviceName == "StudioPrompter-" + pairing.hostID.uuidString.prefix(8),
                      saved == nil || (saved?.hostID == pairing.hostID && saved?.deviceID == pairing.deviceID && saved?.token == pairing.token)
                else { connection?.close(); return }
                do { try PairingStorage.save(pairing, to: self.pairingURL) }
                catch { self.endConnection(message: "Could not save the pairing. Try pairing again."); return }
                self.pairedMac = pairing; self.code = ""; authorized = true
            case .document(let document):
                guard authorized, document.isValid else { connection?.close(); return }
                self.document = document; self.playback = nil; self.motion = RemoteMotion()
            case .playback(let state):
                guard authorized, state.isValid, state.revision == self.document?.revision else { connection?.close(); return }
                self.motion.add(progress: state.progress, at: self.lastMessage, snap: self.playback == nil || !state.playing)
                let wasConnected = self.connected
                self.playback = state; self.connected = true; self.connecting = false
                if !wasConnected { self.revealControls() }
                self.status = "Connected to your Mac"; UIApplication.shared.isIdleTimerDisabled = true
            case .removed:
                guard var pairing = saved ?? self.pairedMac else { connection?.close(); return }
                pairing.removed = true
                self.pairedMac = pairing
                do { try PairingStorage.save(pairing, to: self.pairingURL) }
                catch { /* The Mac remains authoritative and rejects future attempts. */ }
                self.endConnection(message: Self.removedMessage)
            case .unavailable(let reason):
                guard reason.utf8.count <= 512 else { connection?.close(); return }
                self.endConnection(message: reason)
            case .stopped: self.endConnection(message: "The producer stopped iPad output. Your pairing is kept.")
            default: connection?.close()
            }
        }
        connection.onClose = { [weak self, weak connection] in
            guard let self, self.link === connection else { return }
            self.heartbeat?.invalidate(); self.heartbeat = nil
            self.controlsHideTask?.cancel(); self.controlsHideTask = nil
            self.link = nil; self.connected = false; self.connecting = false; self.showControls = true
            self.status = self.document != nil ? "Connection lost · script held in place"
                : (saved != nil ? "Could not reach your Mac. Open StudioPrompter on the same network and try again."
                    : "Could not pair. Check the current code and Local Network access for both apps.")
            UIApplication.shared.isIdleTimerDisabled = false
        }
        connection.start()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak connection] _ in
            guard let self else { return }
            let silence = ProcessInfo.processInfo.systemUptime - self.lastMessage
            if silence > (self.connecting ? 15 : 2) { connection?.close(); self.heartbeat?.invalidate() }
        }
    }
    func toggleControls() {
        if showControls && connected { hideControls() } else { revealControls() }
    }
    func revealControls() {
        showControls = true; keepControlsVisible()
    }
    func keepControlsVisible() {
        controlsHideTask?.cancel(); controlsHideTask = nil
        guard connected, showControls else { return }
        let task = DispatchWorkItem { [weak self] in self?.hideControls() }
        controlsHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
    }
    func hideControls() {
        controlsHideTask?.cancel(); controlsHideTask = nil
        guard connected else { return }
        showControls = false
    }
    private func endConnection(message: String) {
        disconnect(); status = message
    }
    func reconnect() {
        guard let saved = pairedMac, !saved.removed else { return }
        let host = hosts.first { $0.name.hasPrefix(saved.serviceName) }
            ?? Host(endpoint: .service(name: saved.serviceName, type: LinkMessage.service, domain: "local.", interface: nil), name: saved.name)
        open(host, key: saved.token, saved: saved)
    }
    /// End this session; only Forget Mac deletes the saved credentials.
    func disconnect(keepScript: Bool = false) {
        autoReconnect = false
        controlsHideTask?.cancel(); controlsHideTask = nil
        heartbeat?.invalidate(); heartbeat = nil
        let previous = link; link = nil; previous?.onClose = nil; previous?.close()
        connected = false; connecting = false; showControls = true
        UIApplication.shared.isIdleTimerDisabled = false
        if !keepScript { document = nil; playback = nil; motion = RemoteMotion() }
        if pairedMac?.removed == true { status = Self.removedMessage }
        else {
            status = keepScript && document != nil ? "Disconnected · script held in place"
                : (pairedMac == nil ? "Choose your Mac to begin." : "Disconnected · ready to reconnect")
        }
    }
    func forgetMac() {
        do { try PairingStorage.forget(at: pairingURL) }
        catch { status = "Could not forget this Mac. Please try again."; return }
        disconnect(); pairedMac = nil; code = ""
        status = "Choose your Mac to begin."
    }
}
