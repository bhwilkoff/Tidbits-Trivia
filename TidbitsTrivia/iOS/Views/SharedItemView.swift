#if os(iOS)
import SwiftUI

/// What a `tidbits://item/<id>` link opens (DEEP_LINKS.md) — the in-app half of the
/// canonical twin the web app renders at `https://tidbitstrivia.com/item/<id>`.
///
/// It shows the FACT, not a quiz. Someone arriving here was sent a thing worth knowing
/// by a friend; making them guess it first is a puzzle they didn't ask for. The answer,
/// the explanation and the door out to the source are the payload — playing is the
/// invitation underneath it.
struct SharedItemView: View {
    let id: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var question: Question? { SharedItem.question(id: id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let q = question {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(TriviaCategory.named(q.categoryID).name.uppercased())
                            .font(Tidbits.TypeRamp.l6)
                            .foregroundStyle(Tidbits.Palette.inkSoft)
                        Text(q.prompt)
                            .font(Tidbits.TypeRamp.l1)
                            .foregroundStyle(Tidbits.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ANSWER")
                                .font(Tidbits.TypeRamp.l6)
                                .foregroundStyle(Tidbits.Palette.inkSoft)
                            Text(q.correctAnswer)
                                .font(Tidbits.TypeRamp.l2)
                                .foregroundStyle(Tidbits.Palette.ink)
                            if !q.explanation.isEmpty {
                                Text(q.explanation)
                                    .font(Tidbits.TypeRamp.l4)
                                    .foregroundStyle(Tidbits.Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let url = q.sourceURL {
                                Button("Read on Wikipedia") { openURL(url) }
                                    .font(Tidbits.TypeRamp.l3)
                                    .foregroundStyle(Tidbits.Palette.blue)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .chunkyCard()
                    }
                    .padding(20)
                } else {
                    // A retired row is a real outcome, not an error state to hide.
                    ContentUnavailableView(
                        "Not found",
                        systemImage: "questionmark.circle",
                        description: Text("This link doesn't point at a question any more — it may have been retired from the bank since it was shared."))
                        .padding(.top, 60)
                }
            }
            .background(Tidbits.Palette.bg)
            .navigationTitle("Tidbits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
#endif
