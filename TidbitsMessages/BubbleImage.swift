import UIKit

/// The artwork drawn into the message bubble itself.
///
/// Kept deliberately small (600×314) and drawn with Core Graphics rather than by
/// snapshotting a SwiftUI view. Two reasons, both about extensions:
///
///  - **Memory.** A bitmap costs width × height × 4 bytes while it exists. At 600×314
///    that is ~750KB; at a "retina" 1200×628 it is 3MB, drawn on every single send.
///    An app extension is the wrong place to be casual about that, and this codebase
///    has an OOM history to prove the point.
///  - **No view lifecycle.** `ImageRenderer` on a SwiftUI view needs a layout pass and
///    is easy to get subtly wrong off the main actor; a CG drawing has neither
///    problem and renders identically whether the drawer is open or not.
///
/// The bubble has to be readable at a glance in a busy thread, so it carries the two
/// things a passer-by needs — whose round it is, and where it has got to — and nothing
/// else. The question text stays out on purpose: it would spoil the question for
/// anyone who has not tapped in yet.
enum BubbleImage {

    static func render(state: RoundState) -> UIImage? {
        let size = CGSize(width: 600, height: 314)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1                      // 1x: this is bubble art, not type
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cream = UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1)
            let ink = UIColor(red: 0.14, green: 0.12, blue: 0.10, alpha: 1)
            let coral = UIColor(red: 1.0, green: 0.36, blue: 0.21, alpha: 1)

            cream.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Coral header band — the brand read at thumbnail size.
            coral.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: 84))

            // CENTRED, not tucked at x=28. Messages draws the app's own icon over the
            // top-LEFT corner of the bubble, so a left-aligned wordmark sits directly
            // behind it and the brand reads as a smudge. Centring puts it in clear
            // space regardless of how large the system draws that icon.
            drawCentered("TIDBITS", centerX: size.width / 2, y: 26,
                         font: .systemFont(ofSize: 30, weight: .black), color: .white)

            let done = state.isFinished
            let progress = done
                ? "Round complete"
                : "Question \(min(state.index + 1, state.questionIDs.count)) of \(state.questionIDs.count)"
            draw(progress, at: CGPoint(x: 28, y: 112),
                 font: .systemFont(ofSize: 24, weight: .bold), color: ink)

            let key: (String) -> Int? = { QuestionPack.shared.correctIndex(id: $0) }
            let line = state.players.isEmpty
                ? "Waiting for players"
                : state.players
                    .prefix(4)
                    .map { "\($0.name)  \(state.score($0, correctIndexFor: key))" }
                    .joined(separator: "     ")
            draw(line, at: CGPoint(x: 28, y: 158),
                 font: .systemFont(ofSize: 20, weight: .semibold),
                 color: UIColor(red: 0.42, green: 0.39, blue: 0.36, alpha: 1))

            // The call to action follows the content instead of sitting at a fixed
            // y=254. With four or fewer players that left a band of dead space in the
            // middle of the bubble; with more, the "+N more" line crowded it.
            var cursor: CGFloat = 190
            if state.players.count > 4 {
                draw("+\(state.players.count - 4) more", at: CGPoint(x: 28, y: cursor),
                     font: .systemFont(ofSize: 17, weight: .medium),
                     color: UIColor(red: 0.42, green: 0.39, blue: 0.36, alpha: 1))
                cursor += 30
            }

            draw(done ? "Tap to see the answers" : "Tap to play",
                 at: CGPoint(x: 28, y: cursor + 14),
                 font: .systemFont(ofSize: 21, weight: .bold), color: coral)
        }
    }

    private static func draw(_ s: String, at p: CGPoint, font: UIFont, color: UIColor) {
        (s as NSString).draw(at: p, withAttributes: [
            .font: font, .foregroundColor: color,
        ])
    }

    /// Draw horizontally centred on `centerX`. Measured rather than guessed — the
    /// wordmark's width changes with the system font, and a hardcoded offset would
    /// drift off-centre on a device with a different text size.
    private static func drawCentered(_ s: String, centerX: CGFloat, y: CGFloat,
                                     font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let w = (s as NSString).size(withAttributes: attrs).width
        (s as NSString).draw(at: CGPoint(x: centerX - w / 2, y: y), withAttributes: attrs)
    }
}
