import Foundation
import Network
import Security
import CryptoKit

public enum LinkSecurity {
    public static func normalize(_ code: String) -> String { code.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) } }
    public static func newCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<12).map { _ in alphabet.randomElement()! })
    }
    public static func parameters(code: String) -> NWParameters { parameters(keys: [code]) }
    public static func parameters(keys: [String]) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        for code in Set(keys.map(normalize)) {
            let key = Data(SHA256.hash(data: Data(code.utf8)))
            let identity = Data(("StudioPrompter-v2-" + SHA256.hash(data: Data(("identity:" + code).utf8)).map { String(format: "%02x", $0) }.joined()).utf8)
            let secret = key.withUnsafeBytes { DispatchData(bytes: $0) }
            let label = identity.withUnsafeBytes { DispatchData(bytes: $0) }
            sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, secret as __DispatchData, label as __DispatchData)
        }
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_add_tls_ciphersuite(tls.securityProtocolOptions, SSLCipherSuite(TLS_PSK_WITH_AES_128_GCM_SHA256))
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}

/// All callbacks and state are confined to the main queue. One framed send at a
/// time; playback messages coalesce rather than queuing seconds of stale motion.
public final class LinkConnection {
    public var onReady: (() -> Void)?
    public var onMessage: ((LinkMessage) -> Void)?
    public var onClose: (() -> Void)?
    private let connection: NWConnection
    private var closed = false
    private var sending = false
    private var finishing = false
    private var pending: [LinkMessage] = []
    private var timeout: DispatchWorkItem?
    public init(_ connection: NWConnection) { self.connection = connection }
    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.closed else { return }
            switch state {
            case .ready: self.timeout?.cancel(); self.onReady?(); self.receiveHeader()
            case .failed, .cancelled: self.close()
            default: break
            }
        }
        let deadline = DispatchWorkItem { [weak self] in self?.close() }
        timeout = deadline; DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: deadline)
        connection.start(queue: .main)
    }
    public func send(_ message: LinkMessage) {
        guard !closed else { return }
        if sending {
            if case .playback = message, let last = pending.last, case .playback = last { pending.removeLast() }
            guard pending.count < 8 else { close(); return }
            pending.append(message); return
        }
        guard let data = try? LinkFraming.frame(message) else { close(); return }
        sending = true
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, !self.closed else { return }
            self.sending = false
            if error != nil { self.close(); return }
            if !self.pending.isEmpty { self.send(self.pending.removeFirst()) }
            else if self.finishing { self.close() }
        })
    }
    /// Deliver a final status after any in-flight frame, discard queued script data,
    /// and then close. The receiver still decodes a final frame delivered with EOF.
    public func finish(with message: LinkMessage) {
        guard !closed else { return }
        finishing = true; pending.removeAll(); send(message)
    }
    public func close() {
        guard !closed else { return }; closed = true
        timeout?.cancel(); pending.removeAll(); connection.cancel(); onClose?()
    }
    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            guard error == nil, let data, let length = try? LinkFraming.length(data) else { self.close(); return }
            self.connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] body, _, complete, error in
                guard let self, !self.closed else { return }
                guard error == nil, let body, body.count == length,
                      let message = try? JSONDecoder().decode(LinkMessage.self, from: body) else { self.close(); return }
                self.onMessage?(message)
                if !self.closed { if complete { self.close() } else { self.receiveHeader() } }
            }
        }
    }
}
