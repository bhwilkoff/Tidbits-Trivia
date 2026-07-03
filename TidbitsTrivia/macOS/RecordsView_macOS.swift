#if os(macOS)
import SwiftUI
import SwiftData

/// Mac Records (macOS-DESIGN Part B). "Compete against your past self" — a
/// dashboard, not a ledger (R-REC-1): streak + lifetime + the 3 most recent
/// games (rest behind "See all") + per-domain knowledge + calibration + bests +
/// facts to review. Reuses the shared SwiftData models + ProgressStats
/// derivation verbatim; only the Mac-native presentation is new.
struct RecordsView_macOS: View {
    @Query(sort: \GameRecord.date, order: .reverse) private var records: [GameRecord]
    @Query private var streaks: [DailyStreak]
    @Query(filter: #Predicate<MissedFact> { !$0.resolved }, sort: \MissedFact.missCount, order: .reverse)
    private var toReview: [MissedFact]
    @Query(sort: \CalibrationTally.tierValue, order: .reverse) private var calibration: [CalibrationTally]

    @State private var recap: GameRecord?
    @State private var drillDomain: String?
    @State private var bestsMode: GameMode?
    @State private var showAllGames = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if records.isEmpty {
                    ContentUnavailableView("No games yet", systemImage: "chart.bar.doc.horizontal",
                        description: Text("Play a round and your scores, streaks, and facts to review show up here."))
                        .padding(.top, 60)
                } else {
                    streakCard
                    lifetimeRow
                    gamesSection
                    knowledgeSection
                    if calibration.contains(where: { $0.total > 0 }) { calibrationSection }
                    bestsSection
                    if !toReview.isEmpty { reviewSection }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Tidbits.Palette.bg)
        .navigationTitle("Records")
        .sheet(item: $recap) { RecapSheet_macOS(record: $0) }
        .sheet(item: Binding(get: { drillDomain.map(IDBox.init) }, set: { drillDomain = $0?.id })) { d in
            DomainSheet_macOS(categoryID: d.id, records: records)
        }
        .sheet(item: Binding(get: { bestsMode.map(ModeBox.init) }, set: { bestsMode = $0?.mode })) { m in
            BestsSheet_macOS(mode: m.mode, records: records.filter { $0.mode == m.mode }) { recap = $0 }
        }
        .sheet(isPresented: $showAllGames) {
            AllGamesSheet_macOS(records: records) { recap = $0 }
        }
    }

    private var streak: DailyStreak? { streaks.first }

