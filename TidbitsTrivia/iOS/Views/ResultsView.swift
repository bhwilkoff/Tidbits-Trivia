#if os(iOS)
import SwiftUI

/// End-of-game summary. Celebrates the score, then turns the recap into a
/// learning surface: every missed question is shown with its answer and
/// the fact, so the session ends with "now I know these."
struct ResultsView: View {
    let summary: GameSummary
    let onPlayAgain: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                scoreCard
                statsRow
                gridCard
                if !summary.missed.isEmpty { recap }
                buttons
            }
            .padding(.horizontal, Tidbits.Metric.pad)
            .padding(.vertical, 24)
        }
        .background(Tidbits.Palette.bg.ignoresSafeArea())
    }

    private var scoreCard: some View {
        VStack(spacing: 8) {
            Text(headline.uppercased())
                .font(Tidbits.TypeRamp.l2)
                .foregroundStyle(Tidbits.Palette.ink)
            Text("\(summary.score)")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
                .contentTransition(.numericText())
            Text("\(summary.mode.title) · \(summary.category.name)")
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .chunkyCard(fill: summary.category.color.opacity(0.18))
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatBox(value: "\(summary.correct)/\(summary.total)", label: "Correct", tint: Tidbits.Palette.mint)
            StatBox(value: "\(Int(summary.accuracy * 100))%", label: "Accuracy", tint: Tidbits.Palette.blue)
            StatBox(value: "\(summary.maxStreak)", label: "Best Streak", tint: Tidbits.Palette.coral)
        }
    }

    /// Spoiler-free Wordle-style grid — the shareable retention loop.
    private var emojiGrid: String {
        summary.answered.map { a in
            a.chosenIndex == nil ? "⬛" : (a.isCorrect ? "🟩" : "🟥")
        }.joined()
    }

    private var gridCard: some View {
        VStack(spacing: 8) {
            Text(emojiGrid).font(.system(size: 26))
            Text("Spoiler-free — safe to share").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .chunkyCard(fill: Tidbits.Palette.bgDeep).padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var recap: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tidbits to remember", systemImage: "brain.head.profile")
                .font(Tidbits.TypeRamp.l2)
                .foregroundStyle(Tidbits.Palette.ink)
            ForEach(summary.missed) { miss in
                VStack(alignment: .leading, spacing: 5) {
                    Text(miss.question.prompt)
                        .font(Tidbits.TypeRamp.l3)
                        .foregroundStyle(Tidbits.Palette.ink)
                    Text("Answer: \(miss.question.correctAnswer)")
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.mint)
                    if !miss.question.explanation.isEmpty {
                        Text(miss.question.explanation)
                            .font(Tidbits.TypeRamp.l5)
                            .foregroundStyle(Tidbits.Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .chunkyCard(fill: Tidbits.Palette.surface)
                .padding(.trailing, Tidbits.Metric.shadowOffset)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            ShareLink(item: shareText) {
                Label("Share Score", systemImage: "square.and.arrow.up")
                    .font(Tidbits.TypeRamp.l3)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: Tidbits.Metric.radius).fill(Tidbits.Palette.blue))
                    .overlay(RoundedRectangle(cornerRadius: Tidbits.Metric.radius).strokeBorder(Tidbits.Palette.border, lineWidth: 3))
            }
            Button("Play Again", action: onPlayAgain)
                .buttonStyle(ChunkyButtonStyle())
            Button("Done", action: onDone)
                .font(Tidbits.TypeRamp.l3)
                .foregroundStyle(Tidbits.Palette.inkSoft)
                .padding(.top, 2)
        }
        .padding(.trailing, Tidbits.Metric.shadowOffset)
        .padding(.top, 4)
    }

    private var headline: String {
        switch summary.accuracy {
        case 1: return "Flawless!"
        case 0.8...: return "Brilliant"
        case 0.5..<0.8: return "Nicely done"
        default: return "Good run"
        }
    }

    private var shareText: String {
        let pct = Int(summary.accuracy * 100)
        let header = summary.mode == .daily ? "🧠 Tidbits Daily — \(QuestionProvider.dayKey())" : "🧠 Tidbits Trivia — \(summary.mode.title)"
        return "\(header)\n\(emojiGrid)\n\(summary.correct)/\(summary.total) right · \(summary.score) pts · \(pct)%\nTrivia from all of Wikipedia. Can you beat it?"
    }
}

struct StatBox: View {
    let value: String
    let label: String
    let tint: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .chunkyCard(fill: tint.opacity(0.18))
        .padding(.trailing, Tidbits.Metric.shadowOffset)
        .padding(.bottom, Tidbits.Metric.shadowOffset)
    }
}
#endif
