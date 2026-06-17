#if os(iOS)
import SwiftUI
import SwiftData

/// "Compete against your past self." Personal bests per mode, lifetime
/// accuracy, the Daily streak, and a spaced-review list of facts the
/// player has missed — the learning loop made visible.
struct RecordsView: View {
    @Query(sort: \GameRecord.date, order: .reverse) private var records: [GameRecord]
    @Query private var streaks: [DailyStreak]
    @Query(filter: #Predicate<MissedFact> { !$0.resolved }, sort: \MissedFact.missCount, order: .reverse)
    private var toReview: [MissedFact]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if records.isEmpty {
                    emptyState
                } else {
                    streakCard
                    lifetimeRow
                    bestsSection
                    if !toReview.isEmpty { reviewSection }
                }
            }
            .padding(.horizontal, Tidbits.Metric.pad)
            .padding(.vertical, 18)
        }
        .background(Tidbits.Palette.bg.ignoresSafeArea())
        .navigationTitle("Records")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No games yet", systemImage: "chart.bar.doc.horizontal")
        } description: {
            Text("Play a round and your scores, streaks, and facts to review will show up here.")
        }
        .padding(.top, 60)
    }

    private var streak: DailyStreak? { streaks.first }

    private var streakCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DAILY STREAK").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink.opacity(0.7))
                Text("\(streak?.current ?? 0) days")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("BEST").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink.opacity(0.7))
                Text("\(streak?.best ?? 0)").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            }
            Image(systemName: "flame.fill").font(.system(size: 32, weight: .black)).foregroundStyle(Tidbits.Palette.coral)
        }
        .padding(18)
        .chunkyCard(fill: Tidbits.Palette.yellow)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var lifetimeRow: some View {
        let totalCorrect = records.reduce(0) { $0 + $1.correct }
        let totalQs = records.reduce(0) { $0 + $1.total }
        let pct = totalQs == 0 ? 0 : Int(Double(totalCorrect) / Double(totalQs) * 100)
        return HStack(spacing: 12) {
            StatBox(value: "\(records.count)", label: "Games", tint: Tidbits.Palette.grape)
            StatBox(value: "\(pct)%", label: "Lifetime Acc.", tint: Tidbits.Palette.blue)
            StatBox(value: "\(totalCorrect)", label: "Right", tint: Tidbits.Palette.mint)
        }
    }

    private var bestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal bests").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            ForEach(GameMode.allCases) { mode in
                let best = records.filter { $0.mode == mode }.map(\.score).max()
                if let best {
                    HStack {
                        Image(systemName: mode.symbol).foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(mode.accent))
                            .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                        Text(mode.title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Spacer()
                        Text("\(best)").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                    }
                    .padding(14)
                    .chunkyCard()
                    .padding(.trailing, Tidbits.Metric.shadowOffset)
                }
            }
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Facts to review", systemImage: "arrow.triangle.2.circlepath")
                .font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("Questions you missed. We'll quietly slip these back into future games.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(toReview.prefix(8), id: \.questionID) { fact in
                VStack(alignment: .leading, spacing: 4) {
                    Text(fact.prompt).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Text("Answer: \(fact.correctAnswer)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.mint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .chunkyCard(fill: Tidbits.Palette.bgDeep)
                .padding(.trailing, Tidbits.Metric.shadowOffset)
            }
        }
    }
}
#endif
