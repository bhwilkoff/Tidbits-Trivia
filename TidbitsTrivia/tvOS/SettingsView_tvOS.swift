#if os(tvOS)
import SwiftUI
import SwiftData
import AuthenticationServices

/// tvOS Settings — parity with the iOS sheet, ten-foot and focus-driven.
/// Native Form works on tvOS and gives free focus + section semantics
/// (native-platform-first). Haptics is n/a on Apple TV; the rest mirrors iOS:
/// Review toggle (its home, moved off the cluttered home header), reset,
/// Game Center status, attribution.
struct SettingsView_tvOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(GameCenterManager.self) private var gameCenter
    @Environment(PlayerIdentityStore.self) private var identity
    @AppStorage(GameSettings.reviewKey) private var reviewEnabled = true
    @State private var confirmReset = false
    @State private var appleNonce = ""

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
                Section("Profile") {
                    if let p = identity.profile {
                        HStack(spacing: 20) {
                            Circle().fill(Color(hue: PlayerIdentity.avatarHue(p.avatarSeed), saturation: 0.55, brightness: 0.85))
                                .overlay(Text(PlayerIdentity.initials(p.name)).font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(.black))
                                .frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.headline)
                                Text("Rating \(Int(p.rating.value)) · \(p.streak.current)-day streak").foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent("Games played", value: "\(p.stats.gamesPlayed)")
                        LabeledContent("Live nights", value: "\(p.stats.liveNights)")
                        if identity.signedIn {
                            Label("Signed in — records sync to every device", systemImage: "checkmark.seal.fill").foregroundStyle(.secondary)
                            Button("Sign out") { Task { await identity.signOut() } }
                        } else {
                            SignInWithAppleButton(.signIn) { req in
                                appleNonce = AppleNonce.random(); req.requestedScopes = [.email, .fullName]; req.nonce = AppleNonce.sha256(appleNonce)
                            } onCompletion: { result in
                                if case .success(let auth) = result, let c = auth.credential as? ASAuthorizationAppleIDCredential,
                                   let d = c.identityToken, let t = String(data: d, encoding: .utf8) {
                                    Task { await identity.linkApple(idToken: t, rawNonce: appleNonce) }
                                }
                            }
                            .signInWithAppleButtonStyle(.white).frame(height: 60)
                        }
                    } else {
                        Text("Setting up your profile…").foregroundStyle(.secondary)
                    }
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
