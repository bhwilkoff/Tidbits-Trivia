import Foundation
import Network

/// Shared Network.framework plumbing for Trivia Night local multiplayer
/// (Decision 033): the TLS-PSK parameters both sides derive from the room code,
/// and the length-prefixed JSON framing. Compiles for iOS AND tvOS (Network is
/// on both) — hosting is no longer TV-only, so neither is this.
///
/// NOTE (honesty): build-verified; the Bonjour discovery + local-network prompt
/// only exercise on real hardware, so a two-device pairing test is the gate
/// before this is called "done".
enum NightTransport {

    /// NWParameters secured by a TLS pre-shared key derived from the room code.
    /// A device that can read the host's code computes the same PSK and pairs;
    /// one that can't, can't. Peer-to-peer Wi-Fi is opted in so discovery works
    /// without an access point.
    static func parameters(code: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let keyData = RoomCode.presharedKeyData(for: code)
        let identityData = Data(RoomCode.pskIdentity.utf8)

        keyData.withUnsafeBytes { (keyBuf: UnsafeRawBufferPointer) in
            let keyDD = DispatchData(bytes: keyBuf)
            identityData.withUnsafeBytes { (idBuf: UnsafeRawBufferPointer) in
                let idDD = DispatchData(bytes: idBuf)
                sec_protocol_options_add_pre_shared_key(
                    tls.securityProtocolOptions,
                    keyDD as __DispatchData,
                    idDD as __DispatchData)
            }
        }
        sec_protocol_options_append_tls_ciphersuite(
            tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)

        let params = NWParameters(tls: tls)
        params.includePeerToPeer = true
        return params
    }

    /// Frame a message: a 4-byte big-endian length prefix + JSON body.
    static func encode(_ message: NightMessage) -> Data? {
        guard let body = try? JSONEncoder().encode(message),
              body.count <= Night.maxMessageBytes else { return nil }
        var prefix = UInt32(body.count).bigEndian
        var out = Data(bytes: &prefix, count: Night.headerBytes)
        out.append(body)
        return out
    }

    /// Send one framed message on a connection (best-effort; logs on failure).
    static func send(_ message: NightMessage, over connection: NWConnection) {
        guard let data = encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { error in
            if let error { print("[night] send failed: \(error)") }
        })
    }
}

/// Reassembles length-prefixed frames from a byte stream. NWConnection delivers
/// bytes, not messages; this buffers until a full frame is available.
final class NightFramer {
    private var buffer = Data()

    /// Append freshly received bytes; returns every complete message now decodable.
    func ingest(_ data: Data) -> [NightMessage] {
        buffer.append(data)
        var messages: [NightMessage] = []
        while buffer.count >= Night.headerBytes {
            let len = buffer.prefix(Night.headerBytes).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let total = Night.headerBytes + Int(len)
            guard len <= Night.maxMessageBytes else { buffer.removeAll(); break } // corrupt — resync
            guard buffer.count >= total else { break }
            let body = buffer.subdata(in: Night.headerBytes..<total)
            buffer.removeSubrange(0..<total)
            if let msg = try? JSONDecoder().decode(NightMessage.self, from: body) {
                messages.append(msg)
            }
        }
        return messages
    }
}
