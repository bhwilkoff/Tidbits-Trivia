// Renders the Tidbits app icon (1024x1024 PNG) with CoreGraphics — no deps.
// Usage: swift make_icon.swift <out.png>
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let S: CGFloat = 1024

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF)/255, green: CGFloat((hex >> 8) & 0xFF)/255,
            blue: CGFloat(hex & 0xFF)/255, alpha: 1)
}
let coral = rgb(0xFF5C5C), cream = rgb(0xFBF3E4), ink = rgb(0x1A1714)
let yellow = rgb(0xFFC93C), blue = rgb(0x2D5BFF), mint = rgb(0x2FCB8A), grape = rgb(0x8B5CF6)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Background
ctx.setFillColor(coral); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

// Memphis confetti
func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: CGColor) {
    ctx.setFillColor(c); ctx.fillEllipse(in: CGRect(x: x-r, y: y-r, width: 2*r, height: 2*r))
}
dot(170, 840, 60, yellow); dot(880, 200, 46, mint); dot(840, 720, 34, blue)
// a couple of small rings
ctx.setStrokeColor(grape); ctx.setLineWidth(22)
ctx.strokeEllipse(in: CGRect(x: 120, y: 150, width: 90, height: 90))

// Center sticker card (rounded square with ink border + hard offset shadow)
let cardSize: CGFloat = 560
let card = CGRect(x: (S-cardSize)/2, y: (S-cardSize)/2, width: cardSize, height: cardSize)
let radius: CGFloat = 96
func roundedPath(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}
// shadow
ctx.setFillColor(ink)
ctx.addPath(roundedPath(card.offsetBy(dx: 34, dy: -34), radius)); ctx.fillPath()
// card fill + border
ctx.setFillColor(cream); ctx.addPath(roundedPath(card, radius)); ctx.fillPath()
ctx.setStrokeColor(ink); ctx.setLineWidth(26); ctx.addPath(roundedPath(card, radius)); ctx.strokePath()

// Big ink "T" built from two rounded bars
ctx.setFillColor(ink)
let barW: CGFloat = 340, barH: CGFloat = 80
let topBar = CGRect(x: (S-barW)/2, y: card.maxY - 150, width: barW, height: barH)
ctx.addPath(roundedPath(topBar, 30)); ctx.fillPath()
let stemW: CGFloat = 90, stemH: CGFloat = 300
let stem = CGRect(x: (S-stemW)/2, y: topBar.minY - stemH + 10, width: stemW, height: stemH)
ctx.addPath(roundedPath(stem, 30)); ctx.fillPath()
// a coral "spark" dot to dot the motif
dot(S/2 + 150, card.minY + 150, 30, coral)

guard let image = ctx.makeImage() else { exit(1) }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")
