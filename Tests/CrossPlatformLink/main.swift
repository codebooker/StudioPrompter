import Foundation
import Network
import PrompterCore
import PrompterLink

// A disposable native Network.framework endpoint for cross-language TLS checks.
var registry = MacPairings()
registry.pairingCode = "ABCDEFGHJKLM"
let device = try registry.pair(name: "Android interop test", code: registry.pairingCode)
let listener = try NWListener(using: LinkSecurity.parameters(keys: registry.transportKeys), on: .any)
var links: [UUID: LinkConnection] = [:]
listener.newConnectionHandler = { connection in
    let id = UUID(), link = LinkConnection(connection)
    links[id] = link
    link.onMessage = { [weak link] message in
        guard let link else { return }
        switch message {
        case .pair(let version, _, let code):
            guard version == 2, LinkSecurity.normalize(code) == registry.pairingCode else { link.close(); return }
        case .resume(let version, let deviceID, let token):
            guard version == 2 else { link.close(); return }
            switch registry.access(id: deviceID, token: token) {
            case .removed: link.finish(with: .removed); return
            case .unknown: link.close(); return
            case .allowed: break
            }
        default: link.close(); return
        }
        link.send(.paired(SavedMac(hostID: registry.hostID, name: "Native Swift fixture", serviceName: registry.serviceName, deviceID: device.id, token: device.token)))
    }
    link.onClose = { links.removeValue(forKey: id) }
    link.start()
}
listener.stateUpdateHandler = { state in
    if case .ready = state, let port = listener.port {
        let data = try! JSONSerialization.data(withJSONObject: ["port": Int(port.rawValue), "code": registry.pairingCode])
        FileHandle.standardOutput.write(data + Data([10]))
    }
}
listener.start(queue: .main)
DispatchQueue.global().async {
    while let command = readLine() {
        if command == "REMOVE" { DispatchQueue.main.async { registry.remove(id: device.id) } }
    }
}
dispatchMain()
