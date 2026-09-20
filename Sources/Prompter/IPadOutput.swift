import AppKit
import SwiftUI
import Network
import PrompterCore
import PrompterLayout
import PrompterLink

final class IPadOutput: ObservableObject {
    @Published private(set) var code = ""
    @Published private(set) var status = "Connect your iPad"
    @Published private(set) var connectedName: String?
    @Published private(set) var connectedID: UUID?
    @Published private(set) var isHosting = false
    @Published private var registry = MacPairings()
    var devices: [PairedIPad] { registry.devices.filter { !$0.removed } }
    var hasRememberedDevices: Bool { !registry.devices.isEmpty }
    var onChange: (() -> Void)?
    var onConnected: (() -> Void)?
    private let registryURL = PairingStorage.url("mac-devices.json")
    private var storageError: Error?
    private var listener: NWListener?
    private var pending: [UUID: LinkConnection] = [:]
    private var connection: LinkConnection?
    private var timer: Timer?
    private var lastScript: Script?
    private var document: RemoteDocument?
    private var latestState: (() -> (Script, Double, Bool, Bool, Int, String?))?

    init() {
        do { if let saved = try PairingStorage.load(MacPairings.self, from: registryURL) { registry = saved } }
        catch { storageError = error; status = "Saved iPad pairings could not be read. They have been preserved." }
    }
    var formattedCode: String {
        stride(from: 0, to: code.count, by: 4).map { String(Array(code)[$0..<min(code.count, $0 + 4)]) }.joined(separator: "–")
    }
    func start(state: @escaping () -> (Script, Double, Bool, Bool, Int, String?)) {
        guard !isHosting, storageError == nil else { return }
        latestState = state
        do {
            try PairingStorage.save(registry, to: registryURL)
            code = registry.pairingCode; isHosting = true; status = "Waiting for your iPad"
            try refreshListener()
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common); self.timer = timer
            onChange?()
        } catch { stop(); status = "Could not start iPad output: \(error.localizedDescription)" }
    }
    private func refreshListener() throws {
        let replacement = try NWListener(using: LinkSecurity.parameters(keys: registry.transportKeys))
        listener?.cancel(); listener = replacement
        replacement.service = NWListener.Service(name: registry.serviceName, type: LinkMessage.service)
        replacement.stateUpdateHandler = { [weak self, weak replacement] stage in
            guard let self, self.listener === replacement else { return }
            if case .failed = stage { self.stop(); self.status = "Could not connect. Allow Local Network access and try again." }
        }
        replacement.newConnectionHandler = { [weak self] incoming in self?.accept(incoming) }
        replacement.start(queue: .main)
    }
    func stop() {
        timer?.invalidate(); timer = nil
        listener?.cancel(); listener = nil
        let waiting = Array(pending.values); pending.removeAll(); waiting.forEach { $0.close() }
        let old = connection; connection = nil; old?.onClose = nil; old?.finish(with: .stopped)
        connectedName = nil; connectedID = nil; isHosting = false; code = ""; lastScript = nil; document = nil
        latestState = nil; status = "iPad output stopped · pairings kept"; onChange?()
        // Keep the closing connection alive until its final message is delivered.
        if let old { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { old.close() } }
    }
    func removeDevice(_ id: UUID) {
        var updated = registry; updated.remove(id: id)
        do { try PairingStorage.save(updated, to: registryURL) }
        catch { status = "Could not save removal. The iPad still has access."; return }
        registry = updated; code = isHosting ? registry.pairingCode : ""
        if connectedID == id {
            let old = connection; connection = nil; old?.onClose = nil
            connectedName = nil; connectedID = nil; lastScript = nil; document = nil
            old?.finish(with: .removed)
            if let old { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { old.close() } }
        }
        if isHosting {
            do { try refreshListener() }
            catch { stop(); status = "iPad removed. Start pairing again to restore the connection service."; return }
        }
        status = "iPad removed · it must pair again to receive the script"; onChange?()
    }
    private func accept(_ incoming: NWConnection) {
        guard isHosting, pending.count < 4 else { incoming.cancel(); return }
        let requestID = UUID(), link = LinkConnection(incoming)
        pending[requestID] = link
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak link] in
            if self?.pending[requestID] != nil { link?.close() }
        }
        link.onMessage = { [weak self, weak link] message in
            guard let self, let link, self.pending[requestID] === link else { link?.close(); return }
            let device: PairedIPad
            switch message {
            case .pair(let version, let name, let code):
                guard version == LinkMessage.version else { link.finish(with: .unavailable("Update StudioPrompter Companion to pair with this Mac.")); return }
                guard self.connection == nil else { link.finish(with: .unavailable("Another iPad is using this Mac. Disconnect it first.")); return }
                var updated = self.registry
                do {
                    device = try updated.pair(name: name, code: code)
                    try PairingStorage.save(updated, to: self.registryURL)
                    self.registry = updated
                    // Existing accepted connections stay alive while discovery is refreshed
                    // to accept this device's private key on future connections.
                    try self.refreshListener()
                } catch { link.finish(with: .unavailable("Could not pair. Check the current code on the Mac and try again.")); return }
            case .resume(let version, let id, let token):
                guard version == LinkMessage.version else { link.finish(with: .unavailable("Update StudioPrompter Companion to reconnect.")); return }
                switch self.registry.access(id: id, token: token) {
                case .removed: link.finish(with: .removed); return
                case .unknown: link.finish(with: .unavailable("This pairing is no longer recognized. Forget this Mac and pair again.")); return
                case .allowed: break
                }
                guard self.connection == nil else { link.finish(with: .unavailable("Another iPad is using this Mac. Disconnect it first.")); return }
                guard let saved = self.registry.devices.first(where: { $0.id == id }) else { link.close(); return }
                device = saved
            default: link.finish(with: .unavailable("Update StudioPrompter Companion and pair again.")); return
            }
            self.pending.removeValue(forKey: requestID); self.connection = link
            self.connectedID = device.id; self.connectedName = device.name
            self.status = "Connected · \(device.name)"; self.lastScript = nil
            link.send(.paired(SavedMac(hostID: self.registry.hostID, name: Host.current().localizedName ?? "StudioPrompter Mac",
                                       serviceName: self.registry.serviceName, deviceID: device.id, token: device.token)))
            self.onConnected?(); self.onChange?(); self.tick()
        }
        link.onClose = { [weak self, weak link] in
            guard let self else { return }
            self.pending.removeValue(forKey: requestID)
            guard self.connection === link else { return }
            self.connection = nil; self.connectedName = nil; self.connectedID = nil; self.lastScript = nil; self.document = nil
            self.status = "iPad disconnected · waiting to reconnect"; self.onChange?()
        }
        link.start()
    }
    private func tick() {
        guard let connection, connectedName != nil, let (script, progress, playing, blackout, countdown, notice) = latestState?() else { return }
        if script != lastScript {
            let packet = Self.makeDocument(script)
            guard packet.isValid else { stop(); status = "This script is too large for iPad output."; return }
            document = packet; lastScript = script
            connection.send(.document(packet))
        }
        guard let document else { return }
        connection.send(.playback(RemotePlayback(revision: document.revision, progress: progress, playing: playing,
                                                 blackout: blackout, countdown: countdown, notice: notice)))
    }
    private static func makeDocument(_ script: Script) -> RemoteDocument {
        let storage = NSTextStorage(attributedString: ScriptTypography.text(script.text, settings: script.settings, emphasis: script.emphasis))
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 1000 - script.settings.margin * 2, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for: container)
        var lines: [RemoteLine] = []
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, used, _, glyphs, _ in
            let range = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            if !(script.text as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(RemoteLine(location: range.location, length: range.length, y: Double(used.minY), height: Double(used.height)))
            }
        }
        let lineHeight = layout.defaultLineHeight(for: ScriptTypography.font(script.settings)) + script.settings.fontSize * (script.settings.lineSpacing - 1)
        return RemoteDocument(script: script, lines: lines, textHeight: Double(layout.usedRect(for: container).height), lineHeight: Double(lineHeight))
    }
}

