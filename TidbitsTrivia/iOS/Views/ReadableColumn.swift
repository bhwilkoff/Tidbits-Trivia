#if os(iOS)
import SwiftUI

/// iOS-DESIGN §2.2a — cap scrolling content at a readable measure and centre it.
///
/// iPhone-first horizontal padding is correct at 390pt and wrong at 1032pt: on an iPad Pro
/// it stretched the option buttons edge to edge with their text stranded at the far left,
/// and left most of the display empty. 760pt keeps a tap target a sensible size and a line
/// of prose a readable measure, while staying a no-op on every iPhone width.
struct ReadableColumn: ViewModifier {
    var maxWidth: CGFloat = 760

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)   // centre the column in the wider container
    }
}

extension View {
    /// Cap this content at a readable width and centre it (§2.2a).
    func readableColumn(_ maxWidth: CGFloat = 760) -> some View {
        modifier(ReadableColumn(maxWidth: maxWidth))
    }
}
#endif
