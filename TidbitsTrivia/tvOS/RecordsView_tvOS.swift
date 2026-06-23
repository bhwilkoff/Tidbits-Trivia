#if os(tvOS)
import SwiftUI
import SwiftData

/// "Compete against your past self" at ten feet. Personal bests per mode,
/// lifetime accuracy, the Daily streak, The Pie (breadth) + Topic Levels
/// (depth), Stake calibration, and the spaced-review list — the same derived
/// knowledge cartography iOS shows (shared `ProgressMath` / SwiftData models),
/// presented dark-first and focus-driven. Every card is focusable so the Siri
/// Remote can arrow down through the whole page (tvOS scrolling is focus-driven;
/// without focusable targets a ScrollView never reveals lower content).
struct RecordsView_tvOS: View {
    @Query(sort: \GameRecord.date, order: .reverse) private var records: [GameRecord]
    @Query private var streaks: [DailyStreak]
    @Query(filter: #Predicate<MissedFact> { !$0.resolved }, sort: \MissedFact.missCount, order: .reverse)
    private var toReview: [MissedFact]
    @Query(sort: \CalibrationTally.tierValue, order: .reverse) private var calibration: [CalibrationTally]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    Text("RECORDS")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(TVTheme.text)
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
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onExitCommand { dismiss() }   // Menu button leaves Records (modal: allowed)
    }

    private var emptyState: some View {
        TVRecordsCard(fill: TVTheme.panel) {
            VStack(alignment: .leading, spacing: 12) {
                Text("No games yet")
                    .font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text("Play a round and your scores, streaks, and the facts to review will show up here.")
                    .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 40)
    }

    // MARK: Streak

    private var streak: DailyStreak? { streaks.first }

    private var streakCard: some View {
        TVRecordsCard(fill: Tidbits.Palette.yellow, dark: false) {
            HStack(spacing: 28) {
                Image(systemName: "flame.fill").font(.system(size: 56, weight: .black)).foregroundStyle(Tidbits.Palette.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DAILY STREAK").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.black.opacity(0.7))
                    Text("\(streak?.current ?? 0) days").font(.system(size: 48, weight: .black, design: .rounded)).foregroundStyle(.black)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("BEST").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.black.opacity(0.7))
                    Text("\(streak?.best ?? 0)").font(.system(size: 48, weight: .black, design: .rounded)).foregroundStyle(.black)
                }
            }
        }
    }

    // MARK: Lifetime

    private var lifetimeRow: some View {
        let totalCorrect = records.reduce(0) { $0 + $1.correct }
        let totalQs = records.reduce(0) { $0 + $1.total }
        let pct = totalQs == 0 ? 0 : Int(Double(totalCorrect) / Double(totalQs) * 100)
        return HStack(spacing: 24) {
            tvStatBox("\(records.count)", "Games", Tidbits.Palette.grape)
            tvStatBox("\(pct)%", "Lifetime Acc.", Tidbits.Palette.blue)
            tvStatBox("\(totalCorrect)", "Right", Tidbits.Palette.mint)
        }
    }

    private func tvStatBox(_ v: String, _ l: String, _ tint: Color) -> some View {
        TVRecordsCard(fill: tint, dark: false) {
            VStack(alignment: .leading, spacing: 4) {
                Text(v).font(.system(size: 52, weight: .black, design: .rounded)).foregroundStyle(tint.legibleForeground)
                Text(l.uppercased()).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(tint.legibleForeground.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Calibration (F1) — from Stake rounds

    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your calibration").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.text)
            Text("From Stake rounds: how often each confidence level actually landed. Well-calibrated means your hit-rate climbs with your confidence.")
                .font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(calibration.filter { $0.total > 0 }, id: \.tierValue) { tally in
                let pct = Int((Double(tally.hits) / Double(tally.total) * 100).rounded())
                TVRecordsCard(fill: TVTheme.panel) {
                    HStack(spacing: 24) {
                        Text(tierLabel(tally.tierValue)).font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .frame(width: 150, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12))
                                Capsule().fill(Tidbits.Palette.mint).frame(width: max(10, geo.size.width * Double(tally.hits) / Double(tally.total)))
                            }
                        }
                        .frame(height: 24)
                        Text("\(tally.hits)/\(tally.total) · \(pct)%")
                            .font(.system(size: 27, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(.white)
                            .frame(width: 200, alignment: .trailing)
                    }
                }
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
        let ds = domains
        let earned = DomainProgress.wedgesEarned(ds)
        return VStack(alignment: .leading, spacing: 16) {
            Text("Your knowledge").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.text)
            TVRecordsCard(fill: TVTheme.panel) {
                HStack(spacing: 36) {
                    ZStack {
                        TVPieProgressView(domains: ds).frame(width: 150, height: 150)
                        VStack(spacing: -2) {
                            Text("\(earned)/7").font(.system(size: 36, weight: .black, design: .rounded)).foregroundStyle(.white)
                            Text("domains").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        }
                    }
                    Text(earned == 7
                         ? "Full pie — you've mastered every domain. That breadth is yours to keep."
                         : "Earn a wedge in each domain by answering its questions well. The pie fills only when you cover them all.")
                        .font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(ds.filter { $0.total > 0 }) { d in topicRow(d) }
        }
    }

    private func topicRow(_ d: DomainProgress) -> some View {
        let cat = TriviaCategory.named(d.categoryID)
        return TVRecordsCard(fill: TVTheme.panel) {
            HStack(spacing: 24) {
                Image(systemName: cat.symbol).font(.system(size: 32, weight: .black)).foregroundStyle(cat.color.legibleForeground)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(cat.color))
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(cat.name).font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        if d.hasWedge {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(Tidbits.Palette.mint)
                        }
                        Spacer()
                        Text("Lvl \(d.level)").font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(cat.color.legibleForeground)
                            .padding(.horizontal, 18).padding(.vertical, 6)
                            .background(Capsule().fill(cat.color))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(cat.color).frame(width: max(10, geo.size.width * d.levelProgress))
                        }
                    }
                    .frame(height: 18)
                }
            }
        }
    }

