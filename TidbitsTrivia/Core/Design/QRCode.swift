import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// QR generation, shared by every Apple platform.
///
/// Returns a `CGImage` rather than a `UIImage`/`NSImage` on purpose: Core must never
/// import per-platform UI, and CoreGraphics is common to all of them. Each shell
/// wraps the result in its own `Image`.
///
/// This matters most on tvOS, where a QR is not a nicety but the ONLY practical way
/// to move a link off the screen — there's no clipboard worth using, no share sheet,
/// and no browser. The TV shows the code; a phone in the room does the rest.
nonisolated enum QRCode {

    /// `scale` multiplies the generator's native (tiny) output. Ten is right for a
    /// phone-sized sheet; a ten-foot TV needs more, so callers pass their own.
    static func image(for string: String, scale: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        // Medium correction survives a camera pointed at a TV from across a room —
        // glare and off-angle both eat modules.
        filter.correctionLevel = "M"
        guard let ci = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else {
            return nil
        }
        return CIContext().createCGImage(ci, from: ci.extent)
    }
}
