import Foundation
import Network
import PrompterCore
import PrompterLink

// Uses the same Apple TLS and Codable implementation as the iPad companion.
let port = NWEndpoint.Port(rawValue: UInt16(CommandLine.arguments[1])!)!
let code = CommandLine.arguments[2]
let connection = LinkConnection(NWConnection(host: "127.0.0.1", port: port, using: LinkSecurity.parameters(code: code)))
var authorized = false
var revision: UUID?
connection.onReady = { connection.send(.pair(version: 2, name: "Apple client test", code: code)) }
connection.onMessage = { message in
    switch message {
    case .paired(let saved):
        guard !saved.removed, saved.token.count == 64,
              saved.serviceName == "StudioPrompter-" + saved.hostID.uuidString.prefix(8) else { exit(3) }
        authorized = true
    case .document(let doc):
        guard authorized, doc.isValid else { exit(4) }
        revision = doc.revision
    case .playback(let state):
        guard authorized, revision == state.revision, state.isValid else { exit(5) }
        print("Apple client received paired, document, playback")
        exit(0)
    default: break
    }
}
connection.onClose = { fputs("Apple connection closed before playback\n", stderr); exit(6) }
DispatchQueue.main.asyncAfter(deadline: .now() + 10) { fputs("Apple connection timed out\n", stderr); exit(7) }
connection.start()
dispatchMain()
