#if os(iOS)
import SwiftUI
import SwiftData

/// "Compete against your past self." Personal bests, lifetime accuracy, the Daily
/// streak, per-domain progress, and — the interactive layer (owner request) — a
/// scrollable game history you can open, plus drill-ins from each domain and each
/// personal best into the actual questions you got right or wrong.
struct RecordsView: View {
    @Query(sort: \GameRecord.date, order: .reverse) private var records: [GameRecord]
    @Query private var streaks: [DailyStreak]
    @Query(filter: #Predicate<MissedFact> { !$0.resolved }, sort: \MissedFact.missCount, order: .reverse)
    private var toReview: [MissedFact]
    @Query(sort: \CalibrationTally.tierValue, order: .reverse) private var calibration: [CalibrationTally]
    @Query(sort: \SeenStory.lastSeen, order: .reverse) private var seenStories: [SeenStory]
    @Query(sort: \MarathonScore.date, order: .reverse) private var marathonScores: [MarathonScore]
    @Environment(PlayerIdentityStore.self) private var identity
    @Environment(EntitlementStore.self) private var entitlement
    @Environment(\.modelContext) private var modelContext

    @State private var recap: GameRecord?
    @State private var drillDomain: String?
    @State private var bestsMode: GameMode?
    @State private var showAllGames = false
    @State private var showStoryArchive = false
    @State private var showMarathonHistory = false
    @State private var showClubPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if records.isEmpty {
                    emptyState
                } else {
                    streakCard
                    lifetimeRow
                    historySection
                    storyArchiveSection
                    marathonHistorySection
                    progressSection
                    badgesSection
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
        .sheet(item: $recap) { GameRecapSheet(record: $0) }
        .sheet(item: Binding(get: { drillDomain.map(DomainID.init) }, set: { drillDomain = $0?.id })) { d in
            DomainDrillSheet(categoryID: d.id, records: records)
        }
        .sheet(item: Binding(get: { bestsMode.map(ModeID.init) }, set: { bestsMode = $0?.mode })) { m in
            BestAttemptsSheet(mode: m.mode, records: records.filter { $0.mode == m.mode }) { recap = $0 }
        }
        .sheet(isPresented: $showAllGames) {
            AllGamesSheet(records: records) { recap = $0 }
        }
        .sheet(isPresented: $showStoryArchive) { StoryArchiveView() }
        .sheet(isPresented: $showMarathonHistory) { MarathonHistoryView() }
        .sheet(isPresented: $showClubPaywall) { ClubPaywallView() }
        .task {
            if DebugHooks.openStoryArchive { openStoryArchive() }
        }
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
                Text("DAY STREAK").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink.opacity(0.7))
                Text("\(identity.profile?.streak.current ?? 0) days")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("BEST").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink.opacity(0.7))
                Text("\(identity.profile?.streak.longest ?? 0)").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
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

    // MARK: Game history (owner: scroll your previous games, Threes-style)

