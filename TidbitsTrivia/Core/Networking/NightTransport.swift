import Foundation
import CryptoKit

/// Trivia Night frame codec (Decision 033) — the cross-platform v2 wire
/// (docs/CROSS-PLATFORM-MULTIPLAYER.md): app-layer AES-GCM keyed by the room
/// code, so an Android device — whose TLS stack can't speak Apple's GCM-PSK
/// suite — can join. The AES-GCM key is `SHA256("tidbits-night-v1:<CODE>")`.
///
/// Pure value-logic (no Network import): a transport behind the `NightPeerLink`
/// seam moves these frames as opaque bytes — Bonjour mDNS+TCP today (which keeps
/// `includePeerToPeer`, so Apple↔Apple stays router-free over AWDL), Wi-Fi Aware
/// / BLE / remote links later, all carrying the identical frames.
enum NightTransport {

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
