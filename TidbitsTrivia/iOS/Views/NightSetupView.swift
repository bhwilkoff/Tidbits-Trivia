#if os(iOS)
import SwiftUI

/// Configure a Trivia Night before it starts — the "host picks the night" screen.
/// Start from a preset, then tune: which rounds (question types) are in play and
/// how many questions each, plus the category. Presets-first so the common path is
/// one tap (clarity over cleverness — the learning-orientation check); the per-round
/// controls are there when a host wants to curate. Returns the assembled `NightPlan`.
struct NightSetupView: View {
    let onStart: (NightPlan, TriviaCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var rounds: [NightRound] = NightPlan.pub.rounds
    @State private var category: TriviaCategory = .named("mixed")
    @State private var presetName: String = "Pub Night"

    private var plan: NightPlan { NightPlan(rounds: rounds.filter { $0.count > 0 }) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    intro
                    presetSection
                    roundsSection
                    categorySection
                }
                .padding(.horizontal, Tidbits.Metric.pad)
                .padding(.bottom, 120)
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationTitle("Trivia Night")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { startBar }
        }
    }

    private var intro: some View {
        Text("A night of mixed rounds — every kind of question, one game. Every answer ends on a fact to learn.")
            .font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }

    // MARK: Presets

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start from").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            ForEach(NightPlan.presets, id: \.name) { preset in
                Button {
                    rounds = preset.plan.rounds
                    presetName = preset.name
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                            Text(preset.blurb).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        }
                        Spacer()
                        Image(systemName: presetName == preset.name ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(presetName == preset.name ? Tidbits.Palette.coral : Tidbits.Palette.inkSoft)
                    }
                    .padding(14)
                    .chunkyCard(fill: presetName == preset.name ? Tidbits.Palette.coral.opacity(0.16) : Tidbits.Palette.surface)
                    .padding(.trailing, Tidbits.Metric.shadowOffset)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Rounds (add/remove types, tune counts)

    private var roundsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Rounds").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Text("\(plan.totalQuestions) questions").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            ForEach(NightPlan.allKinds, id: \.self) { kind in
                roundRow(kind)
            }
        }
    }

    private func roundRow(_ kind: GameMode) -> some View {
        let count = rounds.first(where: { $0.kind == kind })?.count ?? 0
        let on = count > 0
        return HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(on ? kind.accent.legibleForeground : Tidbits.Palette.inkSoft)
                .frame(width: 38, height: 38)
                .background(Circle().fill(on ? kind.accent : Tidbits.Palette.surface))
                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.nightRoundTitle).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Text(kind.blurb).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).lineLimit(1)
            }
            Spacer()
            Stepper(value: Binding(
                get: { count },
                set: { setCount($0, for: kind) }), in: 0...10) {
                Text(on ? "\(count)" : "—")
                    .font(.system(size: 17, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(on ? Tidbits.Palette.ink : Tidbits.Palette.inkSoft)
                    .frame(width: 28)
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(12)
        .chunkyCard(fill: Tidbits.Palette.surface)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private func setCount(_ newCount: Int, for kind: GameMode) {
        presetName = ""   // a manual edit means we're off-preset
        if let i = rounds.firstIndex(where: { $0.kind == kind }) {
            if newCount <= 0 { rounds.remove(at: i) }
            else { rounds[i].count = newCount }
        } else if newCount > 0 {
            // Insert in the canonical running order.
            let order = NightPlan.allKinds
            let newRound = NightRound(kind: kind, count: newCount)
            let insertAt = rounds.firstIndex { (order.firstIndex(of: $0.kind) ?? 0) > (order.firstIndex(of: kind) ?? 0) } ?? rounds.count
            rounds.insert(newRound, at: insertAt)
        }
    }

    // MARK: Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Category").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TriviaCategory.all) { cat in
                        Button { category = cat } label: {
                            HStack(spacing: 8) {
                                Image(systemName: cat.symbol).font(.system(size: 14, weight: .bold))
                                Text(cat.name).font(Tidbits.TypeRamp.l3)
                            }
                            .foregroundStyle(category.id == cat.id ? cat.color.legibleForeground : Tidbits.Palette.ink)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Capsule().fill(category.id == cat.id ? cat.color : Tidbits.Palette.surface))
                            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var startBar: some View {
        Button {
            let p = plan
            guard !p.rounds.isEmpty else { return }
            dismiss()
            onStart(p, category)
        } label: {
            Text(plan.rounds.isEmpty ? "Add a round to start" : "Start the Night · \(plan.totalQuestions) Qs")
        }
        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: Tidbits.Palette.coral.legibleForeground))
        .disabled(plan.rounds.isEmpty)
        .padding(.horizontal, Tidbits.Metric.pad)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
#endif
