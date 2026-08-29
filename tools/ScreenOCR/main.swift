// Screen OCR for the external-observation Apple TV harness: what text is
// ACTUALLY on the glass? Reads screenshots (devicectl capture) and emits JSON
// per file. Ported from Archive Watch's proven harness (the "agent is never
// the tester" doctrine — the app's own claims are never the evidence for what
// a player sees; the screen is).
//
// Build: swiftc -O tools/ScreenOCR/main.swift -o /tmp/tbocr
// Run:   /tmp/tbocr shot1.png shot2.png ...   -> one JSON line per file

import Foundation
import Vision
import AppKit

// `w` (box width) is what makes clipping detectable: a line whose box runs to a
// frame edge is text the layout could not fit, which no app self-report reveals.
struct Line: Codable { let text: String; let x: Double; let y: Double; let h: Double; let w: Double }
struct Luma: Codable { let mean: Double; let stddev: Double }
struct Result: Codable {
    let file: String
    let topRegion: [String]      // top 25% — nav/title chrome
    let centerRegion: [String]   // middle 50% — question prompts, options, cards
    let bottomRegion: [String]   // bottom 25% — hints, footers, toasts
    let centerLuma: Luma         // luminance stats over the central band — a
                                 // picture-round image that failed to load reads
                                 // as a FLAT region (stddev near 0); OCR alone
                                 // cannot see a missing image
    let allText: [Line]
}

func lumaStats(_ cg: CGImage) -> Luma {
    // Sample the central band (x 0.2–0.8, y 0.25–0.75) on a decimated grid.
    let w = cg.width, h = cg.height
    guard let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
        return Luma(mean: -1, stddev: -1)
    }
    let bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
    var vals: [Double] = []
    var y = Int(0.25 * Double(h))
    while y < Int(0.75 * Double(h)) {
        var x = Int(0.2 * Double(w))
        while x < Int(0.8 * Double(w)) {
            let o = y * bpr + x * bpp
            let r = Double(ptr[o]), g = Double(ptr[o + 1]), b = Double(ptr[o + 2])
            vals.append(0.299 * r + 0.587 * g + 0.114 * b)
            x += max(1, w / 96)
        }
        y += max(1, h / 96)
    }
    guard !vals.isEmpty else { return Luma(mean: -1, stddev: -1) }
    let mean = vals.reduce(0, +) / Double(vals.count)
    let varsum = vals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
    return Luma(mean: mean, stddev: (varsum / Double(vals.count)).squareRoot())
}

for path in CommandLine.arguments.dropFirst() {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
        continue
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false     // report what is drawn, not a guess
    let handler = VNImageRequestHandler(cgImage: cg)
    try? handler.perform([request])
    var lines: [Line] = []
    for obs in request.results ?? [] {
        guard let top = obs.topCandidates(1).first else { continue }
        let b = obs.boundingBox   // normalized, origin bottom-left
        lines.append(Line(text: top.string, x: b.origin.x, y: b.origin.y,
                          h: b.height, w: b.width))
    }
    func band(_ lo: Double, _ hi: Double) -> [String] {
        lines.filter { $0.y >= lo && $0.y < hi }.sorted { $0.y > $1.y }.map(\.text)
    }
    let res = Result(file: (path as NSString).lastPathComponent,
                     topRegion: band(0.75, 1.01),
                     centerRegion: band(0.25, 0.75),
                     bottomRegion: band(0.0, 0.25),
                     centerLuma: lumaStats(cg),
                     allText: lines)
    let data = try! JSONEncoder().encode(res)
    print(String(data: data, encoding: .utf8)!)
}
