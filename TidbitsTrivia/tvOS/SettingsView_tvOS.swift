#if os(tvOS)
import SwiftUI
import SwiftData

/// tvOS Settings — parity with the iOS sheet, ten-foot and focus-driven.
/// Native Form works on tvOS and gives free focus + section semantics
/// (native-platform-first). Haptics is n/a on Apple TV; the rest mirrors iOS:
/// Review toggle (its home, moved off the cluttered home header), reset,
/// Game Center status, attribution.
struct SettingsView_tvOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(GameCenterManager.self) private var gameCenter
    @AppStorage(GameSettings.reviewKey) private var reviewEnabled = true
    @State private var confirmReset = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        ZStack {
            // The Form is transparent in a tvOS fullScreenCover — back it with the
            // opaque dark-first background so the home screen doesn't bleed through.
            TVTheme.bg.ignoresSafeArea()
            NavigationStack {
                Form {
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
                    Text("Questions from Wikipedia, available under CC BY-SA. Tidbits is a learning game — every question is a door to learn more.")
                        .foregroundStyle(.secondary)
                }
                }
                .navigationTitle("Settings")
                .confirmationDialog("Reset all records?", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Reset Everything", role: .destructive) { resetAll() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This permanently deletes your scores, streaks, and review list.")
                }
            }
        }
        .onExitCommand { dismiss() }
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
