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

    @State private var store = LiveEventStore()
    @State private var library = LiveLibraryStore()          // §6: the host's own bank, across nights
    @State private var libraryPickFor: Int? = nil            // the round a "From library…" is adding to
    @Environment(AppStore.self) private var appStore   // the deep-link inbox's pending package
    @State private var selectedID: LiveEvent.ID?
    @State private var working = LiveEvent(name: "New Event")
    @State private var newFormat: GameMode = .classic
    @State private var newCategory: TriviaCategory = .named("mixed")
    @State private var newCount = 5
    @State private var busy = false
    @State private var expandedRounds: Set<UUID> = []
    @State private var editing: EditingQuestion?
    private var played: LivePlayedLog { LivePlayedLog.shared }   // A2.6: what the room has heard
    /// The last file operation's result, shown on the builder. A host who exports
    /// and sees nothing cannot tell success from a silently-cancelled panel — and
    /// it is what makes the file path GRADEABLE from a screenshot.
    @State private var fileReceipt: String?

    /// The question currently open in the editor sheet. `questionIndex == nil`
    /// means "a new question being appended to that round".
    struct LibraryPick: Identifiable { let round: Int; var id: Int { round } }

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
        // macOS-DESIGN §B2.1 — every command that has a button here also has a
        // menu item. The bundle is republished whenever the working event changes
        // so `hasQuestions` (which gates Print and Host) stays honest.
        .focusedSceneValue(\.liveBuilder, LiveBuilderCommands(
            hasQuestions: working.totalQuestions > 0,
            newEvent: { newEvent() },
            saveEvent: { store.upsert(working); selectedID = working.id },
            addRound: {
                Task {
                    busy = true
                    let r = await LiveEventStore.buildRound(format: newFormat, category: newCategory, count: newCount)
                    working.rounds.append(r)
                    busy = false
                }
            },
            addAudioRound: { addAudioRound() },
            addVideoRound: { addVideoRound() },
            addBoardRound: { addBoardRound() },
            hostLive: { store.upsert(working); onHost(working) },
            previewSolo: { store.upsert(working); onPreview(working) },
            duplicateEvent: { duplicateEvent(working, fresh: working.weekday != nil) },
            refreshRepeats: { Task { await refreshRepeats() } },
            importQuestions: { importCSV() },
            importQuickQuestions: { importQuickQuestions() },
            importEvent: { importEvent() },
            exportPackage: { exportPackage() },
            exportEvent: { exportEvent() },
            exportLibrary: { exportLibrary() },
            exportCSV: { exportQuestionsCSV() },
            exportGIFT: { exportQuestionsGIFT() },
            exportKahoot: { exportKahootSheet() },
            printQuestionPack: { LivePrint.questionPack(working) },
            printAnswerSheet: { LivePrint.answerSheet(working) }))
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
        // TIDBITS_LIVE_FILEOP=exportevent|importevent|exportcsv|importcsv — run one
        // file operation on launch, with TIDBITS_LIVE_FILE supplying the path the
        // panel would have returned. This is what makes the EDGE observable: the
        // behaviour layer (encode/decode/parse) has had good coverage all along,
        // but nothing drove button -> panel -> file on disk, which is the half a
        // host actually touches.
        .task {
            guard let op = ProcessInfo.processInfo.environment["TIDBITS_LIVE_FILEOP"] else { return }
            try? await Task.sleep(for: .seconds(3))   // let the demo event load first
            switch op {
            case "exportevent": exportEvent()
            case "importevent": importEvent()
            case "exportpackage": exportPackage()
            case "importpackage": importEvent()   // the one importer opens both shapes
            case "exportlibrary": exportLibrary()
            case "importqq": importQuickQuestions()
            case "exportkahoot": exportKahootSheet()
            case "exportcsv":   exportQuestionsCSV()
            case "importcsv":   importCSV()
            case "printpack":
                LivePrint.questionPack(working)
                fileReceipt = "Printed \(LivePrint.lastRenderedPages) pages"
            case "printsheet":
                LivePrint.answerSheet(working)
                fileReceipt = "Printed \(LivePrint.lastRenderedPages) pages"
            default: break
            }
        }
        // TIDBITS_LIVE_REFRESH=1 — after the import above lands, open every round
        // (so the asked-before badges are on screen at 5 s) and at 14 s swap the
        // questions the room has heard, through the same call as the button
        // (A2.6; hooks-are-coverage). No-op in production.
        .task {
            guard ProcessInfo.processInfo.environment["TIDBITS_LIVE_REFRESH"] == "1" else { return }
            try? await Task.sleep(for: .seconds(5))
            expandedRounds = Set(working.rounds.map(\.id))
            try? await Task.sleep(for: .seconds(9))
            await refreshRepeats()
        }
        // TIDBITS_LIVE_ADDVIDEO=1 — build a VIDEO round on launch, paired with
        // TIDBITS_LIVE_CLIPS. A video round that renders a black rectangle passes
        // every unit test in the suite, so the only way to know the surface works
        // is to put a real clip through the real path and photograph it.
        .task {
            guard ProcessInfo.processInfo.environment["TIDBITS_LIVE_ADDVIDEO"] == "1" else { return }
            try? await Task.sleep(for: .seconds(2))
            addVideoRound()
            if let last = working.rounds.last { expandedRounds = [last.id] }
        }
        // TIDBITS_LIVE_EDITQ=1 — open the FIRST question's editor after the demo
        // event loads, so the editor (and its Picture section, LIVE-PACKAGE-FORMAT
        // §8.1) can be photographed. A per-question sheet is otherwise unreachable
        // from a cold launch (hooks-are-coverage). No-op in production.
        .task {
            guard ProcessInfo.processInfo.environment["TIDBITS_LIVE_EDITQ"] == "1" else { return }
            try? await Task.sleep(for: .seconds(3))
            guard let round = working.rounds.first, let q = round.questions.first else { return }
            // A bare filename resolves inside the sandbox's Documents, like TIDBITS_LIVE_FILE.
            if let p = ProcessInfo.processInfo.environment["TIDBITS_LIVE_PICTURE"], !p.isEmpty,
               let data = try? Data(contentsOf: p.contains("/") ? URL(fileURLWithPath: p)
                                    : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(p)),
               let id = try? LiveMediaStore.store(data, ext: (p as NSString).pathExtension, originalName: (p as NSString).lastPathComponent) {
                var pictured = q; pictured.imageURL = LiveMediaStore.reference(id)
                working.rounds[0].questions[0] = pictured
            }
            // TIDBITS_LIVE_CLIP=<file in Documents> attaches an audio clip to it first.
            if let p = ProcessInfo.processInfo.environment["TIDBITS_LIVE_CLIP"], !p.isEmpty, !p.contains("/"),
               let data = try? Data(contentsOf: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(p)),
               let id = try? LiveMediaStore.store(data, ext: (p as NSString).pathExtension, originalName: p) {
                applyClip(.set(id: id), video: false, ri: 0, qi: 0)
            }
            editing = EditingQuestion(roundIndex: 0, questionIndex: 0, format: round.format,
                                      draft: draftFor(0, 0))
        }
        // A double-clicked .tidbits (DeepLink.package): import it and select the night.
        // Checked on appear too — the inbox can drain before this view exists.
        .onChange(of: appStore.pendingPackageURL) { _, _ in consumePendingPackage() }
        .onAppear { consumePendingPackage() }
        // TIDBITS_LIVE_LIBRARY=1 — open the library picker on round 1 after the demo
        // event loads, so the picker can be photographed (hooks-are-coverage).
        .task {
            guard ProcessInfo.processInfo.environment["TIDBITS_LIVE_LIBRARY"] == "1" else { return }
            try? await Task.sleep(for: .seconds(3))
            if library.items.isEmpty, let r = working.rounds.first { library.add(r.questions, source: working.name) }
            libraryPickFor = 0
        }
        .sheet(item: Binding(get: { libraryPickFor.map { LibraryPick(round: $0) } },
                             set: { libraryPickFor = $0?.round })) { pick in
            LiveLibraryPicker_macOS(library: library,
                                    onAdd: { q in insertQuestion(q.duplicatedForEditing(), into: pick.round, at: nil) },   // a fresh id per use
                                    onClose: { libraryPickFor = nil })
        }
        .sheet(item: $editing) { ctx in
            LiveQuestionEditor_macOS(draft: ctx.draft, format: ctx.format,
                                     onSave: { q, audio, video in
                                         let qi: Int
                                         if let i = ctx.questionIndex,
                                            working.rounds.indices.contains(ctx.roundIndex),
                                            working.rounds[ctx.roundIndex].questions.indices.contains(i) {
                                             working.rounds[ctx.roundIndex].questions[i] = q
                                             qi = i
                                         } else {
                                             insertQuestion(q, into: ctx.roundIndex, at: nil)
                                             qi = max(0, (working.rounds.indices.contains(ctx.roundIndex)
                                                          ? working.rounds[ctx.roundIndex].questions.count : 1) - 1)
                                         }
                                         applyClip(audio, video: false, ri: ctx.roundIndex, qi: qi)
                                         applyClip(video, video: true, ri: ctx.roundIndex, qi: qi)
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
                        Text(LivePrint.summary(rounds: ev.rounds.count, questions: ev.totalQuestions))
                            .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                        if let next = ev.nextOccurrence, let day = ev.weekdayName {   // Wave D: recurring series
                            Label("Every \(day) · next \(next.formatted(.dateTime.month().day()))", systemImage: "repeat")
                                .font(.caption).foregroundStyle(Tidbits.Palette.coral)
                        }
                    }
                    .tag(ev.id)
                    .contextMenu {
                        // A2.7: the night as a template — next week's copy, fresh where the
                        // room has heard it.
                        Button(ev.weekday != nil ? "Clone for next \(ev.weekdayName ?? "week") with fresh questions" : "Duplicate") {
                            duplicateEvent(ev, fresh: ev.weekday != nil)
                        }
                        if ev.weekday != nil { Button("Duplicate as is") { duplicateEvent(ev, fresh: false) } }
                        Button("Delete", role: .destructive) { store.delete(ev) }
                    }
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
            VStack(alignment: .leading, spacing: 20) {
                eventHeader
                if let r = fileReceipt {
                    Label(r, systemImage: "checkmark.circle.fill")
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .quietCard(fill: Tidbits.Palette.mint.opacity(0.28))
                }
                eventDetailsCard

                sectionHeader("Rounds", trailing: working.rounds.isEmpty
                              ? nil : pluralized(working.rounds.count, "round"))
                if working.rounds.isEmpty {
                    Text("No rounds yet — add one below.")
                        .font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.inkSoft)
                        .padding(.vertical, 6)
                }
                ForEach(Array(working.rounds.enumerated()), id: \.element.id) { i, round in
                    roundRow(i, round)
                }

                addRoundBar
                balanceMeter

                sectionHeader("Event file")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { actionButtons }
                    VStack(alignment: .leading, spacing: 10) { actionButtons }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// The screen's identity and its ONE primary action, at the top where a host
    /// looks first. "Host live" used to be the third of five equal text buttons at
    /// the very bottom of the scroll (§5.6/§5.7 — one primary, and hierarchy).
    private var eventHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(working.name.isEmpty ? "New Event" : working.name)
                    .font(Tidbits.TypeRamp.l1).foregroundStyle(Tidbits.Palette.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(subtitleLine)
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Spacer(minLength: 12)
            Button {
                store.upsert(working); onHost(working)
            } label: {
                Label("Host live", systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.coral,
                                            textColor: .white, prominent: true))
            .disabled(working.totalQuestions == 0)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Open the host cockpit and put this night on the big screen (⌘↩)")
        }
    }

    private var subtitleLine: String {
        var parts: [String] = []
        if !working.venue.isEmpty { parts.append(working.venue) }
        parts.append(pluralized(working.rounds.count, "round"))
        parts.append(pluralized(working.totalQuestions, "question"))
        return parts.joined(separator: " · ")
    }

    /// L2 with an optional count on the right — the hierarchy the flat stack lacked.
    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Spacer()
            if let trailing {
                Text(trailing).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
        }
        .padding(.top, 4)
    }

    /// The event's settings, in a card, with fields sized to what they hold —
    /// a mailing-list URL does not deserve the whole window (§5.7 Proportion).
    private var eventDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Event name", help: "Shown on the big screen and the answer sheets") {
                TextField("", text: $working.name, prompt: Text("Friday Pub Quiz"))
                    .textFieldStyle(.roundedBorder).frame(width: 320)
            }
            field("Venue", help: "Shown on the big screen and printed on the answer sheets") {
                TextField("", text: $working.venue, prompt: Text("The Anchor"))
                    .textFieldStyle(.roundedBorder).frame(width: 320)
            }
            field("Repeats") {
                HStack(spacing: 10) {
                    Picker("", selection: Binding(get: { working.weekday ?? 0 },
                                                  set: { working.weekday = $0 == 0 ? nil : $0 })) {
                        Text("One-off").tag(0)
                        ForEach(1...7, id: \.self) { wd in
                            Text("Every \(Calendar.current.weekdaySymbols[wd - 1])").tag(wd)
                        }
                    }
                    .labelsHidden().frame(width: 200)
                    if let next = working.nextOccurrence {
                        Text("next " + next.formatted(.dateTime.weekday(.abbreviated).month().day()))
                            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                }
            }
            field("Sponsor", help: "Shown as “brought to you by …” in the lobby and between rounds") {
                TextField("", text: $working.sponsor, prompt: Text("optional"))
                    .textFieldStyle(.roundedBorder).frame(width: 320)
            }
            field("Mailing list", help: "A “join our list” QR is shown at the end of the night") {
                TextField("", text: $working.leadCaptureURL, prompt: Text("https://…"))
                    .textFieldStyle(.roundedBorder).frame(width: 320)
            }
            field("Brand accent", help: "Colors the event title on the big screen") {
                HStack(spacing: 10) {
                    ColorPicker("", selection: Binding(
                        get: { Color(hexString: working.brandHex) ?? Tidbits.Palette.coral },
                        set: { working.brandHex = $0.hexString }))
                        .labelsHidden()
                    if !working.brandHex.isEmpty {
                        Button("Reset") { working.brandHex = "" }
                            .buttonStyle(CompactButtonStyle())
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chunkyCard(fill: Tidbits.Palette.bg)
    }

    /// One labelled row: a fixed label column so every field starts at the same x,
    /// which is what makes a stack of settings read as a form instead of a list.
    private func field<Content: View>(_ label: String, help: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                .frame(width: 110, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                content()
                if let help {
                    Text(help).font(.footnote).foregroundStyle(Tidbits.Palette.inkSoft.opacity(0.85))
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// File plumbing only. "Host live" is the header's primary (§5.7 — one
    /// prominent control per surface), so nothing down here competes with it and
    /// every control in the row is the same style at the same size.
    @ViewBuilder private var actionButtons: some View {
        Button("Save event") { store.upsert(working); selectedID = working.id }
            .buttonStyle(CompactButtonStyle())
            .keyboardShortcut("s", modifiers: .command)
            .help("Save this event to your library (⌘S)")
        Button("Preview solo") { store.upsert(working); onPreview(working) }
            .buttonStyle(CompactButtonStyle())
            .disabled(working.totalQuestions == 0)
            .help("Play the night yourself before you host it")
        Menu {
            Button("Import questions (CSV, GIFT, Aiken)…") { importCSV() }
            Button("Import a SpeedQuizzing folder…") { importQuickQuestions() }
            Button("Audio round…") { addAudioRound() }
            Button("Video round…") { addVideoRound() }
            Divider()
            Button("Pick-a-category board…") { addBoardRound() }
        } label: { Label("Add round…", systemImage: "plus") }
            .menuStyle(.button).buttonStyle(CompactButtonStyle()).fixedSize()
        Menu {
            // The PACKAGE is the distributable form (LIVE-PACKAGE-FORMAT, Decision
            // 059): pictures and clips inside. The bare document is kept for
            // hosts who want text they can diff or edit by hand.
            Button("Export package (with media)…") { exportPackage() }
            Button("Export event as JSON…") { exportEvent() }
            Button("Import event or package…") { importEvent() }
            Divider()
            Button("Export library as bank package…") { exportLibrary() }
                .disabled(library.items.isEmpty)
            Divider()
            Button("Export questions as CSV…") { exportQuestionsCSV() }
                .disabled(working.totalQuestions == 0)
            Button("Export questions as GIFT…") { exportQuestionsGIFT() }
                .disabled(working.totalQuestions == 0)
            Button("Export for Kahoot (.xlsx)…") { exportKahootSheet() }
                .disabled(working.totalQuestions == 0)
        } label: { Label("Event file", systemImage: "doc") }
            .menuStyle(.button).buttonStyle(CompactButtonStyle()).fixedSize()

        Menu {
            Button("Question pack (host)") { LivePrint.questionPack(working) }
            Button("Answer sheet (teams)") { LivePrint.answerSheet(working) }
        } label: { Label("Print…", systemImage: "printer") }
            .menuStyle(.button).buttonStyle(CompactButtonStyle()).fixedSize()
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
                }
                .buttonStyle(RoundIconButtonStyle())
                .help("Show this round's questions")
                .accessibilityLabel(expandedRounds.contains(round.id) ? "Hide questions" : "Show questions")
                Image(systemName: round.symbol).foregroundStyle(round.format.accent.legibleForeground)
                    .font(.system(size: 16, weight: .black))
                    .frame(width: 38, height: 38).background(Circle().fill(round.format.accent))
                    .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    // The round title was display-only, so a host could never rename
                    // "General Knowledge" to "Round 1 — Warm Up".
                    TextField("Round title", text: Binding(get: { working.rounds[i].title },
                                                           set: { working.rounds[i].title = $0 }))
                        .textFieldStyle(.plain)
                        .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
                    Text("\(round.format.title) · \(TriviaCategory.named(round.categoryID).name) · " + (round.questions.count == 1 ? "1 question" : "\(round.questions.count) questions"))
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).lineLimit(1)
                }
                Spacer()
                Button { move(i, up: true) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(RoundIconButtonStyle()).disabled(i == 0)
                    .help("Move this round earlier (⌘⌥↑)").accessibilityLabel("Move round up")
                Button { move(i, up: false) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(RoundIconButtonStyle()).disabled(i == working.rounds.count - 1)
                    .help("Move this round later (⌘⌥↓)").accessibilityLabel("Move round down")
                Button(role: .destructive) { working.rounds.remove(at: i) } label: { Image(systemName: "trash") }
                    .buttonStyle(RoundIconButtonStyle(tint: Tidbits.Palette.coral))
                    .help("Delete this round").accessibilityLabel("Delete round")
            }
            // Per-round settings live WITH the round, not in its title bar. Crowding
            // them into the header pushed the subtitle into an ellipsis and put
            // three controls where a title belongs (§5.7).
            HStack(spacing: 8) {
                Menu {   // Wave A: per-round countdown
                    Button("No timer") { working.rounds[i].timerSeconds = nil }
                    ForEach([30, 45, 60, 90, 120], id: \.self) { s in Button("\(s)s") { working.rounds[i].timerSeconds = s } }
                } label: { Label(round.timerSeconds.map { "\($0)s" } ?? "Timer", systemImage: "timer") }
                    .menuStyle(.button).buttonStyle(CompactButtonStyle()).fixedSize()
                roundFlagChip("Wager", systemImage: "dollarsign.circle",   // Wave A: wager round
                              isOn: Binding(get: { working.rounds[i].isWager ?? false },
                                            set: { working.rounds[i].isWager = $0 ? true : nil }),
                              help: "Wager round — teams stake points on each question")
                roundFlagChip("Speed", systemImage: "bolt",                 // Wave B: speed round
                              isOn: Binding(get: { working.rounds[i].isSpeed ?? false },
                                            set: { working.rounds[i].isSpeed = $0 ? true : nil }),
                              help: "Speed round — the fastest correct answers earn a bonus")
                roundFlagChip("Buzz", systemImage: "hand.tap",              // G1: buzz round
                              isOn: Binding(get: { working.rounds[i].isBuzz ?? false },
                                            set: { working.rounds[i].isBuzz = $0 ? true : nil }),
                              help: "Buzz round — the room races to buzz and the first team answers out loud")
                Menu {   // G4: first-letter round — every answer begins with the same letter
                    Button("No letter theme") { working.rounds[i].letter = nil }
                    Divider()
                    ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), id: \.self) { c in
                        Button(String(c)) { working.rounds[i].letter = String(c) }
                    }
                } label: {
                    Text(round.letter.map { "Letter \($0)" } ?? "Letter")
                }
                .menuStyle(.button).buttonStyle(CompactButtonStyle()).fixedSize()
                .help("First-letter round — every answer in it begins with the same letter")
                Spacer()
            }
            // G4: a letter theme the round does not actually keep is worse than no
            // theme — the host announces "B" and the room hears an answer that
            // isn't one. Name the offenders rather than refusing the edit; a
            // half-built round is a normal state to be in mid-build.
            if let l = round.letter, let ch = l.first {
                let bad = LiveLetterRound.violations(in: round.questions, letter: ch)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: bad.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                    Text(bad.isEmpty
                         ? "Every answer begins with \(ch)."
                         : (bad.count == 1
                            ? "1 answer does not begin with \(ch): \(bad[0].correctAnswer)"
                            : "\(bad.count) answers do not begin with \(ch): " + bad.prefix(3).map(\.correctAnswer).joined(separator: ", ") + (bad.count > 3 ? "…" : "")))
                        .lineLimit(2)
                }
                .font(.callout)
                .foregroundStyle(bad.isEmpty ? Tidbits.Palette.inkSoft : Color.orange)
            }
            // A2.6: a re-run night names its repeats up front, with the one-click fix.
            let heard = LivePlayedLog.repeats(in: round.questions, played: played.ids).count
            if heard > 0 {
                HStack(spacing: 8) {
                    Label(heard == 1 ? "1 question the room has heard" : "\(heard) questions the room has heard",
                          systemImage: "clock.arrow.circlepath")
                        .font(.callout).foregroundStyle(Tidbits.Palette.coral)
                    Button(heard == 1 ? "Swap it for a fresh one" : "Swap them for fresh ones") {
                        Task { await refreshRepeats(rounds: [i]) }
                    }
                    .buttonStyle(.bordered).controlSize(.small).disabled(busy)
                    .accessibilityIdentifier("live.refreshRepeats")
                }
            }
            TextField("Host note (shown in the cockpit)", text: Binding(   // Wave A — its own line, full width
                get: { working.rounds[i].hostNote ?? "" },
                set: { working.rounds[i].hostNote = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder).font(Tidbits.TypeRamp.l5)
            if expandedRounds.contains(round.id) { questionList(i, round) }
        }
        .padding(16).chunkyCard(fill: Tidbits.Palette.bg)
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
                } label: { Label("Add one from the question bank", systemImage: "sparkles") }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(busy)
                Button { libraryPickFor = ri } label: { Label("From library…", systemImage: "books.vertical") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Add questions you saved from earlier nights")
                if !round.questions.isEmpty {
                    Button {
                        let n = library.add(round.questions, source: working.name)
                        fileReceipt = "Saved round to your library: \(n) new, \(round.questions.count - n) already there"
                    } label: { Label("Save round to library", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                // G4: hand-picking eight answers that all begin with B out of a
                // 98,000-question corpus is not something a host will do, so the
                // themed round fills itself.
                if let l = round.letter, let ch = l.first {
                    Button {
                        Task {
                            busy = true
                            let more = await LiveEventStore.letterQuestions(
                                format: round.format, category: .named(round.categoryID),
                                letter: ch, count: 8)
                            for q in more where !working.rounds[ri].questions.contains(where: { $0.id == q.id }) {
                                insertQuestion(q, into: ri, at: nil)
                            }
                            busy = false
                        }
                    } label: { Label("Fill with \(ch) answers", systemImage: "textformat.abc") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(busy)
                }
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    /// A round's ON/OFF flag, as a chip whose STATE is visible.
    ///
    /// ADVERSARIAL-DESIGN-LEDGER M3, measured: with `.toggleStyle(.button)` an ON
    /// chip and an OFF chip rendered the same pixels — fill (226,231,254), text
    /// (56,90,246) — so "is this a wager round?" was unanswerable from the glass.
    /// ON is now a filled coral pill with a filled symbol; OFF is a plain bordered
    /// one. The two menus beside them keep their chevron, so a menu still reads as
    /// a menu and a switch as a switch.
    @ViewBuilder
    private func roundFlagChip(_ title: String, systemImage: String,
                               isOn: Binding<Bool>, help: String) -> some View {
        if isOn.wrappedValue {
            Button { isOn.wrappedValue = false } label: {
                Label(title, systemImage: systemImage + ".fill")
            }
            .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
            .fixedSize().help(help)
            .accessibilityAddTraits(.isSelected)
        } else {
            Button { isOn.wrappedValue = true } label: {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(CompactButtonStyle())
            .fixedSize().help(help)
        }
    }

    private func questionRow(_ ri: Int, _ qi: Int, _ q: Question, format: GameMode) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(qi + 1).")
                .font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                // ADVERSARIAL-DESIGN-LEDGER M1: `lineLimit(2)` cut 3 of 5 prompts in one
                // round mid-sentence ("…impeached for corruption,…"), so a host could not
                // proof-read their own night. A question is the row's whole point; it wraps.
                Text(q.prompt.isEmpty ? "Untitled question" : q.prompt)
                    .font(.body).foregroundStyle(Tidbits.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(answerSummary(q, format: format))
                    .font(.caption).foregroundStyle(Tidbits.Palette.inkSoft).lineLimit(1)
                let qTimer = LiveEvent.override(working.rounds[ri].questionTimers, qi)
                let qPoints = LiveEvent.override(working.rounds[ri].questionPoints, qi)
                if qTimer != nil || qPoints != nil {   // A2.8: this question's own timer / points
                    HStack(spacing: 8) {
                        if let t = qTimer { Label("\(t) s", systemImage: "timer") }
                        if let pts = qPoints { Label("\(pts) pt\(pts == 1 ? "" : "s")", systemImage: "star.fill") }
                    }
                    .font(.caption).foregroundStyle(Tidbits.Palette.blue)
                }
                if let e = played.entry(q.id) {   // A2.6: the room has heard this one
                    Label(LivePlayedLog.askedLine(e), systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(Tidbits.Palette.coral).lineLimit(1)
                        .accessibilityIdentifier("live.askedBefore")
                }
            }
            Spacer(minLength: 8)
            Text("D\(q.difficulty)")
                .font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
            Button("Edit") {
                editing = EditingQuestion(roundIndex: ri, questionIndex: qi, format: format,
                                          draft: draftFor(ri, qi))
            }
            .controlSize(.small)
            Menu {
                Button("Save to library") {
                    let new = library.add(q, source: working.name)
                    fileReceipt = new ? "Saved to your library (\(library.items.count))" : "Already in your library — updated"
                }
                Button("Duplicate") { insertQuestion(q.duplicatedForEditing(), into: ri, at: qi + 1) }
                Button("Swap for a fresh one") { Task { await swapForFresh(ri, qi) } }.disabled(busy)
                Menu("Timer for this question") {   // A2.8
                    Button("Round default") { setOverride(ri, qi, timer: 0) }
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { secs in
                        Button("\(secs) seconds") { setOverride(ri, qi, timer: secs) }
                    }
                }
                Menu("Points for this question") {
                    Button("Night default") { setOverride(ri, qi, points: 0) }
                    ForEach([1, 2, 3, 5, 10], id: \.self) { pts in
                        Button("\(pts) point\(pts == 1 ? "" : "s")") { setOverride(ri, qi, points: pts) }
                    }
                }
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
            editing = EditingQuestion(roundIndex: ri, questionIndex: qi, format: format, draft: draftFor(ri, qi))
        }
        // Drop a picture, an audio file or a video onto the question (§8.1). The
        // file's KIND decides what it becomes; anything else is refused by name.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in attachDropped(url, ri: ri, qi: qi) }
            }
            return true
        }
    }

    /// The editor draft for a question, with the round's clips named so the
    /// editor can show what is attached (the clips live on the round, §8.1).
    private func draftFor(_ ri: Int, _ qi: Int) -> QuestionDraft {
        var d = QuestionDraft(working.rounds[ri].questions[qi])
        d.audioClipName = clipName(working.rounds[ri].audioBookmarks, qi)
        d.videoClipName = clipName(working.rounds[ri].videoBookmarks, qi)
        return d
    }

    private func clipName(_ marks: [Data]?, _ qi: Int) -> String? {
        guard let marks, marks.indices.contains(qi), !marks[qi].isEmpty,
              let url = try? LiveClip.resolve(marks[qi]) else { return nil }
        if let id = LiveMediaStore.id(forStoreFile: url) {
            return LiveMediaStore.info(id)?.originalName ?? url.lastPathComponent
        }
        url.stopAccessingSecurityScopedResource()
        return url.lastPathComponent
    }

    /// Put an editor's clip decision onto the round, keeping the bookmark array
    /// index-parallel with the questions (a missing array is created on first use).
    private func applyClip(_ change: QuestionDraft.ClipChange, video: Bool, ri: Int, qi: Int) {
        guard working.rounds.indices.contains(ri), case let count = working.rounds[ri].questions.count, qi < count else { return }
        var marks = (video ? working.rounds[ri].videoBookmarks : working.rounds[ri].audioBookmarks) ?? []
        switch change {
        case .keep: return
        case .remove:
            if marks.indices.contains(qi) { marks[qi] = Data() }
        case .set(let id):
            while marks.count < count { marks.append(Data()) }
            guard let url = LiveMediaStore.fileURL(id), let mark = try? LiveClip.bookmark(for: url) else {
                presentError("Could not attach that clip", NSError(domain: "LiveClip", code: 2,
                             userInfo: [NSLocalizedDescriptionKey: "The clip is not in the media store."]))
                return
            }
            marks[qi] = mark
        }
        let value: [Data]? = marks.contains(where: { !$0.isEmpty }) ? marks : nil
        if video { working.rounds[ri].videoBookmarks = value } else { working.rounds[ri].audioBookmarks = value }
    }

    private func attachDropped(_ url: URL, ri: Int, qi: Int) {
        guard working.rounds.indices.contains(ri), working.rounds[ri].questions.indices.contains(qi) else { return }
        let ext = LiveMediaStore.normalizedExt(url.pathExtension)
        guard let kind = LiveMediaStore.allowed[ext] else {
            presentError("Could not use \(url.lastPathComponent)", NSError(domain: "LiveMediaStore", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Drop a picture, an audio file or a video."]))
            return
        }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let id = try LiveMediaStore.store(try Data(contentsOf: url), ext: ext, originalName: url.lastPathComponent)
            switch kind.kind {
            case "image": working.rounds[ri].questions[qi].imageURL = LiveMediaStore.reference(id)
            case "audio": applyClip(.set(id: id), video: false, ri: ri, qi: qi)
            default: applyClip(.set(id: id), video: true, ri: ri, qi: qi)
            }
        } catch { presentError("Could not use \(url.lastPathComponent)", error) }
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
        syncOverrides(ri, insertAt: at)
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

    /// A2.8: keep the per-question override arrays index-parallel with the
    /// questions through insert / remove / move, the way the clips are kept.
    private func syncOverrides(_ ri: Int, insertAt: Int? = nil, removeAt: Int? = nil, swap: (Int, Int)? = nil) {
        func fix(_ list: inout [Int]?) {
            guard var l = list else { return }
            if let at = insertAt { l.insert(0, at: min(at, l.count)) }
            if let at = removeAt, l.indices.contains(at) { l.remove(at: at) }
            if let (a, b) = swap, l.indices.contains(a), l.indices.contains(b) { l.swapAt(a, b) }
            list = l.contains(where: { $0 > 0 }) ? l : nil
        }
        fix(&working.rounds[ri].questionTimers)
        fix(&working.rounds[ri].questionPoints)
    }

    private func setOverride(_ ri: Int, _ qi: Int, timer: Int? = nil, points: Int? = nil) {
        guard working.rounds.indices.contains(ri) else { return }
        let count = working.rounds[ri].questions.count
        guard qi < count else { return }
        func put(_ list: inout [Int]?, _ v: Int) {
            var l = list ?? []
            while l.count < count { l.append(0) }
            l[qi] = v
            list = l.contains(where: { $0 > 0 }) ? l : nil
        }
        if let timer { put(&working.rounds[ri].questionTimers, timer) }
        if let points { put(&working.rounds[ri].questionPoints, points) }
    }

    private func removeQuestion(_ ri: Int, at qi: Int) {
        guard working.rounds.indices.contains(ri), working.rounds[ri].questions.indices.contains(qi) else { return }
        working.rounds[ri].questions.remove(at: qi)
        syncOverrides(ri, removeAt: qi)
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
        syncOverrides(ri, swap: (from, to))
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
            .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
            .keyboardShortcut("r", modifiers: .command)
            .disabled(busy)
            .help("Draw a round from the Tidbits question bank (⌘R)")
            if busy { ProgressView().controlSize(.small) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chunkyCard(fill: Tidbits.Palette.bgDeep)
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
    // MARK: File panels — the one seam that makes them testable
    //
    // Every import/export ran `panel.runModal()` inline, so the whole path from
    // the button to the file on disk was undrivable: a modal panel is not
    // scriptable, and the QA harness had no scenario for print, export, import or
    // save-load at all. The BEHAVIOUR (encode/decode/parse) was well covered; the
    // EDGE was not covered anywhere.
    //
    // TIDBITS_LIVE_FILE=<path> hands the panel its answer, so the harness drives
    // the real code path and a real file lands on disk. No-op in production, where
    // the environment variable is absent and the panel runs exactly as before.
    private func panelURL() -> URL? {
        guard let p = ProcessInfo.processInfo.environment["TIDBITS_LIVE_FILE"], !p.isEmpty
        else { return nil }
        // The Mac app is SANDBOXED, so it cannot write to an arbitrary path the
        // harness picks — outside the container only a real panel grant opens a
        // file, which is the whole reason this edge was undrivable. A bare
        // filename therefore resolves inside the app's own Documents directory,
        // which is always writable; the harness reads it back from the container.
        // An absolute path is honoured as-is and will fail under the sandbox
        // exactly as it would in production, which is the truthful behaviour.
        if p.contains("/") { return URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(p)
    }

    private func chooseSaveURL(named: String, types: [UTType]) -> URL? {
        if let hooked = panelURL() { return hooked }
        let panel = NSSavePanel()
        panel.allowedContentTypes = types
        panel.nameFieldStringValue = named
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func chooseOpenURL(types: [UTType]) -> URL? {
        if let hooked = panelURL() { return hooked }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func exportEvent() {
        guard let url = chooseSaveURL(named: LiveEventFile.suggestedFilename(for: working),
                                      types: [.json]) else { return }
        do {
            try LiveEventFile.write(working, to: url)
            fileReceipt = "Exported \(working.rounds.count) rounds, \(working.totalQuestions) questions"
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

    private func consumePendingPackage() {
        guard let url = appStore.pendingPackageURL else { return }
        appStore.pendingPackageURL = nil
        // LaunchServices grants the sandbox access to a file the user opened; the
        // scope must still be claimed to read it.
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let (ev, problems) = try LivePackage.importIntoStore(try Data(contentsOf: url))
            fileReceipt = "Imported package: \(ev.rounds.count) rounds, \(ev.totalQuestions) questions"
            working = ev
            store.upsert(ev)
            selectedID = ev.id
            expandedRounds = []
            if !problems.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Imported with \(problems.count) problem\(problems.count == 1 ? "" : "s")"
                alert.informativeText = problems.prefix(6).joined(separator: "\n")
                alert.alertStyle = .warning
                alert.runModal()
            }
        } catch { presentError("Could not open \(url.lastPathComponent)", error) }
    }

    /// The whole library as a `bank` package: the same container, rounds as
    /// category folders, media inside (LIVE-PACKAGE-FORMAT §6).
    private func exportLibrary() {
        let type = UTType(filenameExtension: LivePackage.fileExtension, conformingTo: .zip) ?? .zip
        let bank = LiveLibrary.bankEvent(library.items, name: "Question library")
        guard let url = chooseSaveURL(named: "Question library.\(LivePackage.fileExtension)", types: [type]) else { return }
        do {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            _ = try LivePackage.write(bank, to: url, createdBy: "Tidbits Trivia (macOS) \(version)", kind: "bank")
            fileReceipt = "Exported your library: \(library.items.count) questions in \(bank.rounds.count) categories"
        } catch { presentError("Could not export the library", error) }
    }

    /// Write the night as ONE file with its media inside (LIVE-PACKAGE-FORMAT).
    private func exportPackage() {
        let type = UTType(filenameExtension: LivePackage.fileExtension, conformingTo: .zip) ?? .zip
        guard let url = chooseSaveURL(named: LivePackage.suggestedFilename(for: working), types: [type]) else { return }
        do {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let dropped = try LivePackage.write(working, to: url, createdBy: "Tidbits Trivia (macOS) \(version)")
            fileReceipt = "Exported package: \(working.rounds.count) rounds, \(working.totalQuestions) questions"
            if !dropped.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Exported without \(dropped.count) clip\(dropped.count == 1 ? "" : "s")"
                alert.informativeText = "These could not be read from disk, so they are not in the package:\n" + dropped.prefix(6).joined(separator: "\n")
                alert.alertStyle = .informational
                alert.runModal()
            }
        } catch { presentError("Could not export the package", error) }
    }

    /// Read an event back — a `.tidbits` package (media and all) or the bare JSON
    /// document. The imported event gets a NEW id so importing a co-host's copy
    /// adds a night rather than silently overwriting one of yours.
    private func importEvent() {
        let pkg = UTType(filenameExtension: LivePackage.fileExtension, conformingTo: .zip) ?? .zip
        guard let url = chooseOpenURL(types: [pkg, .json, .zip]) else { return }
        do {
            let ev: LiveEvent
            var problems: [String] = []
            if LivePackage.isPackage(url) || (try? LivePackage.read(try Data(contentsOf: url))) != nil {
                let data = try Data(contentsOf: url)
                // A BANK goes into the library, not the list of nights (§6.1).
                if (try? LivePackage.read(data).manifest.kind) == "bank" {
                    let (bank, bankProblems) = try LivePackage.importIntoStore(data)
                    let n = library.add(bank.questionStream.map { var q = $0; q.roundIndex = nil; return q },
                                        source: bank.name.isEmpty ? url.lastPathComponent : bank.name)
                    fileReceipt = "Imported bank into your library: \(n) new, \(bank.totalQuestions - n) already there"
                    if !bankProblems.isEmpty { presentError("Imported with problems", NSError(domain: "LivePackage", code: 1, userInfo: [NSLocalizedDescriptionKey: bankProblems.prefix(6).joined(separator: "\n")])) }
                    return
                }
                (ev, problems) = try LivePackage.importIntoStore(data)
                fileReceipt = "Imported package: \(ev.rounds.count) rounds, \(ev.totalQuestions) questions"
            } else {
                ev = try LiveEventFile.read(from: url)
                fileReceipt = "Imported \(ev.rounds.count) rounds, \(ev.totalQuestions) questions"
            }
            working = ev
            store.upsert(ev)
            selectedID = ev.id
            expandedRounds = []
            if !problems.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Imported with \(problems.count) problem\(problems.count == 1 ? "" : "s")"
                alert.informativeText = problems.prefix(6).joined(separator: "\n")
                alert.alertStyle = .warning
                alert.runModal()
            }
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
        guard let url = chooseSaveURL(named: "\(working.name) — questions.csv",
                                      types: [.commaSeparatedText]) else { return }
        do {
            try Data(LiveCSV.exportCSV(working.questionStream).utf8).write(to: url, options: .atomic)
            fileReceipt = "Exported \(working.totalQuestions) questions as CSV"
        } catch {
            presentMessage("Could not export the questions", error.localizedDescription)
        }
    }

    /// Kahoot's own import template, so a host can hand a Tidbits night to someone
    /// who runs Kahoot (QUIZ-FORMATS-RESEARCH §4). Their importer takes only xlsx.
    private func exportKahootSheet() {
        let type = UTType(filenameExtension: "xlsx") ?? .data
        guard let url = chooseSaveURL(named: "\(working.name) — for Kahoot.xlsx", types: [type]) else { return }
        // One timer for the whole sheet: Kahoot allows a per-question time, but a
        // Tidbits round has ONE, so the first round's timer is the honest source.
        let (rows, notes) = LiveKahootSheet.rows(for: working.questionStream,
                                                 seconds: working.rounds.first?.timerSeconds)
        guard !rows.isEmpty else {
            presentMessage("Nothing to export for Kahoot",
                           "Kahoot's sheet only carries multiple-choice questions with two to four answers."
                           + (notes.isEmpty ? "" : "\n\n" + notes.prefix(6).joined(separator: "\n")))
            return
        }
        do {
            try LiveKahootSheet.xlsx(rows).write(to: url, options: .atomic)
            fileReceipt = "Exported \(rows.count) questions for Kahoot"
            if !notes.isEmpty {
                presentMessage("Exported \(rows.count) of \(working.totalQuestions) questions",
                               notes.prefix(8).joined(separator: "\n"))
            }
        } catch { presentMessage("Could not export for Kahoot", error.localizedDescription) }
    }

    /// A SpeedQuizzing quizpack is a FOLDER whose filenames are the questions and
    /// whose files are the media (QUIZ-FORMATS-RESEARCH §1). Each picture, MP3 or
    /// clip lands in the media store, so the round exports as a `.tidbits` package
    /// with the media inside — the whole point of the format.
    private func importQuickQuestions() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        let picked: URL?
        if let p = ProcessInfo.processInfo.environment["TIDBITS_LIVE_QQFOLDER"], !p.isEmpty {
            picked = p.contains("/") ? URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
                : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(p)
        } else {
            picked = panel.runModal() == .OK ? panel.url : nil
        }
        guard let folder = picked else { return }
        let granted = folder.startAccessingSecurityScopedResource()
        defer { if granted { folder.stopAccessingSecurityScopedResource() } }
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            presentMessage("Could not read “\(folder.lastPathComponent)”", "Tidbits could not list that folder.")
            return
        }
        let store: (URL) throws -> String? = { url in
            try LiveMediaStore.store(try Data(contentsOf: url), ext: url.pathExtension, originalName: url.lastPathComponent)
        }
        let (qs, notes) = LiveQuickQuestions.questions(from: files, store: store)
        guard !qs.isEmpty else {
            presentMessage("No Quick Questions in “\(folder.lastPathComponent)”",
                           "A Quick Question is a file whose NAME is the question and answer, separated by "
                           + "underscores — for example “QQ_Who sang this^^_Dolly Parton.mp3”."
                           + (notes.isEmpty ? "" : "\n\n" + notes.prefix(6).joined(separator: "\n")))
            return
        }
        let clips = LiveQuickQuestions.clipIDs(from: files, store: store)
        var round = LiveRound(title: folder.lastPathComponent, format: .typeAnswer, categoryID: "mixed", questions: qs)
        // The clip arrays stay index-parallel with the questions (§3.2).
        let marks: [Data] = clips.prefix(qs.count).map { id in
            guard let id, let url = LiveMediaStore.fileURL(id), let m = try? LiveClip.bookmark(for: url) else { return Data() }
            return m
        }
        if marks.contains(where: { !$0.isEmpty }) {
            round.audioBookmarks = marks + Array(repeating: Data(), count: max(0, qs.count - marks.count))
        }
        working.rounds.append(round)
        let pictured = qs.filter { $0.imageURL != nil }.count
        let clipped = marks.filter { !$0.isEmpty }.count
        fileReceipt = "Imported \(qs.count) Quick Questions (\(pictured) with pictures, \(clipped) with clips)"
        if !notes.isEmpty {
            presentMessage("Imported with \(notes.count) note\(notes.count == 1 ? "" : "s")", notes.prefix(8).joined(separator: "\n"))
        }
    }

    /// GIFT: the human-writable archive form (QUIZ-FORMATS-RESEARCH §4) — every
    /// type but ordering round-trips through Moodle and any text editor.
    private func exportQuestionsGIFT() {
        guard let url = chooseSaveURL(named: "\(working.name) — questions.gift.txt", types: [.plainText]) else { return }
        do {
            try Data(LiveTextFormats.exportGIFT(working.questionStream).utf8).write(to: url, options: .atomic)
            fileReceipt = "Exported \(working.totalQuestions) questions as GIFT"
        } catch { presentMessage("Could not export the questions", error.localizedDescription) }
    }

    /// Wave A: CSV import — bulk-author a round from a host's question bank.
    /// Columns: prompt, correct, wrong1, wrong2, wrong3, [category], [difficulty 1-5], [explanation].
    private func importCSV() {
        guard let url = chooseOpenURL(types: [.commaSeparatedText, .plainText, .text]) else { return }
        guard let text = LiveCSV.readTextFile(at: url) else {
            presentMessage("Could not read “\(url.lastPathComponent)”",
                           "Tidbits tried UTF-8, UTF-16 and Latin-1 and none of them decoded the file. "
                           + "Re-save it from your spreadsheet as CSV (UTF-8).")
            return
        }
        // The text says what it is: Aiken's ANSWER: lines, GIFT's {…} blocks, else CSV.
        let kind = LiveTextFormats.detect(text)
        let qs: [Question]
        let kindName: String
        switch kind {
        case .aiken: qs = LiveTextFormats.parseAiken(text); kindName = "Aiken"
        case .gift: qs = LiveTextFormats.parseGIFT(text); kindName = "GIFT"
        case .csv: qs = LiveCSV.parseCSVQuestions(text); kindName = "CSV"
        }
        guard !qs.isEmpty else {
            // A silent return here is how a host's CSV "imports" and nothing appears.
            presentMessage("No questions in “\(url.lastPathComponent)”",
                           kind == .csv
                           ? "Each row needs at least: prompt, correct answer, and three wrong answers. "
                             + "Optional extras follow: category, difficulty 1-5, explanation. A named header row "
                             + "(including another tool's, like Kahoot's or Crowdpurr's) is read by name."
                           : "Tidbits read this as \(kindName) but found no answerable questions in it.")
            return
        }
        // One format per round: the one the questions share, else classic.
        let format: GameMode = qs.allSatisfy { $0.accepted != nil } ? .typeAnswer
            : qs.allSatisfy { $0.closest != nil } ? .closestCall
            : qs.allSatisfy { $0.matching != nil } ? .matching : .classic
        working.rounds.append(LiveRound(title: url.deletingPathExtension().lastPathComponent, format: format,
                                        categoryID: "mixed", questions: qs))
        // Name the format the file actually WAS: a GIFT import reporting "from CSV"
        // is a false receipt, and the receipt is the only thing the host reads.
        fileReceipt = "Imported \(qs.count) questions from \(kindName)"
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
    /// G5: add a pick-your-category board round. Only categories the corpus can
    /// fill at EVERY tier are offered — a column with a hole in it is a cell the
    /// room can pick and the host cannot read.
    private func addBoardRound() {
        Task {
            busy = true
            let pool = await QuestionProvider.shared.questions(mode: .classic, category: .named("mixed"))
            let fillable = LiveBoardBuilder.fillableCategories(in: pool)
            let chosen = Array((fillable.isEmpty ? TriviaCategory.all.dropFirst().map(\.id) : fillable).prefix(5))
            var round = await LiveEventStore.buildBoardRound(categories: chosen)
            round.title = "Pick a Category"
            working.rounds.append(round)
            expandedRounds.insert(round.id)
            busy = false
        }
    }

    /// TIDBITS_LIVE_CLIPS=<path>[:<path>…] — the clips a harness would have picked.
    ///
    /// Same seam as the import/export panels: a modal picker is not scriptable, so
    /// an AV round could be built by hand and never once driven end to end. The
    /// REST of the path is unchanged — the bookmark is still made the same way and
    /// still refused the same way, which is the part that decides whether a clip
    /// plays. No-op in production, where the variable is unset.
    private func hookedClipURLs() -> [URL]? {
        guard let raw = ProcessInfo.processInfo.environment["TIDBITS_LIVE_CLIPS"], !raw.isEmpty
        else { return nil }
        let urls = raw.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        return urls.isEmpty ? nil : urls
    }

    private func addAudioRound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav, .mpeg4Audio, .aiff]
        panel.allowsMultipleSelection = true
        // A harness can point the panel at a known folder so it only has to choose
        // the file; a person never sees this because the variable is unset.
        if let dir = ProcessInfo.processInfo.environment["TIDBITS_LIVE_CLIPDIR"] {
            panel.directoryURL = URL(fileURLWithPath: dir)
        }
        let picked: [URL]
        if let hooked = hookedClipURLs() { picked = hooked }
        else { guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }; picked = panel.urls }
        var questions: [Question] = []
        var bookmarks: [Data] = []
        var failures: [String] = []
        for (i, url) in picked.enumerated() {
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
        let picked: [URL]
        if let hooked = hookedClipURLs() { picked = hooked }
        else { guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }; picked = panel.urls }
        var questions: [Question] = []
        var bookmarks: [Data] = []
        var failures: [String] = []
        for (i, url) in picked.enumerated() {
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

    /// A2.7: a copy the host runs as its own night; `fresh` swaps every question
    /// the room has heard for one it has not (a recurring night's regulars are
    /// the same people every week).
    private func duplicateEvent(_ ev: LiveEvent, fresh: Bool) {
        let copy = ev.duplicated(named: ev.cloneName)
        store.upsert(copy)
        working = copy
        selectedID = copy.id
        if fresh { Task { await refreshRepeats() } }
    }

    /// Swap one question for a bank question of the same format and category that
    /// neither the room has heard nor the night already holds. The row stays put.
    private func swapForFresh(_ ri: Int, _ qi: Int) async {
        guard working.rounds.indices.contains(ri), working.rounds[ri].questions.indices.contains(qi) else { return }
        busy = true; defer { busy = false }
        let round = working.rounds[ri]
        let taken = played.ids.union(working.questionStream.map(\.id))
        let drawn = await LiveEventStore.buildRound(format: round.format, category: .named(round.categoryID),
                                                    count: 1, excluding: taken)
        guard let q = drawn.questions.first, !taken.contains(q.id),
              working.rounds.indices.contains(ri), working.rounds[ri].questions.indices.contains(qi) else {
            fileReceipt = "The bank has nothing fresh for this round — every \(round.format.nightRoundTitle.lowercased()) question has been asked."
            return
        }
        working.rounds[ri].questions[qi] = q
    }

    /// Every question the room has heard, in the given rounds (all by default),
    /// swapped for a fresh one. Reports what changed.
    private func refreshRepeats(rounds: [Int]? = nil) async {
        var swapped = 0, stuck = 0
        for ri in rounds ?? Array(working.rounds.indices) where working.rounds.indices.contains(ri) {
            for qi in working.rounds[ri].questions.indices where played.ids.contains(working.rounds[ri].questions[qi].id) {
                let before = working.rounds[ri].questions[qi].id
                await swapForFresh(ri, qi)
                if working.rounds[ri].questions[qi].id != before { swapped += 1 } else { stuck += 1 }
            }
        }
        if swapped + stuck > 0 {
            fileReceipt = swapped == 0 ? "No fresh questions for \(stuck) repeat\(stuck == 1 ? "" : "s") — the bank is spent for those rounds."
                : (swapped == 1 ? "1 question swapped for a fresh one" : "\(swapped) questions swapped for fresh ones") + (stuck > 0 ? " · \(stuck) had nothing fresh left" : "")
        }
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
