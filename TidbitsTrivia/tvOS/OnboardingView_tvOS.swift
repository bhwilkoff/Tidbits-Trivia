#if os(tvOS)
import SwiftUI

/// First-run walkthrough on the TV — the same three beats as iOS/macOS/Android/web
/// (play, then LEARN, then compete; learning is the point, not a side effect), in the
/// ten-foot idiom: one screen, everything legible from the couch, and exactly ONE
/// focusable control so the remote has nowhere to get lost.
///
/// Deliberately not a paged carousel like iOS. Swiping a page indicator with a remote is
/// a chore, and a living-room audience is often several people watching one screen —
/// three short rows they can all read beats three screens one person clicks through.
struct OnboardingView_tvOS: View {
    let onDone: () -> Void
    @FocusState private var startFocused: Bool

    private let points: [(String, Color, String, String)] = [
        ("globe.americas.fill", Tidbits.Palette.blue, "All of Wikipedia, as trivia",
         "Thousands of questions built from real Wikipedia facts."),
        ("lightbulb.fill", Tidbits.Palette.yellow, "Learn something every round",
         "Miss one and we show you the fact. Missed questions quietly come back so they stick."),
        ("person.2.fill", Tidbits.Palette.grape, "Solo or together",
         "Chase your own best score, keep a daily streak, or host a trivia night for the room."),
    ]

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 44) {
                Text("WELCOME TO TIDBITS")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(TVTheme.text)
                VStack(alignment: .leading, spacing: 30) {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        HStack(alignment: .top, spacing: 28) {
                            Image(systemName: p.0)
                                .font(.system(size: 34, weight: .black))
                                .foregroundStyle(p.1.legibleForeground)
                                .frame(width: 76, height: 76)
                                .background(Circle().fill(p.1))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(p.2).font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundStyle(TVTheme.text)
                                Text(p.3).font(.system(size: 27, weight: .medium, design: .rounded))
                                    .foregroundStyle(TVTheme.textSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                Button("Start Playing", action: onDone)
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                    .focused($startFocused)
            }
            .padding(.horizontal, 120)
            .padding(.vertical, 70)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Claim focus exactly once. A bare `.task { focused = true }` re-fires when a lazy
        // view recycles and yanks focus back mid-browse (tvOS-DESIGN, learned the hard way).
        .onAppear { startFocused = true }
    }
}
#endif