    // iOS-DESIGN §5.4: a bounded preview (the 3 most recent) + a "See all"
    // drill-in, so Records reads as a dashboard, not a 40-card ledger.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your games").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("Your latest rounds — tap one to see the questions.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(records.prefix(3)) { rec in
                Button { recap = rec } label: { GameHistoryRow(record: rec) }
                    .buttonStyle(.plain)
            }
            if records.count > 3 {
                Button { showAllGames = true } label: { seeAllRow("See all \(records.count) games") }
                    .buttonStyle(.plain)
            }
        }
    }

    private func seeAllRow(_ title: String) -> some View {
        HStack {
            Text(title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                .foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .padding(14)
        .chunkyCard(fill: Tidbits.Palette.bgDeep)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    // MARK: Story Archive (Club — docs/CLUB-FEATURES-BUILD.md "Feature 2")

    // A single Club-marked "see all" entry into the searchable story library
    // (R-REC-1: the dashboard stays a row, not the archive itself).
    private var storyArchiveSection: some View {
        Button(action: openStoryArchive) {
            HStack(spacing: 14) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Tidbits.Palette.teal.legibleForeground)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("STORY ARCHIVE")
                            .font(Tidbits.TypeRamp.l2)
                            .foregroundStyle(Tidbits.Palette.teal.legibleForeground)
                        if !entitlement.isClub {
                            Text("CLUB")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(Tidbits.Palette.teal)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.92)))
                        }
                    }
                    Text(storyArchiveSubtitle)
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.teal.legibleForeground.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Tidbits.Palette.teal.legibleForeground)
            }
            .padding(18)
            .chunkyCard(fill: Tidbits.Palette.teal)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var storyArchiveSubtitle: String {
        if entitlement.isClub {
            return seenStories.isEmpty
                ? "Every story you unlock, kept here forever."
                : "\(seenStories.count) stor\(seenStories.count == 1 ? "y" : "ies") collected — searchable, forever."
        }
        return StoryArchive.previewLine(in: modelContext)
            ?? "Club keeps every story you unlock, searchable forever."
    }

    /// Members open the archive directly; everyone else sees the existing
    /// paywall with a real preview — never a blank wall.
    private func openStoryArchive() {
        if entitlement.isClub { showStoryArchive = true } else { showClubPaywall = true }
    }

    // MARK: Marathon History (Club — docs/CLUB-FEATURES-BUILD.md "Feature 3")

    // The permanent record of every completed 200-Q run — reachable from
    // Records (in addition to the Home card's own "See Marathon history" link).
    private var marathonHistorySection: some View {
        Button(action: openMarathonHistory) {
            HStack(spacing: 14) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Tidbits.Palette.teal.legibleForeground)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("MARATHON HISTORY")
                            .font(Tidbits.TypeRamp.l2)
                            .foregroundStyle(Tidbits.Palette.teal.legibleForeground)
                        if !entitlement.isClub {
                            Text("CLUB")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(Tidbits.Palette.teal)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.92)))
                        }
                    }
                    Text(marathonHistorySubtitle)
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.teal.legibleForeground.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Tidbits.Palette.teal.legibleForeground)
            }
            .padding(18)
            .chunkyCard(fill: Tidbits.Palette.teal)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var marathonHistorySubtitle: String {
        if entitlement.isClub {
            return marathonScores.isEmpty
                ? "200 questions. Play it across as many sittings as you like — we'll keep your place."
                : "\(marathonScores.count) run\(marathonScores.count == 1 ? "" : "s") played — best \(Int((marathonScores.map(\.accuracy).max() ?? 0) * 100))%."
        }
        return "See exactly where you stand across a 200-question run, by domain — Club keeps every run forever."
    }

    /// Members open the history list directly; everyone else sees the
    /// existing paywall — never a blank wall.
    private func openMarathonHistory() {
        if entitlement.isClub { showMarathonHistory = true } else { showClubPaywall = true }
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

    // MARK: Progress — per-domain levels, now tappable to drill in

    private var domains: [DomainProgress] {
        DomainProgress.summarize(records.map { ($0.categoryID, $0.correct, $0.total) })
    }

    private var progressSection: some View {
        let ds = domains.filter { $0.total > 0 }
        let mastered = ds.filter { $0.hasWedge }.count
        return VStack(alignment: .leading, spacing: 12) {
            Text("Your knowledge").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("Each domain levels up as you answer its questions correctly. You've explored \(ds.count) of 7 domains and mastered \(mastered). Tap a domain to see the questions you've faced.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ds) { d in
                Button { drillDomain = d.categoryID } label: { topicRow(d) }
                    .buttonStyle(.plain)
            }
        }
    }

    // L4: levelable badges — tiered milestones from BadgeMath (shared Core), hidden until one is earned.
    private var badgesSection: some View {
        let lifetime = records.reduce(into: (correct: 0, total: 0)) { $0.correct += $1.correct; $0.total += $1.total }
        let acc = lifetime.total > 0 ? Int(Double(lifetime.correct) / Double(lifetime.total) * 100) : 0
        let mastered = domains.filter { $0.hasWedge }.count
        let badges = BadgeMath.badges(games: records.count,
                                      longestStreak: identity.profile?.streak.longest ?? 0,
                                      mastered: mastered, lifetimeAccuracy: acc,
                                      liveNights: identity.profile?.stats.liveNights ?? 0)
        return Group {
            if badges.contains(where: { $0.tier > 0 }) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Badges").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                    Text("Milestones that level up as you play — depth, consistency, and range.")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    ForEach(badges) { badgeRow($0) }
                }
            }
        }
    }

    private func badgeRow(_ b: LevelableBadge) -> some View {
        HStack(spacing: 12) {
            Text(b.tier > 0 ? "\(b.tier)" : "·").font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white).frame(width: 36, height: 36)
                .background(Circle().fill(b.tier > 0 ? Tidbits.Palette.coral : Tidbits.Palette.inkSoft))
                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(b.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Spacer()
                    Text("Tier \(b.tier)/\(b.maxTier)").font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white).padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(Tidbits.Palette.blue))
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tidbits.Palette.bgDeep)
                        Capsule().fill(Tidbits.Palette.coral).frame(width: max(6, geo.size.width * b.progress))
                    }
                    .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                }
                .frame(height: 12)
                Text(b.detail).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
        }
        .padding(12)
        .chunkyCard()
        .padding(.trailing, Tidbits.Metric.shadowOffset)
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
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Tidbits.Palette.inkSoft)
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
            Text("Tap a mode to scroll your previous attempts.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(GameMode.allCases) { mode in
                let attempts = records.filter { $0.mode == mode }
                if let best = attempts.map(\.score).max() {
                    Button { bestsMode = mode } label: {
                        HStack {
                            Image(systemName: mode.symbol).foregroundStyle(mode.accent.legibleForeground)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(mode.accent))
                                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mode.title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                                Text("\(attempts.count) played").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                            }
                            Spacer()
                            Text("\(best)").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Tidbits.Palette.inkSoft)
                        }
                        .padding(14)
                        .chunkyCard()
                        .padding(.trailing, Tidbits.Metric.shadowOffset)
                    }
                    .buttonStyle(.plain)
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

