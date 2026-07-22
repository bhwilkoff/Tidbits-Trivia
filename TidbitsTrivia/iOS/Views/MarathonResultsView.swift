#if os(iOS)
import SwiftUI
import SwiftData

/// The Marathon scorecard — a completed 200-question run's payoff
/// (docs/CLUB-FEATURES-BUILD.md "Feature 3"). Unlike `ResultsView` (which
/// reads the current session's `GameSummary`), this reads the permanent
/// `MarathonScore` just written, because a run's true total spans however
/// many sessions it took to finish, not just this last one.
struct MarathonResultsView: View {
    let score: MarathonScore
    var onPlayAgain: (() -> Void)? = nil
    let onDone: () -> Void
    /// True when opened from the history list (a past run, read-only) rather
    /// than right after finishing — hides the replay + history-link actions.
    var isHistorical: Bool = false

    @Query(sort: \MarathonScore.date, order: .reverse) private var allScores: [MarathonScore]
    @State private var showHistory = false

    /// The run before this one (excludes the one just written) — "vs your
    /// last run," per the design spec's literal phrasing.
    private var previous: MarathonScore? {
        allScores.first { $0.date < score.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                scoreCard
                comparisonMoment
                statsRow
                domainCard
                if !isHistorical {
                    Button { showHistory = true } label: {
                        Label("See Marathon history", systemImage: "clock.arrow.circlepath")
                            .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.blue)
                    }
                }
                buttons
            }
            .padding(.horizontal, Tidbits.Metric.pad)
            .padding(.vertical, 24)
        }
        .background(Tidbits.Palette.bg.ignoresSafeArea())
        .sheet(isPresented: $showHistory) { MarathonHistoryView() }
    }

    private var scoreCard: some View {
        VStack(spacing: 8) {
            Text("MARATHON COMPLETE")
                .font(Tidbits.TypeRamp.l2)
                .foregroundStyle(Tidbits.Palette.ink)
            Text("\(score.score)")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
            Text("\(score.correct)/\(score.total) correct · \(Self.durationLabel(score.durationSeconds))")
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .chunkyCard(fill: Tidbits.Palette.teal.opacity(0.18))
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    /// "+6% vs your last run" — the measured-mastery payoff (the whole reason
    /// Marathon isn't just a long Classic).
    @ViewBuilder private var comparisonMoment: some View {
        if let previous {
            let delta = Int((score.accuracy - previous.accuracy) * 100)
            VStack(spacing: 4) {
                Text(delta == 0 ? "Same as your last run" : "\(delta > 0 ? "+" : "")\(delta)% vs your last run")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(delta >= 0 ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                Text("Last run: \(Int(previous.accuracy * 100))% · this run: \(Int(score.accuracy * 100))%")
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .chunkyCard(fill: Tidbits.Palette.surface)
            .padding(.trailing, Tidbits.Metric.shadowOffset)
        } else {
            VStack(spacing: 4) {
                Text("Your first Marathon")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
                Text("Play another to see how you're improving")
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .chunkyCard(fill: Tidbits.Palette.surface)
            .padding(.trailing, Tidbits.Metric.shadowOffset)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatBox(value: "\(Int(score.accuracy * 100))%", label: "Accuracy", tint: Tidbits.Palette.blue)
            StatBox(value: "\(score.score)", label: "Score", tint: Tidbits.Palette.teal)
            StatBox(value: "\(allScores.count)", label: "Marathons", tint: Tidbits.Palette.coral)
        }
    }

    /// Per-domain accuracy bars — the measured-mastery map (not just a score).
    private var domainCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where you stood this run")
                .font(Tidbits.TypeRamp.l2)
                .foregroundStyle(Tidbits.Palette.ink)
            ForEach(score.domainBreakdown.filter { $0.total > 0 }) { stat in
                domainRow(stat)
            }
        }
        .padding(16)
        .chunkyCard()
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private func domainRow(_ stat: MarathonDomainStat) -> some View {
        let cat = TriviaCategory.named(stat.categoryID)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: cat.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(cat.color.legibleAccent)
                Text(cat.name).font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Text("\(stat.correct)/\(stat.total) · \(Int(stat.accuracy * 100))%")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tidbits.Palette.bgDeep)
                    Capsule().fill(cat.color).frame(width: max(6, geo.size.width * stat.accuracy))
                }
                .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
            }
            .frame(height: 10)
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            if let onPlayAgain {
                Button("Start a new Marathon", action: onPlayAgain)
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.teal, textColor: .white))
            }
            Button("Done", action: onDone)
                .font(Tidbits.TypeRamp.l3)
                .foregroundStyle(Tidbits.Palette.inkSoft)
                .padding(.top, 2)
        }
        .padding(.trailing, Tidbits.Metric.shadowOffset)
        .padding(.top, 4)
    }

    private static func durationLabel(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(1, minutes)) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours)h" : "\(hours)h \(rem)m"
    }
}

// MARK: - Marathon history (permanent record of every completed run)

struct MarathonHistoryView: View {
    @Query(sort: \MarathonScore.date, order: .reverse) private var scores: [MarathonScore]
    @Environment(\.dismiss) private var dismiss
    @State private var detail: MarathonScore?

    var body: some View {
        NavigationStack {
            Group {
                if scores.isEmpty {
                    ContentUnavailableView {
                        Label("No Marathons yet", systemImage: "flag.checkered")
                    } description: {
                        Text("A 200-question test of everything. Play it across as many sittings as you like — we'll keep your place.")
                    }
                    .padding(.top, 60)
                } else {
                    List(scores) { s in
                        Button { detail = s } label: {
                            row(s)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationTitle("Marathon History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: $detail) { s in
                MarathonResultsView(score: s, onDone: { detail = nil }, isHistorical: true)
            }
        }
    }

    private func row(_ s: MarathonScore) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(s.correct)/\(s.total) correct · \(Int(s.accuracy * 100))%")
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Text(s.date.formatted(date: .abbreviated, time: .omitted))
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Spacer()
            Text("\(s.score)")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.teal)
        }
        .padding(.vertical, 4)
    }
}
#endif
