import Foundation
import Compression

/// A minimal ZIP reader/writer — enough for the Tidbits package
/// (docs/LIVE-PACKAGE-FORMAT.md §1) and nothing more.
///
/// Foundation has no ZIP API and the project takes no third-party packages, so
/// this is hand-rolled against the format's fixed points: a reader that walks
/// the CENTRAL DIRECTORY (so an archive re-zipped by Finder, which writes data
/// descriptors, still opens), methods 0 (store) and 8 (deflate, via the
/// Compression framework's raw-DEFLATE), no encryption, no zip64. The writer
/// stores everything: media is already compressed and the JSON is small.
nonisolated enum ZipContainer {
    struct Entry: Sendable {
        let name: String
        let method: Int
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: LocalizedError {
        case notAZip
        case unsupportedMethod(Int, String)
        case corrupt(String)
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .notAZip: return "That file is not a zip archive."
            case .unsupportedMethod(let m, let n): return "\(n) is compressed with an unsupported method (\(m))."
            case .corrupt(let what): return "The archive is damaged (\(what))."
            case .tooLarge: return "The archive is larger than 4 GB, which a Tidbits package cannot be."
            }
        }
    }

    // MARK: Reading

    /// Every entry's location, from the central directory.
    static func entries(in data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        // End of central directory: scan back over a possible comment (≤ 65535 bytes).
        var eocd = -1
        var i = bytes.count - 22
        let floor = max(0, bytes.count - 22 - 65535)
        while i >= floor {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4b, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let count = Int(u16(bytes, eocd + 10))
        let cdOffset = Int(u32(bytes, eocd + 16))
        guard cdOffset < bytes.count, count < 0xFFFF else { throw ZipError.tooLarge }

        var out: [Entry] = []
        var p = cdOffset
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(bytes, p) == 0x0201_4b50 else { throw ZipError.corrupt("central directory") }
            let method = Int(u16(bytes, p + 10))
            let crc = u32(bytes, p + 16)
            let csize = Int(u32(bytes, p + 20))
            let usize = Int(u32(bytes, p + 24))
            let nameLen = Int(u16(bytes, p + 28))
            let extraLen = Int(u16(bytes, p + 30))
            let commentLen = Int(u16(bytes, p + 32))
            let local = Int(u32(bytes, p + 42))
            guard p + 46 + nameLen <= bytes.count else { throw ZipError.corrupt("entry name") }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            out.append(Entry(name: name, method: method, crc32: crc, compressedSize: csize,
                             uncompressedSize: usize, localHeaderOffset: local))
            p += 46 + nameLen + extraLen + commentLen
        }
        return out
    }

    /// The bytes of one entry, inflated if needed and CRC-checked.
    static func extract(_ entry: Entry, from data: Data) throws -> Data {
        let bytes = [UInt8](data)
        let h = entry.localHeaderOffset
        guard h + 30 <= bytes.count, u32(bytes, h) == 0x0403_4b50 else { throw ZipError.corrupt("local header of \(entry.name)") }
        let nameLen = Int(u16(bytes, h + 26))
        let extraLen = Int(u16(bytes, h + 28))
        let start = h + 30 + nameLen + extraLen
        let end = start + entry.compressedSize
        guard end <= bytes.count else { throw ZipError.corrupt("data of \(entry.name)") }
        let raw = Data(bytes[start..<end])
        let plain: Data
        switch entry.method {
        case 0: plain = raw
        case 8: plain = try inflate(raw, expected: entry.uncompressedSize, name: entry.name)
        default: throw ZipError.unsupportedMethod(entry.method, entry.name)
        }
        guard crc32(plain) == entry.crc32 else { throw ZipError.corrupt("checksum of \(entry.name)") }
        return plain
    }

    /// Everything, by name. Fine for a package (tens of MB); not for archives in general.
    static func readAll(_ data: Data) throws -> [String: Data] {
        var out: [String: Data] = [:]
        for e in try entries(in: data) where !e.name.hasSuffix("/") {
            out[e.name] = try extract(e, from: data)
        }
        return out
    }

    private static func inflate(_ raw: Data, expected: Int, name: String) throws -> Data {
        guard expected > 0 else { return Data() }
        var dst = [UInt8](repeating: 0, count: expected)
        let got = raw.withUnsafeBytes { src -> Int in
            dst.withUnsafeMutableBufferPointer { d in
                compression_decode_buffer(d.baseAddress!, expected,
                                          src.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard got == expected else { throw ZipError.corrupt("inflate of \(name)") }
        return Data(dst)
    }

    // MARK: Writing

    /// Write entries in the given order, all STORED, names UTF-8 flagged.
    static func write(_ entries: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        // A fixed DOS timestamp (2026-01-01 00:00) so the same inputs give the
        // same bytes — a package is a document, not a log.
        let dosTime: UInt16 = 0, dosDate: UInt16 = UInt16((2026 - 1980) << 9 | 1 << 5 | 1)
        for (name, data) in entries {
            let nameBytes = Array(name.utf8)
            let crc = crc32(data)
            let offset = UInt32(out.count)
            out.append(le32(0x0403_4b50)); out.append(le16(20)); out.append(le16(0x0800))
            out.append(le16(0)); out.append(le16(dosTime)); out.append(le16(dosDate))
            out.append(le32(crc)); out.append(le32(UInt32(data.count))); out.append(le32(UInt32(data.count)))
            out.append(le16(UInt16(nameBytes.count))); out.append(le16(0))
            out.append(contentsOf: nameBytes); out.append(data)

            central.append(le32(0x0201_4b50)); central.append(le16(20)); central.append(le16(20))
            central.append(le16(0x0800)); central.append(le16(0)); central.append(le16(dosTime)); central.append(le16(dosDate))
            central.append(le32(crc)); central.append(le32(UInt32(data.count))); central.append(le32(UInt32(data.count)))
            central.append(le16(UInt16(nameBytes.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0)); central.append(le32(offset))
            central.append(contentsOf: nameBytes)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x0605_4b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(entries.count))); out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(cdOffset)); out.append(le16(0))
        return out
    }

    // MARK: Bits

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }
}