    // MARK: Personal bests

    private var bestsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personal bests").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.text)
            ForEach(GameMode.allCases) { mode in
                let best = records.filter { $0.mode == mode }.map(\.score).max()
                if let best {
                    TVRecordsCard(fill: TVTheme.panel) {
                        HStack(spacing: 24) {
                            Image(systemName: mode.symbol).font(.system(size: 30, weight: .black)).foregroundStyle(mode.accent.legibleForeground)
                                .frame(width: 64, height: 64)
                                .background(Circle().fill(mode.accent))
                            Text(mode.title).font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Spacer()
                            Text("\(best)").font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }

    // MARK: Facts to review

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Facts to review").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.text)
            Text("Questions you missed. We'll quietly slip these back into future games.")
                .font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            ForEach(toReview.prefix(8), id: \.questionID) { fact in
                TVRecordsCard(fill: TVTheme.panel) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(fact.prompt).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Answer: \(fact.correctAnswer)").font(.system(size: 25, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.mint)
                    }
                }
            }
        }
    }
}

// MARK: - Focusable display card (lets the focus engine scroll the page)

/// A non-interactive card that is nonetheless focusable, so the Siri Remote can
/// arrow down through a read-only page (tvOS scrolling is focus-driven). Reads
/// `\.isFocused` in a child to draw a focus ring — the same pattern as the
/// button styles and the results recap card.
struct TVRecordsCard<Content: View>: View {
    var fill: Color = TVTheme.panel
    /// `false` for bright-fill cards (streak/stats) where content is already
    /// dark — keeps the focus ring/brightening from washing it out.
    var dark: Bool = true
    @ViewBuilder var content: () -> Content
    var body: some View { TVRecordsCardInner(fill: fill, dark: dark, content: content).focusable() }
}

private struct TVRecordsCardInner<Content: View>: View {
    let fill: Color
    let dark: Bool
    @ViewBuilder var content: () -> Content
    @Environment(\.isFocused) private var focused
    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(dark ? (focused ? fill.opacity(1.0) : fill.opacity(0.72)) : fill))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 4))
            .scaleEffect(focused ? 1.012 : 1.0)
            .animation(.easeOut(duration: 0.16), value: focused)
    }
}

/// The Pie — seven equal wedges, one per knowledge domain. Earned wedges show
/// their category color; unearned are dim. (tvOS copy of the iOS Canvas pie.)
private struct TVPieProgressView: View {
    let domains: [DomainProgress]
    var body: some View {
        Canvas { ctx, size in
            let n = max(1, domains.count)
            let radius = min(size.width, size.height) / 2 - 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for (i, d) in domains.enumerated() {
                let start = Angle(degrees: Double(i) / Double(n) * 360 - 90)
                let end = Angle(degrees: Double(i + 1) / Double(n) * 360 - 90)
                var slice = Path()
                slice.move(to: center)
                slice.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                slice.closeSubpath()
                let fill = d.hasWedge ? TriviaCategory.named(d.categoryID).color : Color.white.opacity(0.10)
                ctx.fill(slice, with: .color(fill))
                ctx.stroke(slice, with: .color(.black.opacity(0.5)), lineWidth: 2)
            }
        }
    }
}
#endif
