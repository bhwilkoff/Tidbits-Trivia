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
    @Query(sort: \CalibrationTally.tierValue, order: .reverse) private var calibration: [CalibrationTally]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if records.isEmpty {
                    emptyState
                } else {
                    streakCard
                    lifetimeRow
                    progressSection
                    if calibration.contains(where: { $0.total > 0 }) { calibrationSection }
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
            StatBox(value: "\(pct)%", label: "Accuracy", tint: Tidbits.Palette.blue)
            StatBox(value: "\(totalCorrect)", label: "Correct", tint: Tidbits.Palette.mint)
        }
    }

    // MARK: Calibration (F1) — from Stake rounds

    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your calibration").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("From Stake rounds: how often each confidence level actually landed. Well-calibrated means your hit-rate climbs with your confidence.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(calibration.filter { $0.total > 0 }, id: \.tierValue) { tally in
                let pct = Int((Double(tally.hits) / Double(tally.total) * 100).rounded())
                HStack(spacing: 12) {
                    Text(tierLabel(tally.tierValue)).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        .frame(width: 70, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Tidbits.Palette.surface)
                            Capsule().fill(Tidbits.Palette.mint).frame(width: max(6, geo.size.width * Double(tally.hits) / Double(tally.total)))
                        }
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                    }
                    .frame(height: 16)
                    Text("\(tally.hits)/\(tally.total) · \(pct)%")
                        .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(Tidbits.Palette.ink)
                        .frame(width: 92, alignment: .trailing)
                }
                .padding(12)
                .chunkyCard()
                .padding(.trailing, Tidbits.Metric.shadowOffset)
            }
        }
    }

    private func tierLabel(_ value: Int) -> String {
        GameMode.stakeBudget.first { $0.value == value }?.label ?? "+\(value)"
    }

    // MARK: Progress — The Pie (breadth) + Topic Levels (depth)

    private var domains: [DomainProgress] {
        DomainProgress.summarize(records.map { ($0.categoryID, $0.correct, $0.total) })
    }

    private var progressSection: some View {
        let ds = domains.filter { $0.total > 0 }
        let mastered = ds.filter { $0.hasWedge }.count
        return VStack(alignment: .leading, spacing: 12) {
            Text("Your knowledge").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("Each domain levels up as you answer its questions correctly. You've explored \(ds.count) of 7 domains and mastered \(mastered). A ✓ means mastered — 15+ right at 60%+ accuracy.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ds) { d in topicRow(d) }
        }
    }

    private func topicRow(_ d: DomainProgress) -> some View {
        let cat = TriviaCategory.named(d.categoryID)
        let remaining = max(0, d.nextLevelCorrect - d.correct)
        return HStack(spacing: 12) {
            Image(systemName: cat.symbol).foregroundStyle(cat.color.legibleForeground)
                .frame(width: 36, height: 36)
                .background(Circle().fill(cat.color))
                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(cat.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    if d.hasWedge {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Tidbits.Palette.mint)
                    }
                    Spacer()
                    Text("Level \(d.level)").font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(cat.color.legibleForeground)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(cat.color))
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tidbits.Palette.bgDeep)
                        Capsule().fill(cat.color).frame(width: max(6, geo.size.width * d.levelProgress))
                    }
                    .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                }
                .frame(height: 12)
                Text("\(d.correct) correct · \(remaining) more to Level \(d.level + 1)")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
        }
        .padding(12)
        .chunkyCard()
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var bestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal bests").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            ForEach(GameMode.allCases) { mode in
                let best = records.filter { $0.mode == mode }.map(\.score).max()
                if let best {
                    HStack {
                        Image(systemName: mode.symbol).foregroundStyle(mode.accent.legibleForeground)
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
                    Text("Answer: \(fact.correctAnswer)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
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
