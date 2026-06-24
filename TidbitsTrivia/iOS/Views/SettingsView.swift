#if os(iOS)
import SwiftUI
import SwiftData

/// Settings — a sheet behind a toolbar gear, not a tab (the tab bar is for
/// content verbs). Native Form is the right idiom here (native-platform-first).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(GameCenterManager.self) private var gameCenter
    @AppStorage(Haptics.defaultsKey) private var hapticsEnabled = true
    @AppStorage(GameSettings.reviewKey) private var reviewEnabled = true
    @State private var confirmReset = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Feedback") {
                    Toggle("Haptics", isOn: $hapticsEnabled)
                }
                Section {
                    Toggle("Review questions", isOn: $reviewEnabled)
                } header: {
                    Text("Gameplay")
                } footer: {
                    Text("Occasionally re-asks questions you've missed, spaced out, so they stick. Turn off to only ever see new questions.")
                }
                Section("Game Center") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(gameCenter.isAuthenticated ? "Signed in" : "Not signed in")
                            .foregroundStyle(.secondary)
                    }
                    if gameCenter.isAuthenticated {
                        Button("Leaderboards & Achievements") { gameCenter.showDashboard() }
                    }
                }
                Section("Data") {
                    Button("Reset Seen Questions") { QuestionProvider.shared.resetSeen() }
                    Button("Reset All Records", role: .destructive) { confirmReset = true }
                }
                Section("About") {
                    LabeledContent("Version", value: version)
                    Link(destination: URL(string: "https://www.wikipedia.org")!) {
                        Label("Questions from Wikipedia", systemImage: "globe")
                    }
                    Text("Content from Wikipedia, available under CC BY-SA. Tidbits is a learning game — every question is a door to learn more.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .tint(Tidbits.Palette.blue)
            .confirmationDialog("Reset all records?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset Everything", role: .destructive) { resetAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your scores, streaks, and review list.")
            }
        }
    }

    private func resetAll() {
        try? modelContext.delete(model: GameRecord.self)
        try? modelContext.delete(model: MissedFact.self)
        try? modelContext.delete(model: DailyStreak.self)
        try? modelContext.delete(model: CalibrationTally.self)
        try? modelContext.save()
        QuestionProvider.shared.resetSeen()
    }
}
#endif
