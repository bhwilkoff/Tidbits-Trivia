#if os(iOS)
import SwiftUI

/// iPhone/iPad root. Three content tabs (Play / Records / Create) — the
/// tab bar is reserved for verbs; settings would be a toolbar sheet, not
/// a tab. One NavigationStack per tab, paths owned by AppStore.
struct ContentView_iOS: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var showPaywall = false

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            Tab("Play", systemImage: "play.fill", value: AppStore.Tab.play) {
                NavigationStack(path: $store.playPath) { HomeView() }
            }
            Tab("Records", systemImage: "chart.bar.fill", value: AppStore.Tab.records) {
                NavigationStack(path: $store.recordsPath) { RecordsView() }
            }
            Tab("Create", systemImage: "wand.and.stars", value: AppStore.Tab.create) {
                NavigationStack(path: $store.createPath) { CreateQuizView() }
            }
        }
        .onChange(of: store.inbox) { _, _ in handleInbox() }
        .onAppear {
            DebugHooks.seedRecordsIfRequested(modelContext)
            handleInbox()
            if let tab = DebugHooks.initialTab { store.selectedTab = tab }
        }
        // A sheet set during the first layout pass gets swallowed; a short-delayed task
        // presents it reliably (screenshot observability only).
        .task { if DebugHooks.showPaywall { try? await Task.sleep(for: .milliseconds(400)); showPaywall = true } }
        .task {
            // A relevance sweep is a headless run that happens to need the app: it
            // wants the bundled corpus and the shipped assembly, not the UI.
            if let path = DebugHooks.createSweepPath {
                await QuestionProvider.shared.sweepCreate(
                    path: path, corpusOnly: DebugHooks.createSweepCorpusOnly)
            }
            if let games = DebugHooks.playthroughGames {
                await PlaySweep.run(games: games, modes: DebugHooks.playSweepModes,
                                    categories: DebugHooks.playSweepCategories,
                                    style: PlaySweep.Style(rawValue: DebugHooks.playthroughStyle) ?? .correct)
            }
            if let games = DebugHooks.playSweepGames {
                await QuestionProvider.shared.sweepPlay(
                    games: games, modes: DebugHooks.playSweepModes,
                    categories: DebugHooks.playSweepCategories)
            }
        }
        .sheet(isPresented: $showPaywall) { ClubPaywallView().environment(EntitlementStore.shared) }
    }

    private func handleInbox() {
        for link in store.drainInbox() {
            switch link {
            case .daily:
                store.selectedTab = .play
            case .topic, .category:
                store.selectedTab = .play
            case .quiz(let id):
                // Create owns saved quizzes, so a share link lands there and the
                // view picks the id up from the store (never mutate nav from
                // outside the view tree).
                store.pendingSharedQuizID = id
                store.selectedTab = .create
            }
        }
    }
}
#endif
