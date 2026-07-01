import Foundation
import Network
import CryptoKit

/// Shared Network.framework plumbing for Trivia Night local multiplayer
/// (Decision 033), migrated to the cross-platform v2 wire (docs/CROSS-PLATFORM-
/// MULTIPLAYER.md): plain TCP + app-layer AES-GCM keyed by the room code, so an
/// Android device — whose TLS stack can't speak Apple's GCM-PSK suite — can join.
///
/// **No Apple↔Apple degradation:** `includePeerToPeer` stays on, so two Apple
/// devices still pair over AWDL with no router; the same Bonjour service is also
/// advertised on the LAN, which is how Android (no AWDL) discovers it over a
/// shared Wi-Fi. The AES-GCM key is the SAME `SHA256("tidbits-night-v1:<CODE>")`
/// this file already derived for the PSK, reused as the symmetric key.
///
/// Build-verified, NOT yet two-device-verified — a cross-platform pairing test is
/// the gate.
enum NightTransport {

    /// Plain-TCP parameters with peer-to-peer Wi-Fi opted in (Apple↔Apple AWDL).
    /// Confidentiality + auth are the app-layer AES-GCM below, not TLS.
    static func parameters() -> NWParameters {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        return params
    }

    /// Frame a message: `4-byte big-endian length + AES-256-GCM(nonce‖ciphertext‖tag)`.
    /// Byte-identical to the Android `NightWire` scheme (12-byte nonce, 16-byte tag).
    static func encode(_ message: NightMessage, key: SymmetricKey) -> Data? {
        guard let plain = try? JSONEncoder().encode(message) else { return nil }
        guard let sealed = try? AES.GCM.seal(plain, using: key) else { return nil }
        // sealed.nonce is 12 bytes; combined = nonce ‖ ciphertext ‖ tag.
        var body = Data(sealed.nonce)
        body.append(sealed.ciphertext)
        body.append(sealed.tag)
        guard body.count <= Night.maxMessageBytes else { return nil }
        var prefix = UInt32(body.count).bigEndian
        var out = Data(bytes: &prefix, count: Night.headerBytes)
        out.append(body)
        return out
    }

    /// Send one framed, encrypted message on a connection (best-effort).
    static func send(_ message: NightMessage, over connection: NWConnection, key: SymmetricKey) {
        guard let data = encode(message, key: key) else { return }
        connection.send(content: data, completion: .contentProcessed { error in
            if let error { print("[night] send failed: \(error)") }
        })
    }
}

/// Reassembles length-prefixed frames from a byte stream and opens each with the
/// room-code key. A wrong code fails the GCM tag → the frame is dropped (the
/// "only a device that can read the code pairs" guarantee, now app-layer).
final class NightFramer {
    private let key: SymmetricKey
    private var buffer = Data()

    init(key: SymmetricKey) { self.key = key }

    func ingest(_ data: Data) -> [NightMessage] {
        buffer.append(data)
        var messages: [NightMessage] = []
        while buffer.count >= Night.headerBytes {
            let len = buffer.prefix(Night.headerBytes).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let total = Night.headerBytes + Int(len)
            guard len <= Night.maxMessageBytes else { buffer.removeAll(); break }   // corrupt — resync
            guard buffer.count >= total else { break }
            let body = buffer.subdata(in: Night.headerBytes..<total)
            buffer.removeSubrange(0..<total)
            if let msg = open(body) { messages.append(msg) }
        }
        return messages
    }

    private func open(_ body: Data) -> NightMessage? {
        guard body.count > 12 + 16 else { return nil }
        let nonceData = body.prefix(12)
        let tag = body.suffix(16)
        let ciphertext = body.dropFirst(12).dropLast(16)
        guard let nonce = try? AES.GCM.Nonce(data: nonceData),
              let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag),
              let plain = try? AES.GCM.open(box, using: key),
              let msg = try? JSONDecoder().decode(NightMessage.self, from: plain) else { return nil }
        return msg
    }
}
