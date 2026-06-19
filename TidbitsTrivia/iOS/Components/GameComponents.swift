#if os(iOS)
import SwiftUI

// MARK: - Question card

struct QuestionCard: View {
    let question: Question
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TriviaCategory.named(question.categoryID).name.uppercased())
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(TriviaCategory.named(question.categoryID).color.legibleAccent)
            Text(question.prompt)
                .font(.system(size: 23, weight: .heavy, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .chunkyCard()
        .padding(.trailing, Tidbits.Metric.shadowOffset)
        .padding(.top, 6)
    }
}

// MARK: - Answer button

struct AnswerButton: View {
    enum State { case idle, correct, wrong, dimmed }
    let text: String
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(text)
                    .font(Tidbits.TypeRamp.l3)
                    .foregroundStyle(fg)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let symbol { Image(systemName: symbol).font(.system(size: 18, weight: .black)).foregroundStyle(fg) }
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            .opacity(state == .dimmed ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: state)
    }

    private var fill: Color {
        switch state {
        case .idle, .dimmed: return Tidbits.Palette.surface
        case .correct:       return Tidbits.Palette.mint
        case .wrong:         return Tidbits.Palette.coral
        }
    }
    private var fg: Color {
        switch state {
        case .idle, .dimmed:   return Tidbits.Palette.ink
        case .correct, .wrong: return fill.legibleForeground   // mint→ink, coral→white
        }
    }
    private var symbol: String? {
        switch state {
        case .correct: return "checkmark"
        case .wrong:   return "xmark"
        default:       return nil
        }
    }
}

// MARK: - HUD pills

struct ScorePill: View {
    let score: Int
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill").font(.system(size: 12, weight: .black))
            Text("\(score)").font(Tidbits.TypeRamp.l6)
        }
        .foregroundStyle(Tidbits.Palette.ink)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Tidbits.Palette.yellow))
        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
        .contentTransition(.numericText())
        .animation(.snappy, value: score)
    }
}

struct StreakPill: View {
    let streak: Int
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill").font(.system(size: 12, weight: .black))
            Text("\(streak)").font(Tidbits.TypeRamp.l6)
        }
        .foregroundStyle(streak >= 2 ? .white : Tidbits.Palette.inkSoft)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(streak >= 2 ? Tidbits.Palette.coral : Tidbits.Palette.surface))
        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
        .opacity(streak >= 1 ? 1 : 0.5)
        .animation(.snappy, value: streak)
    }
}

// MARK: - Clock bar

struct ClockBar: View {
    let remaining: Double
    let budget: Double
    let tint: Color
    let label: String

    private var fraction: Double { budget <= 0 ? 0 : max(0, min(1, remaining / budget)) }
    private var urgent: Bool { remaining <= 5 }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Tidbits.TypeRamp.l6)
                .foregroundStyle(Tidbits.Palette.inkSoft)
                .frame(minWidth: 54, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tidbits.Palette.bgDeep)
                    Capsule().fill(urgent ? Tidbits.Palette.coral : tint)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 14)
            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            Text("\(Int(ceil(remaining)))s")
                .font(Tidbits.TypeRamp.l6)
                .foregroundStyle(urgent ? Tidbits.Palette.coral : Tidbits.Palette.ink)
                .frame(minWidth: 34, alignment: .trailing)
        }
    }
}
#endif
