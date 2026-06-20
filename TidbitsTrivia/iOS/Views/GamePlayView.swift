#if os(iOS)
import SwiftUI

/// The live question screen. Observes the shared GameEngine and renders
/// the current question, answer choices, and — after answering — the
/// "learn the fact" reveal that turns every miss (and hit) into a
/// curiosity door (the learning-orientation mandate).
struct GamePlayView: View {
    let game: GameEngine
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            hud
            if let q = game.current {
                ScrollView {
                    VStack(spacing: 18) {
                        QuestionCard(question: q)
                        if game.mode == .sweep { sweepGrid }
                        if game.mode == .stake && game.phase == .playing { stakeSelector }
                        answers(for: q)
                        if game.phase == .reveal { reveal(for: q) }
                    }
                    .padding(.horizontal, Tidbits.Metric.pad)
                    .padding(.bottom, 24)
                    // Stable per-question identity so the prompt AND the four
                    // option buttons swap as ONE atomic subtree on advance —
                    // not an in-place diff that mutates the reused buttons a
                    // frame before/after the prompt (the "text loads after the
                    // buttons / options don't match the last question" jank).
                    .id(game.index)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            Spacer(minLength: 0)
            if game.phase == .reveal { nextBar }
        }
        .background(Tidbits.Palette.bg.ignoresSafeArea())
        .task {
            // Screenshot/CI autopilot — no-op unless TIDBITS_AUTOPILOT=1.
            guard DebugHooks.autopilot else { return }
            while game.phase != .finished && game.phase != .idle {
                try? await Task.sleep(for: .seconds(0.9))
                switch game.phase {
                case .playing:
                    if game.mode == .stake && game.currentStake == 0 { game.setStake(game.stakeTiers.first?.value ?? 1) }
                    game.submit(0)
                case .reveal:  game.advance()
                default:       break
                }
            }
        }
    }

    // MARK: HUD

    private var hud: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onQuit) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Tidbits.Palette.ink)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Tidbits.Palette.surface))
                        .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                }
                Spacer()
                StreakPill(streak: game.streak)
                Spacer()
                ScorePill(score: game.score)
            }
            ClockBar(remaining: game.remaining,
                     budget: game.mode.perQuestionSeconds ?? game.mode.globalClockSeconds ?? 30,
                     tint: game.mode.accent,
                     label: progressLabel)
        }
        .padding(.horizontal, Tidbits.Metric.pad)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var progressLabel: String {
        switch game.mode {
        case .timeAttack, .survival: return "#\(game.index + 1)"
        default: return "\(game.index + 1) / \(game.questions.count)"
        }
    }

    // MARK: Answers

    private func answers(for q: Question) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { idx, option in
                AnswerButton(
                    text: option,
                    state: answerState(idx: idx, q: q),
                    action: { game.submit(idx) }
                )
                // Stake mode: you must commit a confidence chip before answering.
                .disabled(game.phase != .playing || (game.mode == .stake && game.currentStake == 0))
            }
        }
    }

    // MARK: Stake selector

    private var stakeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(game.currentStake == 0 ? "How sure are you?" : "Staked: \(game.stakeLabel)")
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
            HStack(spacing: 10) {
                ForEach(game.stakeTiers) { tier in
                    StakeChip(tier: tier,
                              selected: game.currentStake == tier.value,
                              action: { game.setStake(tier.value) })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .chunkyCard(fill: Tidbits.Palette.bgDeep)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    // MARK: Sweep fill-grid

    /// The persistent "set" scoreboard — one cell per question. Filled green
    /// (hit) / coral (miss) as you go, the current cell outlined, the rest dim.
    /// The grid IS the progress indicator and the reward (Sporcle's 37/45).
    private var sweepGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 7), count: 6)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Set: \(game.score) / \(game.questions.count)")
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
            LazyVGrid(columns: cols, spacing: 7) {
                ForEach(0..<game.questions.count, id: \.self) { i in
                    let answered = i < game.answered.count
                    let hit = answered && game.answered[i].isCorrect
                    let current = i == game.index
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(answered ? (hit ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                                       : Tidbits.Palette.surface)
                        .frame(height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Tidbits.Palette.border,
                                          lineWidth: current ? 2.5 : 1.5))
                        .opacity(answered || current ? 1 : 0.45)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .chunkyCard(fill: Tidbits.Palette.bgDeep)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private func answerState(idx: Int, q: Question) -> AnswerButton.State {
        guard game.phase == .reveal else { return .idle }
        if idx == q.correctIndex { return .correct }
        if idx == game.chosenIndex { return .wrong }
        return .dimmed
    }

    // MARK: Reveal / learn

    private func reveal(for q: Question) -> some View {
        let correct = game.lastAnswer?.isCorrect ?? false
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: correct ? "checkmark.seal.fill" : "lightbulb.fill")
                    .foregroundStyle(correct ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                Text(correct ? "Nice — you knew it." : "Now you know.")
                    .font(Tidbits.TypeRamp.l3)
                    .foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                if game.mode == .stake {
                    Text(correct ? "+\(game.currentStake)" : "+0")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(correct ? Tidbits.Palette.mint.legibleForeground : Tidbits.Palette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(correct ? Tidbits.Palette.mint : Tidbits.Palette.surface))
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                }
            }
            if !q.explanation.isEmpty {
                Text(q.explanation)
                    .font(Tidbits.TypeRamp.l4)
                    .foregroundStyle(Tidbits.Palette.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = q.sourceURL {
                Link(destination: url) {
                    Label("Read \(q.sourceTitle) on Wikipedia", systemImage: "arrow.up.right.square")
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .chunkyCard(fill: Tidbits.Palette.bgDeep)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var nextBar: some View {
        Button(action: { game.advance() }) {
            Text(isLast ? "See Results" : "Next")
        }
        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.ink, textColor: .white))
        .padding(.horizontal, Tidbits.Metric.pad)
        .padding(.bottom, 16)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var isLast: Bool {
        (game.mode == .classic || game.mode == .daily || game.mode == .stake || game.mode == .sweep) && game.index + 1 >= game.questions.count
    }
}

/// One confidence-chip button in Stake mode. Shows the tier label, its point
/// value, and how many remain; disabled at zero (unless already selected).
private struct StakeChip: View {
    let tier: StakeTier
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let usable = tier.remaining > 0 || selected
        Button(action: action) {
            VStack(spacing: 2) {
                Text(tier.label).font(.system(size: 15, weight: .black, design: .rounded))
                Text("+\(tier.value) · \(tier.remaining) left").font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(selected ? Tidbits.Palette.mint.legibleForeground : Tidbits.Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Tidbits.Palette.mint : Tidbits.Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            .opacity(usable ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!usable)
    }
}
#endif
