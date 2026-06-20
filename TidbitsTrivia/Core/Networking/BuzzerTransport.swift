import Foundation
import Network

/// Shared Network.framework plumbing for the Phase-1 buzzer (Decision 030):
/// the TLS-PSK parameters both sides derive from the room code, and the
/// length-prefixed JSON framing read/write helpers. Compiles for iOS AND tvOS
/// (Network is on both); the role-specific logic is in BuzzerHost / BuzzerClient.
///
/// NOTE (honesty): this transport is build-verified but NOT yet verified
/// end-to-end on two devices — Bonjour discovery + the local-network prompt
/// only exercise on real hardware. The fairness arbiter it feeds is unit-proven
/// (see BuzzerProtocol's offline harness). Wiring it into a "Buzz Night" game
/// mode + the two-device pairing test is the next slice.
enum BuzzerTransport {

    /// NWParameters secured by a TLS pre-shared key derived from the room code.
    /// A phone that can read the TV's code computes the same PSK and pairs;
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
    static func encode(_ message: BuzzerMessage) -> Data? {
        guard let body = try? JSONEncoder().encode(message),
              body.count <= Buzzer.maxMessageBytes else { return nil }
        var prefix = UInt32(body.count).bigEndian
        var out = Data(bytes: &prefix, count: Buzzer.headerBytes)
        out.append(body)
        return out
    }

    /// Send one framed message on a connection (best-effort; logs on failure).
    static func send(_ message: BuzzerMessage, over connection: NWConnection) {
        guard let data = encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { error in
            if let error { print("[buzzer] send failed: \(error)") }
        })
    }

    /// A monotonic millisecond clock for stamping (round-trip measurement only;
    /// never compared across machines). `uptimeNanoseconds` is immune to wall-
    /// clock changes — the right base for latency math.
    static func nowMillis() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
    }
}

/// Reassembles length-prefixed frames from a byte stream. NWConnection delivers
/// bytes, not messages; this buffers until a full frame is available. On tvOS
/// the receive uses `minimumIncompleteLength:` (raw callbacks can fire only on
/// close there — the Part C gotcha), which this driver wraps uniformly.
final class BuzzerFramer {
    private var buffer = Data()

    /// Append freshly received bytes; returns every complete message now decodable.
    func ingest(_ data: Data) -> [BuzzerMessage] {
        buffer.append(data)
        var messages: [BuzzerMessage] = []
        while buffer.count >= Buzzer.headerBytes {
            let len = buffer.prefix(Buzzer.headerBytes).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let total = Buzzer.headerBytes + Int(len)
            guard len <= Buzzer.maxMessageBytes else { buffer.removeAll(); break } // corrupt — resync
            guard buffer.count >= total else { break }
            let body = buffer.subdata(in: Buzzer.headerBytes..<total)
            buffer.removeSubrange(0..<total)
            if let msg = try? JSONDecoder().decode(BuzzerMessage.self, from: body) {
                messages.append(msg)
            }
        }
        return messages
    }
}