// MARK: - Identifiable wrappers for sheet(item:)

private struct DomainID: Identifiable { let id: String; init(_ id: String) { self.id = id } }
private struct ModeID: Identifiable { let mode: GameMode; var id: String { mode.rawValue }; init(_ m: GameMode) { mode = m } }

// MARK: - History row + the category-colored answer strip

/// One past game as a compact card: mode · category · score · when, plus a
/// per-question strip (owner: "scroll through your previous games… end states").
struct GameHistoryRow: View {
    let record: GameRecord
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.mode.symbol).foregroundStyle(record.mode.accent.legibleForeground)
                .frame(width: 36, height: 36)
                .background(Circle().fill(record.mode.accent))
                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.mode.title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Text("· \(TriviaCategory.named(record.categoryID).name)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    Spacer()
                    Text("\(record.score)").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                }
                AnswerStrip(answers: record.answers, fallback: (record.correct, record.total))
                Text("\(record.correct)/\(record.total) correct · \(record.date.formatted(.relative(presentation: .named)))")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
        }
        .padding(12)
        .chunkyCard()
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }
}

/// The run's shape: one pip per question, filled in the domain's color when
/// correct, hollow when missed — richer than uniform red/green (it also shows
/// which domains you were strong in). Falls back to a correct/total bar for old
/// records with no per-question detail.
struct AnswerStrip: View {
    let answers: [AnswerDetail]
    let fallback: (correct: Int, total: Int)
    var body: some View {
        if answers.isEmpty {
            let (c, t) = fallback
            HStack(spacing: 3) {
                ForEach(0..<max(t, 1), id: \.self) { i in
                    Circle().fill(i < c ? Tidbits.Palette.mint : Tidbits.Palette.surface)
                        .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                }
            }
        } else {
            HStack(spacing: 3) {
                ForEach(answers.prefix(24)) { a in
                    let c = TriviaCategory.named(a.categoryID).color
                    Circle().fill(a.correct ? c : Tidbits.Palette.surface)
                        .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                }
            }
        }
    }
}

