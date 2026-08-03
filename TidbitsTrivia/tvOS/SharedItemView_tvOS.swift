#if os(tvOS)
import SwiftUI

/// The TV half of the shared-question twin (DEEP_LINKS.md `/item/{id}`). Same content as
/// the iPhone sheet, the Mac sheet and the web landing page, at the ten-foot ramp.
///
/// It shows the FACT, not a quiz — a link someone sent is not a puzzle the room asked to
/// be set. One focusable control (Done), because there is nothing else to do here.
struct SharedItemView_tvOS: View {
    let id: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var doneFocused: Bool

    private var question: Question? { SharedItem.question(id: id) }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let q = question {
                        Text(TriviaCategory.named(q.categoryID).name.uppercased())
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(TVTheme.textSoft)
                        Text(q.prompt)
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(TVTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        TVRecordsCard(fill: TVTheme.panel) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("ANSWER")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(TVTheme.textSoft)
                                Text(q.correctAnswer)
                                    .font(.system(size: 38, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                if !q.explanation.isEmpty {
                                    Text(q.explanation)
                                        .font(.system(size: 29, weight: .medium, design: .rounded))
                                        .foregroundStyle(TVTheme.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                // No "Read on Wikipedia": there is no browser on the TV, so
                                // a link here would be a dead end rather than a door.
                            }
                        }
                    } else {
                        Text("Not found")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(TVTheme.text)
                        Text("This link doesn't point at a question any more — it may have been retired from the bank since it was shared.")
                            .font(.system(size: 29, weight: .medium, design: .rounded))
                            .foregroundStyle(TVTheme.textSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Done") { dismiss() }
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                        .focused($doneFocused)
                }
                .padding(.horizontal, 120)
                .padding(.vertical, 70)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { doneFocused = true }
        .onExitCommand { dismiss() }   // Menu leaves — modal, so this is allowed
    }
}
#endif
