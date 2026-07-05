#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Tidbits Live — the event builder (macOS-DESIGN Part A §A2). Left: the host's
/// saved events. Right: the round editor. An event is an ordered list of named
/// rounds; each round pulls from the shared corpus/AI for its format+category,
/// which the host then shapes (§A2.2 no-auto-edit gate). "Preview" plays the
/// event solo; "Host" opens the cockpit.
struct LiveBuilderView_macOS: View {
    let onPreview: (LiveEvent) -> Void
    let onHost: (LiveEvent) -> Void

    @State private var store = LiveEventStore()
    @State private var selectedID: LiveEvent.ID?
    @State private var working = LiveEvent(name: "New Event")
    @State private var newFormat: GameMode = .classic
    @State private var newCategory: TriviaCategory = .named("mixed")
    @State private var newCount = 5
    @State private var busy = false

    private var playableFormats: [GameMode] {
        GameMode.allCases.filter { $0 != .daily && $0 != .barTrivia && $0 != .mix }
    }

    var body: some View {
        HStack(spacing: 0) {
            eventList
            Divider().overlay(Tidbits.Palette.border)
            editor
        }
        .background(Tidbits.Palette.bg)
        .navigationTitle("Tidbits Live")
        .onAppear { if selectedID == nil { newEvent() } }
    }

