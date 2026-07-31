#if os(iOS)
import SwiftUI

/// iOS-DESIGN §2.2a — cap scrolling content at a readable measure.
///
/// iPhone-first horizontal padding is correct at 390pt and wrong at 1032pt: on an iPad Pro
/// it stretched the option buttons edge to edge with their text stranded at the far left,
/// and left most of the display empty. 760pt keeps a tap target a sensible size and a line
/// of prose a readable measure, while staying a no-op on every iPhone width.
///
/// Alignment matters more than it looks. A surface with a system `navigationTitle` renders
/// that title flush-left in the nav bar, which no content modifier can move — centring the
/// column underneath it leaves the title visibly orphaned. Those surfaces pass `.leading`
/// so the column lines up with their title; surfaces that own their heading (the game, Home)
/// centre.
struct ReadableColumn: ViewModifier {
    var maxWidth: CGFloat = 760
    var alignment: Alignment = .center

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth, alignment: alignment)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

extension View {
    /// Cap this content at a readable width (§2.2a). Pass `.leading` under a system
    /// navigation title so the column aligns with it.
    func readableColumn(_ maxWidth: CGFloat = 760, alignment: Alignment = .center) -> some View {
        modifier(ReadableColumn(maxWidth: maxWidth, alignment: alignment))
    }
}
#endif