    private var streakCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DAILY STREAK").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink.opacity(0.7))
                Text("\(streak?.current ?? 0) days").font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
            }
            Spacer()
            Text("best \(streak?.best ?? 0)").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
            Image(systemName: "flame.fill").font(.system(size: 28, weight: .black)).foregroundStyle(Tidbits.Palette.coral)
        }
        .padding(20)
        .chunkyCard(fill: Tidbits.Palette.yellow)
    }

    private var lifetimeRow: some View {
        let totalCorrect = records.reduce(0) { $0 + $1.correct }
        let totalQs = records.reduce(0) { $0 + $1.total }
        let pct = totalQs == 0 ? 0 : Int(Double(totalCorrect) / Double(totalQs) * 100)
        return HStack(spacing: 14) {
            statBox("\(records.count)", "Games", Tidbits.Palette.grape)
            statBox("\(pct)%", "Accuracy", Tidbits.Palette.blue)
            statBox("\(totalCorrect)", "Correct", Tidbits.Palette.mint)
        }
    }

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your games").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("Your latest rounds — click one to see the questions.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(records.prefix(3)) { rec in
                Button { recap = rec } label: { GameRow_macOS(record: rec) }.buttonStyle(.plain)
            }
            if records.count > 3 {
                Button { showAllGames = true } label: {
                    HStack {
                        Text("See all \(records.count) games").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                    .padding(14).chunkyCard(fill: Tidbits.Palette.bgDeep)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var domains: [DomainProgress] {
        DomainProgress.summarize(records.map { ($0.categoryID, $0.correct, $0.total) }).filter { $0.total > 0 }
    }

    private var knowledgeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your knowledge").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("Each domain levels up as you answer its questions correctly. Click a domain to see the questions you've faced.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
            ForEach(domains) { d in
                Button { drillDomain = d.categoryID } label: { topicRow(d) }.buttonStyle(.plain)
            }
        }
    }

    private func topicRow(_ d: DomainProgress) -> some View {
        let cat = TriviaCategory.named(d.categoryID)
        let remaining = max(0, d.nextLevelCorrect - d.correct)
        return HStack(spacing: 12) {
            Image(systemName: cat.symbol).foregroundStyle(cat.color.legibleForeground)
                .frame(width: 34, height: 34).background(Circle().fill(cat.color))
                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(cat.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    if d.hasWedge { Image(systemName: "checkmark.seal.fill").foregroundStyle(Tidbits.Palette.mint) }
                    Spacer()
                    Text("Level \(d.level)").font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(cat.color.legibleForeground)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(cat.color))
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                bar(fraction: d.levelProgress, fill: cat.color)
                Text("\(d.correct) correct · \(remaining) more to Level \(d.level + 1)")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
        }
        .padding(14).chunkyCard()
    }

    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your calibration").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("From Stake rounds: how often each confidence level actually landed.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(calibration.filter { $0.total > 0 }, id: \.tierValue) { t in
                let pct = Int((Double(t.hits) / Double(t.total) * 100).rounded())
                HStack(spacing: 12) {
                    Text(tierLabel(t.tierValue)).font(Tidbits.TypeRamp.l3).frame(width: 70, alignment: .leading)
                        .foregroundStyle(Tidbits.Palette.ink)
                    bar(fraction: Double(t.hits) / Double(t.total), fill: Tidbits.Palette.mint)
                    Text("\(t.hits)/\(t.total) · \(pct)%").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.ink)
                        .frame(width: 92, alignment: .trailing)
                }
                .padding(12).chunkyCard()
            }
        }
    }

    private func tierLabel(_ v: Int) -> String { GameMode.stakeBudget.first { $0.value == v }?.label ?? "+\(v)" }

    private var bestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal bests").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("Click a mode to scroll your previous attempts.").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(GameMode.allCases) { mode in
                let attempts = records.filter { $0.mode == mode }
                if let best = attempts.map(\.score).max() {
                    Button { bestsMode = mode } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.symbol).foregroundStyle(mode.accent.legibleForeground)
                                .frame(width: 34, height: 34).background(Circle().fill(mode.accent))
                                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mode.title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                                Text("\(attempts.count) played").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                            }
                            Spacer()
                            Text("\(best)").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Tidbits.Palette.inkSoft)
                        }
                        .padding(14).chunkyCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Facts to review").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("Questions you missed. We'll quietly slip these back into future games.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(toReview.prefix(8), id: \.questionID) { fact in
                VStack(alignment: .leading, spacing: 4) {
                    Text(fact.prompt).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Text("Answer: \(fact.correctAnswer)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).chunkyCard(fill: Tidbits.Palette.bgDeep)
            }
        }
    }

    private func statBox(_ v: String, _ l: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Text(l.uppercased()).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16).chunkyCard(fill: tint.opacity(0.18))
    }

    private func bar(fraction: Double, fill: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Tidbits.Palette.bgDeep)
                Capsule().fill(fill).frame(width: max(6, geo.size.width * max(0, min(1, fraction))))
            }
            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
        }
        .frame(height: 12)
    }
}

// MARK: - Row + drill-in sheets

struct GameRow_macOS: View {
    let record: GameRecord
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.mode.symbol).foregroundStyle(record.mode.accent.legibleForeground)
                .frame(width: 34, height: 34).background(Circle().fill(record.mode.accent))
                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.mode.title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Text("· \(TriviaCategory.named(record.categoryID).name)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    Spacer()
                    Text("\(record.score)").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                }
                AnswerStrip_macOS(answers: record.answers, fallback: (record.correct, record.total))
                Text("\(record.correct)/\(record.total) correct · \(record.date.formatted(.relative(presentation: .named)))")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
        }
        .padding(14).chunkyCard()
    }
}

