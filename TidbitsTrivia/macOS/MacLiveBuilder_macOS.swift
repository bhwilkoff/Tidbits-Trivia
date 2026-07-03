#if os(macOS)
import SwiftUI

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

                Text("Rounds").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                if working.rounds.isEmpty {
                    Text("No rounds yet — add one below.").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                ForEach(Array(working.rounds.enumerated()), id: \.element.id) { i, round in
                    roundRow(i, round)
                }

                addRoundBar

                Divider().overlay(Tidbits.Palette.border).padding(.vertical, 4)
                HStack(spacing: 12) {
                    Button("Save event") { store.upsert(working); selectedID = working.id }
                        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink))
                    Button("Preview solo") { store.upsert(working); onPreview(working) }
                        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.blue, textColor: .white))
                        .disabled(working.totalQuestions == 0)
                    Button("Host live →") { store.upsert(working); onHost(working) }
                        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
                        .disabled(working.totalQuestions == 0)
                    Spacer()
                    Menu {
                        Button("Question pack (host)") { LivePrint.questionPack(working) }
                        Button("Answer sheet (teams)") { LivePrint.answerSheet(working) }
                    } label: { Label("Print…", systemImage: "printer") }
                        .frame(width: 120)
                        .disabled(working.totalQuestions == 0)
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func roundRow(_ i: Int, _ round: LiveRound) -> some View {
        HStack(spacing: 12) {
            Image(systemName: round.symbol).foregroundStyle(round.format.accent.legibleForeground)
                .frame(width: 34, height: 34).background(Circle().fill(round.format.accent))
                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(round.title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Text("\(round.format.title) · \(TriviaCategory.named(round.categoryID).name) · \(round.questions.count) questions")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Spacer()
            Button { move(i, up: true) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless).disabled(i == 0)
            Button { move(i, up: false) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless).disabled(i == working.rounds.count - 1)
            Button { working.rounds.remove(at: i) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
        }
        .padding(14).chunkyCard()
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