// MARK: - Per-game recap sheet

struct GameRecapSheet: View {
    let record: GameRecord
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        StatBox(value: "\(record.score)", label: "Score", tint: record.mode.accent)
                        StatBox(value: "\(record.correct)/\(record.total)", label: "Correct", tint: Tidbits.Palette.mint)
                        StatBox(value: "\(Int(record.accuracy * 100))%", label: "Accuracy", tint: Tidbits.Palette.blue)
                    }
                    if record.answers.isEmpty {
                        Text("This game was played before per-question history was added, so only the totals are here.")
                            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                    ForEach(record.answers) { a in AnswerRow(answer: a) }
                }
                .padding(Tidbits.Metric.pad)
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationTitle("\(record.mode.title) · \(record.score)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

/// One question line in a recap / drill-in: the prompt, its answer, and a
/// right/wrong seal.
struct AnswerRow: View {
    let answer: AnswerDetail
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: answer.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(answer.correct ? Tidbits.Palette.mint : Tidbits.Palette.coral)
            VStack(alignment: .leading, spacing: 3) {
                Text(answer.prompt).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Answer: \(answer.answer)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .chunkyCard(fill: Tidbits.Palette.surface)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }
}

// MARK: - Domain drill-in

struct DomainDrillSheet: View {
    let categoryID: String
    let records: [GameRecord]
    @Environment(\.dismiss) private var dismiss

    private var answers: [AnswerDetail] {
        // Latest outcome per question in this domain, newest game first.
        var seen = Set<String>()
        var out: [AnswerDetail] = []
        for rec in records {
            for a in rec.answers where a.categoryID == categoryID && !seen.contains(a.qid) {
                seen.insert(a.qid); out.append(a)
            }
        }
        return out
    }

    var body: some View {
        let cat = TriviaCategory.named(categoryID)
        let right = answers.filter(\.correct), wrong = answers.filter { !$0.correct }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if answers.isEmpty {
                        Text("No per-question history yet for \(cat.name). Play a game in this domain and it'll show up here.")
                            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                    if !wrong.isEmpty {
                        Text("Missed (\(wrong.count))").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                        ForEach(wrong) { AnswerRow(answer: $0) }
                    }
                    if !right.isEmpty {
                        Text("Got right (\(right.count))").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                        ForEach(right) { AnswerRow(answer: $0) }
                    }
                }
                .padding(Tidbits.Metric.pad)
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationTitle(cat.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Full game history (the "See all" drill-in, iOS-DESIGN §5.4)

/// The long tail of games lives here, behind the 3-game preview on Records.
/// Tapping a game hands off to the recap sheet (dismiss-then-open, the same
/// two-sheet pattern BestAttemptsSheet uses).
struct AllGamesSheet: View {
    let records: [GameRecord]
    let onOpen: (GameRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(records) { rec in
                        Button { dismiss(); onOpen(rec) } label: { GameHistoryRow(record: rec) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(Tidbits.Metric.pad)
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationTitle("All games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Best-attempts drill-in

struct BestAttemptsSheet: View {
    let mode: GameMode
    let records: [GameRecord]
    let onOpen: (GameRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let best = records.map(\.score).max() ?? 0
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Every \(mode.title) game, newest first. Your best is \(best).")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    ForEach(records) { rec in
                        Button { dismiss(); onOpen(rec) } label: {
                            HStack(spacing: 12) {
                                if rec.score == best {
                                    Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rec.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                                    AnswerStrip(answers: rec.answers, fallback: (rec.correct, rec.total))
                                }
                                Spacer()
                                Text("\(rec.score)").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Tidbits.Palette.inkSoft)
                            }
                            .padding(14)
                            .chunkyCard()
                            .padding(.trailing, Tidbits.Metric.shadowOffset)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Tidbits.Metric.pad)
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationTitle("\(mode.title) attempts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
#endif