struct AnswerStrip_macOS: View {
    let answers: [AnswerDetail]
    let fallback: (correct: Int, total: Int)
    var body: some View {
        HStack(spacing: 3) {
            if answers.isEmpty {
                ForEach(0..<max(fallback.total, 1), id: \.self) { i in
                    pip(i < fallback.correct ? Tidbits.Palette.mint : Tidbits.Palette.surface)
                }
            } else {
                ForEach(answers.prefix(24)) { a in
                    pip(a.correct ? TriviaCategory.named(a.categoryID).color : Tidbits.Palette.surface)
                }
            }
        }
    }
    private func pip(_ c: Color) -> some View {
        Circle().fill(c).overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 1.5)).frame(width: 10, height: 10)
    }
}

private struct IDBox: Identifiable { let id: String; init(_ id: String) { self.id = id } }
private struct ModeBox: Identifiable { let mode: GameMode; var id: String { mode.rawValue }; init(_ m: GameMode) { mode = m } }

private struct SheetChrome_macOS<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            ScrollView { content.padding(20).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .frame(width: 480, height: 560)
        .background(Tidbits.Palette.bg)
    }
}

struct RecapSheet_macOS: View {
    let record: GameRecord
    var body: some View {
        SheetChrome_macOS(title: "\(record.mode.title) · \(record.score)") {
            VStack(alignment: .leading, spacing: 12) {
                if record.answers.isEmpty {
                    Text("This game was played before per-question history was added, so only the totals are here.")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                ForEach(record.answers) { AnswerLine_macOS(answer: $0) }
            }
        }
    }
}

struct DomainSheet_macOS: View {
    let categoryID: String
    let records: [GameRecord]
    private var answers: [AnswerDetail] {
        var seen = Set<String>(); var out: [AnswerDetail] = []
        for rec in records { for a in rec.answers where a.categoryID == categoryID && !seen.contains(a.qid) { seen.insert(a.qid); out.append(a) } }
        return out
    }
    var body: some View {
        let right = answers.filter(\.correct), wrong = answers.filter { !$0.correct }
        SheetChrome_macOS(title: TriviaCategory.named(categoryID).name) {
            VStack(alignment: .leading, spacing: 12) {
                if answers.isEmpty { Text("No per-question history yet for this domain.").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft) }
                if !wrong.isEmpty { Text("Missed (\(wrong.count))").font(Tidbits.TypeRamp.l2); ForEach(wrong) { AnswerLine_macOS(answer: $0) } }
                if !right.isEmpty { Text("Got right (\(right.count))").font(Tidbits.TypeRamp.l2); ForEach(right) { AnswerLine_macOS(answer: $0) } }
            }
        }
    }
}

struct BestsSheet_macOS: View {
    let mode: GameMode
    let records: [GameRecord]
    let onOpen: (GameRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let best = records.map(\.score).max() ?? 0
        SheetChrome_macOS(title: "\(mode.title) attempts") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Newest first. Your best is \(best).").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                ForEach(records) { rec in
                    Button { dismiss(); onOpen(rec) } label: {
                        HStack {
                            if rec.score == best { Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow) }
                            Text(rec.date.formatted(date: .abbreviated, time: .shortened)).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                            Spacer()
                            Text("\(rec.score)").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                        }
                        .padding(12).chunkyCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct AllGamesSheet_macOS: View {
    let records: [GameRecord]
    let onOpen: (GameRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        SheetChrome_macOS(title: "All games") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(records) { rec in
                    Button { dismiss(); onOpen(rec) } label: { GameRow_macOS(record: rec) }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct AnswerLine_macOS: View {
    let answer: AnswerDetail
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: answer.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(answer.correct ? Tidbits.Palette.mint : Tidbits.Palette.coral)
            VStack(alignment: .leading, spacing: 3) {
                Text(answer.prompt).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink).fixedSize(horizontal: false, vertical: true)
                Text("Answer: \(answer.answer)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).chunkyCard(fill: Tidbits.Palette.surface)
    }
}
#endif
