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
    /// Retained so the launch hook (`TIDBITS_LIVE_JOIN`) and any future Live-side
    /// entry can still reach the join sheet — but §A0.4.1 keeps the visible door on
    /// Play, because joining is a Trivia Night action.
    var onJoin: (() -> Void)? = nil

    @State private var store = LiveEventStore()
    @State private var selectedID: LiveEvent.ID?
    @State private var working = LiveEvent(name: "New Event")
    @State private var newFormat: GameMode = .classic
    @State private var newCategory: TriviaCategory = .named("mixed")
    @State private var newCount = 5
    @State private var busy = false
    @State private var expandedRounds: Set<UUID> = []
    @State private var editing: EditingQuestion?

    /// The question currently open in the editor sheet. `questionIndex == nil`
    /// means "a new question being appended to that round".
    struct EditingQuestion: Identifiable {
        let id = UUID()
        let roundIndex: Int
        let questionIndex: Int?
        let format: GameMode
        let draft: QuestionDraft
    }

    private var playableFormats: [GameMode] {
        // .weakSpot / .marathon are personal, Club-gated modes, not shareable
        // Live formats — never offered here.
        GameMode.allCases.filter { $0 != .daily && $0 != .barTrivia && $0 != .mix && $0 != .weakSpot && $0 != .marathon }
    }

    var body: some View {
        HStack(spacing: 0) {
            eventList
            Divider().overlay(Tidbits.Palette.border)
            editor
        }
        .background(Tidbits.Palette.bg)
        .navigationTitle("Tidbits Live")
        .onAppear {
            // Open the host's most recent night, not a blank draft. Creating one
            // unconditionally left the saved event visible in the list and an
            // unrelated empty draft in the editor — same name, nothing selected,
            // and the two disagreeing ("1 rounds" beside "No rounds yet"). A host
            // reasonably read that as their event having lost its rounds.
            guard selectedID == nil,
                  ProcessInfo.processInfo.environment["TIDBITS_LIVE_BUILDER"] != "1"
            else { return }
            if let latest = store.events.first {
                selectedID = latest.id
                working = latest
            } else {
                newEvent()
            }
        }
        // TIDBITS_LIVE_BUILDER=1 — open the builder on a populated event with its
        // first round expanded. The question list and the per-question editor are
        // otherwise unreachable from a cold launch, so nothing could observe them
        // (`hooks-are-coverage`). No-op in production.
        .task {
            // Not gated on `working.rounds.isEmpty`: onAppear now opens the
            // host's most recent night, so that guard started failing whenever a
            // saved event existed and the demo silently never loaded.
            guard ProcessInfo.processInfo.environment["TIDBITS_LIVE_BUILDER"] == "1" else { return }
            let ev = await LiveBuilderView_macOS.demoEvent()
            working = ev
            expandedRounds = Set(ev.rounds.prefix(1).map(\.id))
        }
        // TIDBITS_LIVE_ADDAUDIO=1 — open the audio-round file picker on launch, so a
        // harness can drive the REAL host path (NSOpenPanel grant -> security-scoped
        // bookmark -> playback) end to end. Nothing else can reach it: the grant is
        // what makes a clip work, and no in-process self-test can manufacture one.
        .task {
            guard ProcessInfo.processInfo.environment["TIDBITS_LIVE_ADDAUDIO"] == "1" else { return }
            try? await Task.sleep(for: .seconds(2))
            addAudioRound()
            if let last = working.rounds.last { expandedRounds = [last.id] }
        }
        .sheet(item: $editing) { ctx in
            LiveQuestionEditor_macOS(draft: ctx.draft, format: ctx.format,
                                     onSave: { q in
                                         if let qi = ctx.questionIndex,
                                            working.rounds.indices.contains(ctx.roundIndex),
                                            working.rounds[ctx.roundIndex].questions.indices.contains(qi) {
                                             working.rounds[ctx.roundIndex].questions[qi] = q
                                         } else {
                                             insertQuestion(q, into: ctx.roundIndex, at: nil)
                                         }
                                         editing = nil
                                     },
                                     onCancel: { editing = nil })
        }
    }

    // MARK: Event list

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Events").font(.headline).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button { newEvent() } label: { Image(systemName: "plus") }.buttonStyle(.borderless)
            }
            .padding(12)

            // JOINING lives on Play, not here (macOS-DESIGN §A0.4.1). A player with
            // a code is joining a TRIVIA NIGHT; that the night might have been opened
            // by a Live host is an implementation detail they never see. Having the
            // door on this page told every Mac user the two features were one.
            Divider().overlay(Tidbits.Palette.border)
            if store.events.isEmpty {
                // universal-feature-states: the saved-events column rendered as a blank
                // panel with no explanation of what belongs in it.
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 26)).foregroundStyle(Tidbits.Palette.inkSoft)
                    Text("No saved events yet")
                        .font(.body).foregroundStyle(Tidbits.Palette.ink)
                    Text("Build a night on the right, then Save event to keep it and re-run it next week.")
                        .font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
            List(selection: $selectedID) {
                ForEach(store.events) { ev in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ev.name).font(.headline).foregroundStyle(Tidbits.Palette.ink)
                        Text(Self.summary(rounds: ev.rounds.count, questions: ev.totalQuestions))
                            .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                        if let next = ev.nextOccurrence, let day = ev.weekdayName {   // Wave D: recurring series
                            Label("Every \(day) · next \(next.formatted(.dateTime.month().day()))", systemImage: "repeat")
                                .font(.caption).foregroundStyle(Tidbits.Palette.coral)
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
        }
        .frame(width: 240)
    }

    // MARK: Editor

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // The event name was a `.plain` TextField styled as a heading, so
                // it read as a title and nothing said it was editable (§5.6: a
                // control the host operates gets the native control).

                // A Form is the Mac idiom for a block of settings, and it also fixes
                // the clipped placeholders: the labels carry the explanation, so the
                // fields no longer need placeholder prose wider than the field.
                Form {
                    // Every field on this surface is the same control at the same
                    // size. The event name used to be 20pt semibold directly above
                    // a 13pt venue field (§5.7).
                    TextField("Event name", text: $working.name, prompt: Text("Friday Pub Quiz"))
                    TextField("Venue", text: $working.venue, prompt: Text("The Anchor"))
                        .help("Shown on the big screen and printed on the answer sheets")
                    Picker("Repeats", selection: Binding(get: { working.weekday ?? 0 },
                                                        set: { working.weekday = $0 == 0 ? nil : $0 })) {
                        Text("One-off").tag(0)
                        ForEach(1...7, id: \.self) { wd in
                            Text("Every \(Calendar.current.weekdaySymbols[wd - 1])").tag(wd)
                        }
                    }
                    if let next = working.nextOccurrence {
                        LabeledContent("Next night",
                                       value: next.formatted(.dateTime.weekday(.wide).month().day()))
                    }
                    TextField("Sponsor", text: $working.sponsor, prompt: Text("optional"))
                        .help("Shown as “brought to you by …” in the lobby and between rounds")
                    TextField("Mailing list", text: $working.leadCaptureURL, prompt: Text("https://…"))
                        .help("A “join our list” QR is shown at the end of the night")
                    LabeledContent("Brand accent") {
                        HStack(spacing: 8) {
                            ColorPicker("", selection: Binding(
                                get: { Color(hexString: working.brandHex) ?? Tidbits.Palette.coral },
                                set: { working.brandHex = $0.hexString }))
                                .labelsHidden()
                            if !working.brandHex.isEmpty {
                                Button("Reset") { working.brandHex = "" }.controlSize(.small)
                            }
                            Text("Colours the event title on the big screen")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.columns)
                .frame(maxWidth: 520)

                Text("Rounds").font(.title2.weight(.semibold)).foregroundStyle(Tidbits.Palette.ink)
                if working.rounds.isEmpty {
                    Text("No rounds yet — add one below.").font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                ForEach(Array(working.rounds.enumerated()), id: \.element.id) { i, round in
                    roundRow(i, round)
                }

                addRoundBar
                balanceMeter

                Divider().overlay(Tidbits.Palette.border).padding(.vertical, 4)
                // §5.6: native controls on a work surface. Buttons size to content
                // and wrap, so the row survives a narrow window instead of clipping.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { actionButtons }
                    VStack(alignment: .leading, spacing: 10) { actionButtons }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// "1 round · 1 question", not "1 rounds · 1 questions".
    static func summary(rounds: Int, questions: Int) -> String {
        let r = rounds == 1 ? "1 round" : "\(rounds) rounds"
        let q = questions == 1 ? "1 question" : "\(questions) questions"
        return "\(r) · \(q)"
    }

    @ViewBuilder private var actionButtons: some View {
        Button("Save event") { store.upsert(working); selectedID = working.id }
        Button("Preview solo") { store.upsert(working); onPreview(working) }
            .disabled(working.totalQuestions == 0)
        Button("Host live") { store.upsert(working); onHost(working) }
            .buttonStyle(.borderedProminent)
            // macOS-DESIGN §5.7 — ONE accent. Untinted, this took the system
            // accent (blue by default) and sat in the same view as the coral
            // "Add round", so the surface showed two different filled accents
            // and read as two design systems.
            .tint(Tidbits.Palette.coral)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(working.totalQuestions == 0)
        Menu {
            Button("Import CSV…") { importCSV() }
            Button("Audio round…") { addAudioRound() }
            Button("Video round…") { addVideoRound() }
        } label: { Label("Add round…", systemImage: "plus") }
            .fixedSize()
        Menu {
            Button("Export event…") { exportEvent() }
            Button("Import event…") { importEvent() }
            Divider()
            Button("Export questions as CSV…") { exportQuestionsCSV() }
                .disabled(working.totalQuestions == 0)
        } label: { Label("Event file", systemImage: "doc") }
            .fixedSize()
        Menu {
            Button("Question pack (host)") { LivePrint.questionPack(working) }
            Button("Answer sheet (teams)") { LivePrint.answerSheet(working) }
        } label: { Label("Print…", systemImage: "printer") }
            .fixedSize()
            .disabled(working.totalQuestions == 0)
    }

    private func roundRow(_ i: Int, _ round: LiveRound) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    if expandedRounds.contains(round.id) { expandedRounds.remove(round.id) }
                    else { expandedRounds.insert(round.id) }
                } label: {
                    Image(systemName: expandedRounds.contains(round.id) ? "chevron.down" : "chevron.right")
                        .foregroundStyle(Tidbits.Palette.inkSoft)
                }
                .buttonStyle(.borderless)
                .help("Show this round's questions")
                .accessibilityLabel(expandedRounds.contains(round.id) ? "Hide questions" : "Show questions")
                Image(systemName: round.symbol).foregroundStyle(round.format.accent.legibleForeground)
                    .frame(width: 34, height: 34).background(Circle().fill(round.format.accent))
                    .overlay(Circle().strokeBorder(Tidbits.Palette.border.opacity(0.55), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    // The round title was display-only, so a host could never rename
                    // "General Knowledge" to "Round 1 — Warm Up".
                    TextField("Round title", text: Binding(get: { working.rounds[i].title },
                                                           set: { working.rounds[i].title = $0 }))
                        .textFieldStyle(.plain)
                        .font(.headline).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
                    Text("\(round.format.title) · \(TriviaCategory.named(round.categoryID).name) · " + (round.questions.count == 1 ? "1 question" : "\(round.questions.count) questions"))
                        .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft).lineLimit(1)
                }
                Spacer()
                Button { move(i, up: true) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(i == 0)
                Button { move(i, up: false) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(i == working.rounds.count - 1)
                Button(role: .destructive) { working.rounds.remove(at: i) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            // Per-round settings live WITH the round, not in its title bar. Crowding
            // them into the header pushed the subtitle into an ellipsis and put
            // three controls where a title belongs (§5.7).
            HStack(spacing: 8) {
                Menu {   // Wave A: per-round countdown
                    Button("No timer") { working.rounds[i].timerSeconds = nil }
                    ForEach([30, 45, 60, 90, 120], id: \.self) { s in Button("\(s)s") { working.rounds[i].timerSeconds = s } }
                } label: { Label(round.timerSeconds.map { "\($0)s" } ?? "Timer", systemImage: "timer") }
                    .menuStyle(.button).buttonStyle(.bordered).fixedSize()
                Toggle(isOn: Binding(   // Wave A: wager round
                    get: { working.rounds[i].isWager ?? false },
                    set: { working.rounds[i].isWager = $0 ? true : nil })) {
                    Label("Wager", systemImage: "dollarsign.circle")
                }.toggleStyle(.button).font(.callout).fixedSize()
                Toggle(isOn: Binding(   // Wave B: speed round
                    get: { working.rounds[i].isSpeed ?? false },
                    set: { working.rounds[i].isSpeed = $0 ? true : nil })) {
                    Label("Speed", systemImage: "bolt")
                }.toggleStyle(.button).font(.callout).fixedSize()
                Spacer()
            }
            TextField("Host note (shown in the cockpit)", text: Binding(   // Wave A — its own line, full width
                get: { working.rounds[i].hostNote ?? "" },
                set: { working.rounds[i].hostNote = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder).font(.callout)
            if expandedRounds.contains(round.id) { questionList(i, round) }
        }
        .padding(14).quietCard()
        .draggable(round.id.uuidString)   // Wave A: drag-to-reorder (chevrons remain as a fallback)
        .dropDestination(for: String.self) { items, _ in
            guard let idStr = items.first,
                  let from = working.rounds.firstIndex(where: { $0.id.uuidString == idStr }), from != i else { return false }
            withAnimation { working.rounds.move(fromOffsets: IndexSet(integer: from), toOffset: from < i ? i + 1 : i) }
            return true
        }
    }

    // MARK: Questions inside a round (§A2.4 — every question opens to an editor)

    @ViewBuilder private func questionList(_ ri: Int, _ round: LiveRound) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Tidbits.Palette.border).padding(.vertical, 2)
            if round.questions.isEmpty {
                // universal-feature-states: an expanded round with nothing in it must
                // say so and offer the way out, not render as a blank strip.
                HStack(spacing: 8) {
                    Image(systemName: "text.badge.plus").foregroundStyle(Tidbits.Palette.inkSoft)
                    Text("No questions in this round yet.")
                        .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                .padding(.vertical, 6)
            }
            ForEach(Array(round.questions.enumerated()), id: \.element.id) { qi, q in
                questionRow(ri, qi, q, format: round.format)
            }
            HStack(spacing: 8) {
                Button {
                    editing = EditingQuestion(roundIndex: ri, questionIndex: nil, format: round.format,
                                              draft: .blank(format: round.format, categoryID: round.categoryID))
                } label: { Label("Add question", systemImage: "plus") }
                .buttonStyle(.bordered).controlSize(.small)
                Button {
                    Task {
                        busy = true
                        let more = await LiveEventStore.buildRound(format: round.format,
                                                                   category: .named(round.categoryID), count: 1)
                        if let q = more.questions.first { insertQuestion(q, into: ri, at: nil) }
                        busy = false
                    }
                } label: { Label("Pull one from the corpus", systemImage: "sparkles") }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(busy)
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func questionRow(_ ri: Int, _ qi: Int, _ q: Question, format: GameMode) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(qi + 1).")
                .font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(q.prompt.isEmpty ? "Untitled question" : q.prompt)
                    .font(.body).foregroundStyle(Tidbits.Palette.ink).lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(answerSummary(q, format: format))
                    .font(.caption).foregroundStyle(Tidbits.Palette.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("D\(q.difficulty)")
                .font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
            Button("Edit") {
                editing = EditingQuestion(roundIndex: ri, questionIndex: qi, format: format,
                                          draft: QuestionDraft(q))
            }
            .controlSize(.small)
            Menu {
                Button("Duplicate") { insertQuestion(q.duplicatedForEditing(), into: ri, at: qi + 1) }
                Button("Move up") { moveQuestion(ri, from: qi, to: qi - 1) }.disabled(qi == 0)
                Button("Move down") { moveQuestion(ri, from: qi, to: qi + 1) }
                    .disabled(qi >= working.rounds[ri].questions.count - 1)
                Divider()
                Button("Delete", role: .destructive) { removeQuestion(ri, at: qi) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary)
            .accessibilityLabel("More actions for question \(qi + 1)")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editing = EditingQuestion(roundIndex: ri, questionIndex: qi, format: format, draft: QuestionDraft(q))
        }
    }

    /// One line the host can scan to know whether a question is right, without opening it.
    private func answerSummary(_ q: Question, format: GameMode) -> String {
        switch format {
        case .closestCall: return q.closest.map { "Answer: \($0.formattedAnswer)" } ?? "No numeric answer set"
        case .ordering:    return (q.ordering?.prefix(4).joined(separator: " → ")).map { "Order: \($0)…" } ?? "No items"
        case .matching:    return "\(q.matching?.keys.count ?? 0) pairs"
        case .enumerate:   return "\(q.enumerate?.total ?? 0) accepted answers"
        case .typeAnswer:  return "Accepts: \((q.accepted ?? [q.correctAnswer]).prefix(3).joined(separator: ", "))"
        default:           return "Answer: \(q.correctAnswer)"
        }
    }

    // MARK: Question mutations (keep the AV bookmark arrays index-parallel)

    private func insertQuestion(_ q: Question, into ri: Int, at index: Int?) {
        guard working.rounds.indices.contains(ri) else { return }
        let at = index ?? working.rounds[ri].questions.count
        working.rounds[ri].questions.insert(q, at: min(at, working.rounds[ri].questions.count))
        // An audio/video round pairs bookmark[i] with question[i]; inserting a
        // question without a matching slot would silently shift every later clip
        // onto the wrong question.
        if working.rounds[ri].audioBookmarks != nil {
            working.rounds[ri].audioBookmarks?.insert(Data(), at: min(at, working.rounds[ri].audioBookmarks?.count ?? 0))
        }
        if working.rounds[ri].videoBookmarks != nil {
            working.rounds[ri].videoBookmarks?.insert(Data(), at: min(at, working.rounds[ri].videoBookmarks?.count ?? 0))
        }
    }

    private func removeQuestion(_ ri: Int, at qi: Int) {
        guard working.rounds.indices.contains(ri), working.rounds[ri].questions.indices.contains(qi) else { return }
        working.rounds[ri].questions.remove(at: qi)
        if working.rounds[ri].audioBookmarks?.indices.contains(qi) == true { working.rounds[ri].audioBookmarks?.remove(at: qi) }
        if working.rounds[ri].videoBookmarks?.indices.contains(qi) == true { working.rounds[ri].videoBookmarks?.remove(at: qi) }
    }

    private func moveQuestion(_ ri: Int, from: Int, to: Int) {
        guard working.rounds.indices.contains(ri) else { return }
        var qs = working.rounds[ri].questions
        guard qs.indices.contains(from), qs.indices.contains(to) else { return }
        qs.swapAt(from, to)
        working.rounds[ri].questions = qs
        if var bm = working.rounds[ri].audioBookmarks, bm.indices.contains(from), bm.indices.contains(to) {
            bm.swapAt(from, to); working.rounds[ri].audioBookmarks = bm
        }
        if var bm = working.rounds[ri].videoBookmarks, bm.indices.contains(from), bm.indices.contains(to) {
            bm.swapAt(from, to); working.rounds[ri].videoBookmarks = bm
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
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Tidbits.Palette.border.opacity(0.55), lineWidth: 1))
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
                Text("Balance").font(.headline).foregroundStyle(Tidbits.Palette.ink)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array([(easy, Tidbits.Palette.mint), (med, Tidbits.Palette.blue), (hard, Tidbits.Palette.coral)].enumerated()), id: \.offset) { _, seg in
                            if seg.0 > 0 { seg.1.frame(width: max(4, geo.size.width * CGFloat(seg.0) / CGFloat(qs.count))) }
                        }
                    }
                }
                .frame(height: 14).clipShape(Capsule())
                Text("Easy \(easy) · Medium \(med) · Hard \(hard)").font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                Text(byCat.prefix(6).map { "\($0.key.capitalized) \($0.value)" }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                if let hint = balanceHint(easy: easy, hard: hard, byCat: byCat, total: qs.count) {
                    Text(hint).font(.callout).foregroundStyle(Tidbits.Palette.coral)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Tidbits.Palette.bgDeep))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Tidbits.Palette.border.opacity(0.55), lineWidth: 1))
        }
    }

    private func balanceHint(easy: Int, hard: Int, byCat: [(key: String, value: Int)], total: Int) -> String? {
        if hard > total / 2 { return "Skews hard — a few easier questions keep the whole room in it." }
        if easy > total * 2 / 3 { return "Mostly easy — add a couple of stumpers for the ringers." }
        if let top = byCat.first, top.value > total / 2 { return "\(top.key.capitalized) dominates — mix in other categories for range." }
        return nil
    }

    // MARK: Event file round-trip (§A2.5)

    /// Write the working event out as one self-describing JSON document. A host's
    /// night is their work product: it has to survive a reinstall, move between
    /// their Mac and their Windows box, and be shareable with a co-host.
    private func exportEvent() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = LiveEventFile.suggestedFilename(for: working)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try LiveEventFile.write(working, to: url)
            // A dropped clip is told at EXPORT time as well as at import: the host
            // who made the file is the one who can re-attach the clips.
            let dropped = LiveEventFile.droppedClipCount(in: working)
            if dropped > 0 {
                let alert = NSAlert()
                alert.messageText = "Exported without \(dropped) clip\(dropped == 1 ? "" : "s")"
                alert.informativeText = "Audio and video clips point at files on this Mac, so they cannot travel in the event file. Every question came across — re-attach the clips on the other machine."
                alert.alertStyle = .informational
                alert.runModal()
            }
        }
        catch { presentError("Could not export the event", error) }
    }

    /// Read an event document back. The imported event gets a NEW id so importing
    /// a co-host's copy adds a night rather than silently overwriting one of yours.
    private func importEvent() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let ev = try LiveEventFile.read(from: url)
            working = ev
            store.upsert(ev)
            selectedID = ev.id
            expandedRounds = []
        } catch {
            presentError("Could not import that file", error)
        }
    }

    /// Import/export failures were silent `try?`s — a host who picked the wrong
    /// file saw nothing happen and had no way to know why.
    private func presentError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Write the event's questions out as a CSV a spreadsheet can edit (§6.1).
    /// The event file round-trips Tidbits-to-Tidbits; this is the door to Excel
    /// and back, which is how a host actually revises a bank between weeks.
    private func exportQuestionsCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(working.name) — questions.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(LiveCSV.exportCSV(working.questionStream).utf8).write(to: url, options: .atomic)
        } catch {
            presentMessage("Could not export the questions", error.localizedDescription)
        }
    }

    /// Wave A: CSV import — bulk-author a round from a host's question bank.
    /// Columns: prompt, correct, wrong1, wrong2, wrong3, [category], [difficulty 1-5], [explanation].
    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .text]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = LiveCSV.readTextFile(at: url) else {
            presentMessage("Could not read “\(url.lastPathComponent)”",
                           "Tidbits tried UTF-8, UTF-16 and Latin-1 and none of them decoded the file. "
                           + "Re-save it from your spreadsheet as CSV (UTF-8).")
            return
        }
        let qs = LiveCSV.parseCSVQuestions(text)
        guard !qs.isEmpty else {
            // A silent return here is how a host's CSV "imports" and nothing appears.
            presentMessage("No questions in “\(url.lastPathComponent)”",
                           "Each row needs at least: prompt, correct answer, and three wrong answers. "
                           + "Optional extras follow: category, difficulty 1-5, explanation.")
            return
        }
        working.rounds.append(LiveRound(title: "Imported round", format: .classic, categoryID: "mixed", questions: qs))
    }

    private func presentMessage(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.runModal()
    }

    /// Wave B: build an audio round from picked clips — each clip becomes a "name it"
    /// (typeAnswer) question, answer defaulting to the filename, with a security-scoped
    /// bookmark stored parallel so the host can play the right clip during the round.
    private func addAudioRound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav, .mpeg4Audio, .aiff]
        panel.allowsMultipleSelection = true
        // A harness can point the panel at a known folder so it only has to choose
        // the file; a person never sees this because the variable is unset.
        if let dir = ProcessInfo.processInfo.environment["TIDBITS_LIVE_CLIPDIR"] {
            panel.directoryURL = URL(fileURLWithPath: dir)
        }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        var questions: [Question] = []
        var bookmarks: [Data] = []
        var failures: [String] = []
        for (i, url) in panel.urls.enumerated() {
            // Make the bookmark FIRST. A clip whose reference cannot be kept must
            // not become a question: the old code stored an empty Data and the
            // round played silence with no way to tell.
            let mark: Data
            do { mark = try LiveClip.bookmark(for: url) }
            catch { failures.append(error.localizedDescription); continue }
            let answer = url.deletingPathExtension().lastPathComponent
            questions.append(Question(id: UUID().uuidString, prompt: "Track \(i + 1) — name it",
                                      options: [answer], correctIndex: 0, categoryID: "music", difficulty: 3,
                                      explanation: "", sourceTitle: "", sourceURL: nil, templateID: "audio",
                                      accepted: [answer]))
            bookmarks.append(mark)
        }
        if !failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = failures.count == panel.urls.count
                ? "Tidbits could not attach any of those clips"
                : "\(failures.count) of \(panel.urls.count) clips could not be attached"
            alert.informativeText = failures.prefix(3).joined(separator: "\n")
            alert.alertStyle = .warning
            alert.runModal()
        }
        guard !questions.isEmpty else { return }
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
        var failures: [String] = []
        for (i, url) in panel.urls.enumerated() {
            // Make the bookmark FIRST. A clip whose reference cannot be kept must
            // not become a question: the old code stored an empty Data and the
            // round played silence with no way to tell.
            let mark: Data
            do { mark = try LiveClip.bookmark(for: url) }
            catch { failures.append(error.localizedDescription); continue }
            let answer = url.deletingPathExtension().lastPathComponent
            questions.append(Question(id: UUID().uuidString, prompt: "Clip \(i + 1) — name it",
                                      options: [answer], correctIndex: 0, categoryID: "screen", difficulty: 3,
                                      explanation: "", sourceTitle: "", sourceURL: nil, templateID: "video",
                                      accepted: [answer]))
            bookmarks.append(mark)
        }
        if !failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = failures.count == panel.urls.count
                ? "Tidbits could not attach any of those clips"
                : "\(failures.count) of \(panel.urls.count) clips could not be attached"
            alert.informativeText = failures.prefix(3).joined(separator: "\n")
            alert.alertStyle = .warning
            alert.runModal()
        }
        guard !questions.isEmpty else { return }
        working.rounds.append(LiveRound(title: "Video round", format: .typeAnswer, categoryID: "screen",
                                        questions: questions, videoBookmarks: bookmarks))
    }

    /// The event the TIDBITS_LIVE_BUILDER hook opens on.
    static func demoEvent() async -> LiveEvent {
        var ev = LiveEvent(name: "Friday Pub Quiz", venue: "The Anchor")
        for (i, fmt) in [GameMode.classic, GameMode.typeAnswer].enumerated() {
            ev.rounds.append(await LiveEventStore.buildRound(
                format: fmt, category: .named(i == 0 ? "history" : "music"), count: 5))
        }
        return ev
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
