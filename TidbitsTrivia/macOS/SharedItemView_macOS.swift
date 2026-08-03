#if os(macOS)
import SwiftUI

/// The Mac half of the shared-question twin (DEEP_LINKS.md). Same content as the iPhone
/// sheet and the web landing page; the Mac idiom is a fixed-size sheet with its own Done
/// button rather than a navigation stack, per macOS-DESIGN.
struct SharedItemView_macOS: View {
    let id: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var question: Question? { SharedItem.question(id: id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let q = question {
                Text(TriviaCategory.named(q.categoryID).name.uppercased())
                    .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                Text(q.prompt)
                    .font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ANSWER")
                            .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                        Text(q.correctAnswer)
                            .font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                        if !q.explanation.isEmpty {
                            Text(q.explanation)
                                .font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let url = q.sourceURL {
                            Button("Read on Wikipedia") { openURL(url) }
                                .buttonStyle(.link)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .chunkyCard()
                }
            } else {
                Text("Not found").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Text("This link doesn't point at a question any more — it may have been retired from the bank since it was shared.")
                    .font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
        .background(Tidbits.Palette.bg)
    }
}
#endif