struct IPadPairingView: View {
    @ObservedObject var output: IPadOutput
    let retry: () -> Void
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Label("iPad Prompter", systemImage: "ipad.landscape").font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) {
                Label("Connect to the same network", systemImage: "wifi").font(.headline)
                Text("Connect your iPad to the same Wi-Fi network as this Mac. Ethernet on the Mac works too, when it connects to that same network.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            Text("Open StudioPrompter Companion on your iPad, select this Mac, and enter the pairing code.")
                .foregroundStyle(.secondary)
            if !output.code.isEmpty {
                Text(output.formattedCode).font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity).padding(18)
                    .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            if !output.devices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("PAIRED IPADS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(output.devices) { device in
                        HStack {
                            Label(device.name, systemImage: "ipad.landscape")
                            Spacer()
                            Text(output.connectedID == device.id ? "Connected" : "Offline").font(.caption).foregroundStyle(.secondary)
                            Button("Remove iPad", role: .destructive) { output.removeDevice(device.id) }
                        }
                    }
                    Text("Removal revokes access, even if the iPad is offline. It will need the new pairing code to connect again.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Label(output.status, systemImage: output.connectedName == nil ? "wifi" : "checkmark.circle.fill")
            Text("Can’t find this Mac? Allow Local Network access for both apps. Guest or public Wi-Fi may block device connections. No internet connection is needed.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                if output.isHosting { Button("Stop iPad output", action: output.stop) }
                else { Button("Start pairing", action: retry) }
            }
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }.frame(width: 506, height: 620).preferredColorScheme(.dark)
    }
}
