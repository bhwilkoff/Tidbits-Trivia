#if os(iOS)
import SwiftUI

/// iPhone/iPad root. Three content tabs (Play / Records / Create) — the
/// tab bar is reserved for verbs; settings would be a toolbar sheet, not
/// a tab. One NavigationStack per tab, paths owned by AppStore.
struct ContentView_iOS: View {
    @Environment(AppStore.self) private var store

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
            handleInbox()
            if let tab = DebugHooks.initialTab { store.selectedTab = tab }
        }
    }

    private func handleInbox() {
        for link in store.drainInbox() {
            switch link {
            case .daily:
                store.selectedTab = .play
            case .topic, .category:
                store.selectedTab = .play
            }
        }
    }
}
#endif