    // MARK: Event list

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Events").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button { newEvent() } label: { Image(systemName: "plus") }.buttonStyle(.borderless)
            }
            .padding(12)
            Divider().overlay(Tidbits.Palette.border)
            List(selection: $selectedID) {
                ForEach(store.events) { ev in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ev.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Text("\(ev.rounds.count) rounds · \(ev.totalQuestions) questions")
                            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        if let next = ev.nextOccurrence, let day = ev.weekdayName {   // Wave D: recurring series
                            Label("Every \(day) · next \(next.formatted(.dateTime.month().day()))", systemImage: "repeat")
                                .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.coral)
                        }
                    }
                    .tag(ev.id)
                    .contextMenu { Button("Delete", role: .destructive) { store.delete(ev) } }
                }
            }
            .onChange(of: selectedID) { _, id in
                if let id, let ev = store.events.first(where: { $0.id == id }) { working = ev }
            }
        }
        .frame(width: 240)
    }

    // MARK: Editor

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TextField("Event name", text: $working.name)
                    .textFieldStyle(.plain).font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
                TextField("Venue (shown on the big screen)", text: $working.venue)
                    .textFieldStyle(.roundedBorder).font(Tidbits.TypeRamp.l4)
                    .frame(maxWidth: 340)
                HStack(spacing: 8) {   // Wave D: recurring-series scheduling
                    Image(systemName: "repeat").foregroundStyle(Tidbits.Palette.inkSoft)
                    Menu {
                        Button("One-off (not recurring)") { working.weekday = nil }
                        ForEach(1...7, id: \.self) { wd in
                            Button("Every \(Calendar.current.weekdaySymbols[wd - 1])") { working.weekday = wd }
                        }
                    } label: {
                        Text(working.weekdayName.map { "Every \($0)" } ?? "One-off").font(Tidbits.TypeRamp.l5)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    if let next = working.nextOccurrence {
                        Text("· next \(next.formatted(.dateTime.weekday(.abbreviated).month().day()))")
                            .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                }
                TextField("Sponsor (optional — shown as “brought to you by …”)", text: $working.sponsor)   // Wave D: sponsor kit
                    .textFieldStyle(.roundedBorder).font(Tidbits.TypeRamp.l5).frame(maxWidth: 340)
                TextField("Mailing-list URL (optional — a “join our list” QR at the end)", text: $working.leadCaptureURL)   // Wave D: lead capture
                    .textFieldStyle(.roundedBorder).font(Tidbits.TypeRamp.l5).frame(maxWidth: 340)
                HStack(spacing: 10) {   // Wave D: white-label brand accent
                    ColorPicker("Brand accent (big-screen title)", selection: Binding(
                        get: { Color(hexString: working.brandHex) ?? Tidbits.Palette.coral },
                        set: { working.brandHex = $0.hexString }))
                        .font(Tidbits.TypeRamp.l5).fixedSize()
                    if !working.brandHex.isEmpty {
                        Button("Reset to default") { working.brandHex = "" }.font(Tidbits.TypeRamp.l6)
                    }
                }

                Text("Rounds").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                if working.rounds.isEmpty {
                    Text("No rounds yet — add one below.").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                ForEach(Array(working.rounds.enumerated()), id: \.element.id) { i, round in
                    roundRow(i, round)
                }

                addRoundBar
                balanceMeter

                Divider().overlay(Tidbits.Palette.border).padding(.vertical, 4)
                HStack(spacing: 10) {
                    Button("Save event") { store.upsert(working); selectedID = working.id }
                        .buttonStyle(CompactButtonStyle())
                    Button("Preview solo") { store.upsert(working); onPreview(working) }
                        .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.blue, textColor: .white, prominent: true))
                        .disabled(working.totalQuestions == 0)
                    Button("Host live →") { store.upsert(working); onHost(working) }
                        .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.coral, textColor: .white, prominent: true))
                        .disabled(working.totalQuestions == 0)
                    Menu {   // secondary "add a round type" actions — folded out of the primary row to declutter
                        Button("Import CSV…") { importCSV() }
                        Button("Audio round…") { addAudioRound() }
                        Button("Video round…") { addVideoRound() }
                    } label: { Label("Add round…", systemImage: "plus") }
                        .menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                    Menu {
                        Button("Question pack (host)") { LivePrint.questionPack(working) }
                        Button("Answer sheet (teams)") { LivePrint.answerSheet(working) }
                    } label: { Label("Print…", systemImage: "printer") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .disabled(working.totalQuestions == 0)
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func roundRow(_ i: Int, _ round: LiveRound) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: round.symbol).foregroundStyle(round.format.accent.legibleForeground)
                    .frame(width: 34, height: 34).background(Circle().fill(round.format.accent))
                    .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(round.title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
                    Text("\(round.format.title) · \(TriviaCategory.named(round.categoryID).name) · \(round.questions.count) questions")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).lineLimit(1)
                }
                Spacer()
                Menu {   // Wave A: per-round countdown
                    Button("No timer") { working.rounds[i].timerSeconds = nil }
                    ForEach([30, 45, 60, 90, 120], id: \.self) { s in Button("\(s)s") { working.rounds[i].timerSeconds = s } }
                } label: { Label(round.timerSeconds.map { "\($0)s" } ?? "Timer", systemImage: "timer") }
                    .menuStyle(.borderlessButton).fixedSize()
                Toggle(isOn: Binding(   // Wave A: wager round
                    get: { working.rounds[i].isWager ?? false },
                    set: { working.rounds[i].isWager = $0 ? true : nil })) {
                    Label("Wager", systemImage: "dollarsign.circle")
                }.toggleStyle(.button).font(Tidbits.TypeRamp.l5).fixedSize()
                Toggle(isOn: Binding(   // Wave B: speed round
                    get: { working.rounds[i].isSpeed ?? false },
                    set: { working.rounds[i].isSpeed = $0 ? true : nil })) {
                    Label("Speed", systemImage: "bolt")
                }.toggleStyle(.button).font(Tidbits.TypeRamp.l5).fixedSize()
                Button { move(i, up: true) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless).disabled(i == 0)
                Button { move(i, up: false) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless).disabled(i == working.rounds.count - 1)
                Button { working.rounds.remove(at: i) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            TextField("Host note (shown in the cockpit)", text: Binding(   // Wave A — its own line, full width
                get: { working.rounds[i].hostNote ?? "" },
                set: { working.rounds[i].hostNote = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder).font(Tidbits.TypeRamp.l5)
        }
        .padding(14).chunkyCard()
        .draggable(round.id.uuidString)   // Wave A: drag-to-reorder (chevrons remain as a fallback)
        .dropDestination(for: String.self) { items, _ in
            guard let idStr = items.first,
                  let from = working.rounds.firstIndex(where: { $0.id.uuidString == idStr }), from != i else { return false }
            withAnimation { working.rounds.move(fromOffsets: IndexSet(integer: from), toOffset: from < i ? i + 1 : i) }
            return true
        }
    }

    private var addRoundBar: some View {
        HStack(spacing: 10) {
            Picker("Format", selection: $newFormat) {
                ForEach(playableFormats) { Text($0.title).tag($0) }
            }.frame(width: 160)
            Picker("Category", selection: Binding(get: { newCategory.id }, set: { newCategory = .named($0) })) {
                ForEach(TriviaCategory.all) { Text($0.name).tag($0.id) }
            }.frame(width: 150)
            Stepper("\(newCount) Qs", value: $newCount, in: 1...15).frame(width: 110)
            Button {
                Task {
                    busy = true
                    let round = await LiveEventStore.buildRound(format: newFormat, category: newCategory, count: newCount)
                    working.rounds.append(round)
                    busy = false
                }
            } label: { Label("Add round", systemImage: "plus.circle.fill") }
            .buttonStyle(.borderedProminent).tint(Tidbits.Palette.coral)
            .disabled(busy)
            if busy { ProgressView().controlSize(.small) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Tidbits.Palette.bgDeep))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidbits.Palette.border, lineWidth: 2))
    }

    /// Wave A: a read-only composition meter — shows the host the night's difficulty curve
    /// and category spread so THEY can balance it. Informs, never auto-rebalances.
    @ViewBuilder private var balanceMeter: some View {
        let qs = working.questionStream
        if qs.count >= 2 {
            let easy = qs.filter { $0.difficulty <= 2 }.count
            let med = qs.filter { $0.difficulty == 3 }.count
            let hard = qs.filter { $0.difficulty >= 4 }.count
            let byCat = Dictionary(grouping: qs, by: { $0.categoryID }).mapValues(\.count).sorted { $0.value > $1.value }
            VStack(alignment: .leading, spacing: 8) {
                Text("Balance").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array([(easy, Tidbits.Palette.mint), (med, Tidbits.Palette.blue), (hard, Tidbits.Palette.coral)].enumerated()), id: \.offset) { _, seg in
                            if seg.0 > 0 { seg.1.frame(width: max(4, geo.size.width * CGFloat(seg.0) / CGFloat(qs.count))) }
                        }
                    }
                }
                .frame(height: 14).clipShape(Capsule())
                Text("Easy \(easy) · Medium \(med) · Hard \(hard)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                Text(byCat.prefix(6).map { "\($0.key.capitalized) \($0.value)" }.joined(separator: " · "))
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                if let hint = balanceHint(easy: easy, hard: hard, byCat: byCat, total: qs.count) {
                    Text(hint).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.coral)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Tidbits.Palette.bgDeep))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidbits.Palette.border, lineWidth: 2))
        }
    }

    private func balanceHint(easy: Int, hard: Int, byCat: [(key: String, value: Int)], total: Int) -> String? {
        if hard > total / 2 { return "Skews hard — a few easier questions keep the whole room in it." }
        if easy > total * 2 / 3 { return "Mostly easy — add a couple of stumpers for the ringers." }
        if let top = byCat.first, top.value > total / 2 { return "\(top.key.capitalized) dominates — mix in other categories for range." }
        return nil
    }

    /// Wave A: CSV import — bulk-author a round from a host's question bank.
    /// Columns: prompt, correct, wrong1, wrong2, wrong3, [category], [difficulty 1-5], [explanation].
    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .text]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let qs = Self.parseCSVQuestions(text)
        guard !qs.isEmpty else { return }
        working.rounds.append(LiveRound(title: "Imported round", format: .classic, categoryID: "mixed", questions: qs))
    }

    /// Wave B: build an audio round from picked clips — each clip becomes a "name it"
    /// (typeAnswer) question, answer defaulting to the filename, with a security-scoped
    /// bookmark stored parallel so the host can play the right clip during the round.
    private func addAudioRound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav, .mpeg4Audio, .aiff]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        var questions: [Question] = []
        var bookmarks: [Data] = []
        for (i, url) in panel.urls.enumerated() {
            let answer = url.deletingPathExtension().lastPathComponent
            questions.append(Question(id: UUID().uuidString, prompt: "Track \(i + 1) — name it",
                                      options: [answer], correctIndex: 0, categoryID: "music", difficulty: 3,
                                      explanation: "", sourceTitle: "", sourceURL: nil, templateID: "audio",
                                      accepted: [answer]))
            bookmarks.append((try? url.bookmarkData(options: .withSecurityScope)) ?? Data())
        }
        working.rounds.append(LiveRound(title: "Audio round", format: .typeAnswer, categoryID: "music",
                                        questions: questions, audioBookmarks: bookmarks))
    }

    /// Wave B: build a video round from picked clips — each becomes a "name it" (typeAnswer)
    /// question; the clip plays on the big screen during the round.
    private func addVideoRound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        var questions: [Question] = []
        var bookmarks: [Data] = []
        for (i, url) in panel.urls.enumerated() {
            let answer = url.deletingPathExtension().lastPathComponent
            questions.append(Question(id: UUID().uuidString, prompt: "Clip \(i + 1) — name it",
                                      options: [answer], correctIndex: 0, categoryID: "screen", difficulty: 3,
                                      explanation: "", sourceTitle: "", sourceURL: nil, templateID: "video",
                                      accepted: [answer]))
            bookmarks.append((try? url.bookmarkData(options: .withSecurityScope)) ?? Data())
        }
        working.rounds.append(LiveRound(title: "Video round", format: .typeAnswer, categoryID: "screen",
                                        questions: questions, videoBookmarks: bookmarks))
    }

    static func parseCSVQuestions(_ text: String) -> [Question] {
        var out: [Question] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let f = splitCSVLine(String(raw))
            guard f.count >= 5, !f[0].isEmpty, !f[1].isEmpty else { continue }
            if ["prompt", "question"].contains(f[0].lowercased()) { continue }   // header row
            var opts = [f[1], f[2], f[3], f[4]].filter { !$0.isEmpty }
            while opts.count < 4 { opts.append("—") }
            opts = Array(opts.prefix(4)).shuffled()
            let ci = opts.firstIndex(of: f[1]) ?? 0
            let cat = (f.count > 5 && !f[5].isEmpty) ? f[5].lowercased() : "mixed"
            let diff = min(5, max(1, f.count > 6 ? (Int(f[6]) ?? 3) : 3))
            let expl = f.count > 7 ? f[7] : ""
            out.append(Question(id: UUID().uuidString, prompt: f[0], options: opts, correctIndex: ci,
                                categoryID: cat, difficulty: diff, explanation: expl,
                                sourceTitle: "", sourceURL: nil, templateID: "csv"))
        }
        return out
    }

    /// Minimal quote-aware CSV line split (handles "commas, in fields").
    static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []; var cur = ""; var inQuotes = false
        for ch in line {
            if ch == "\"" { inQuotes.toggle() }
            else if ch == ",", !inQuotes { fields.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
            else { cur.append(ch) }
        }
        fields.append(cur.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private func newEvent() {
        working = LiveEvent(name: "New Event")
        selectedID = nil
    }
    private func move(_ i: Int, up: Bool) {
        let t = up ? i - 1 : i + 1
        guard working.rounds.indices.contains(t) else { return }
        working.rounds.swapAt(i, t)
    }
}

// MARK: - Solo preview (play the assembled event yourself)

/// Plays a built event solo through the shared engine (round-tagged night).
/// A preview is a rehearsal tool — it does NOT write to personal Records.
struct LivePreviewContainer_macOS: View {
    let event: LiveEvent
    let onClose: () -> Void

    @Environment(AppStore.self) private var store
    @State private var started = false
    private var game: GameEngine { store.game }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                ProgressView().controlSize(.large)
            case .roundIntro:
                RoundIntroView_macOS(game: game, onQuit: close)
            case .playing, .reveal:
                GameView_macOS(game: game, onQuit: close)
            case .finished:
                ResultsView_macOS(summary: game.summary, onPlayAgain: nil, onDone: close)
            }
        }
        .onAppear {
            if !started {
                started = true
                game.startNight(plan: event.nightPlan, category: .named("mixed"),
                                questions: event.questionStream, hostPaced: false)
            }
        }
    }
    private func close() { game.quit(); onClose() }
}
#endif
