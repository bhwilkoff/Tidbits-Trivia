#if os(iOS)
import SwiftUI

/// First-run walkthrough — shown once. Frames the app around its mission:
/// play, learn, compete (in that order — learning is the point, not a
/// side effect). A HintBanner/Walkthrough per universal-feature-states.
struct OnboardingView: View {
    let onDone: () -> Void
    @State private var page = 0

    private struct Slide: Identifiable {
        let id = UUID(); let symbol: String; let color: Color; let title: String; let body: String
    }
    private let slides = [
        Slide(symbol: "globe.americas.fill", color: Tidbits.Palette.blue,
              title: "All of Wikipedia,\nas trivia", body: "Thousands of questions built from real Wikipedia facts — and you can spin up a quiz on any topic you like."),
        Slide(symbol: "lightbulb.fill", color: Tidbits.Palette.yellow,
              title: "Learn something\nevery round", body: "Miss one? We show you the fact and the article. Missed questions quietly come back so they actually stick."),
        Slide(symbol: "person.2.fill", color: Tidbits.Palette.grape,
              title: "Solo or\ntogether", body: "Chase your own best score, keep a daily streak, or pass the phone for 2–4 player trivia night."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(slides.enumerated()), id: \.offset) { i, slide in
                    VStack(spacing: 22) {
                        Spacer()
                        Image(systemName: slide.symbol)
                            .font(.system(size: 72, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 132, height: 132)
                            .background(Circle().fill(slide.color))
                            .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 4))
                        Text(slide.title)
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Tidbits.Palette.ink)
                        Text(slide.body)
                            .font(Tidbits.TypeRamp.l4)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Tidbits.Palette.inkSoft)
                            .padding(.horizontal, 28)
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page == slides.count - 1 ? "Start Playing" : "Next") {
                if page < slides.count - 1 { withAnimation { page += 1 } } else { onDone() }
            }
            .buttonStyle(ChunkyButtonStyle())
            .padding(.horizontal, Tidbits.Metric.pad)
            .padding(.trailing, Tidbits.Metric.shadowOffset)
            .padding(.bottom, 24)

            if page < slides.count - 1 {
                Button("Skip") { onDone() }.tint(Tidbits.Palette.inkSoft).padding(.bottom, 8)
            }
        }
        .background(Tidbits.Palette.bg.ignoresSafeArea())
    }
}
#endif
