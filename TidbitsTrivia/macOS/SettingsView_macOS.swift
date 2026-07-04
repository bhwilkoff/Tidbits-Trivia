#if os(macOS)
import SwiftUI
import SwiftData
import AuthenticationServices

/// Mac Settings (macOS-DESIGN §B1: rides the app menu / ⌘,, never a sidebar
/// row). Native `Form`, reusing the shared GameSettings keys. No haptics on the
/// Mac (that's a touch affordance).
struct SettingsView_macOS: View {
    @Environment(GameCenterManager.self) private var gameCenter
    @Environment(PlayerIdentityStore.self) private var identity
    @Environment(\.modelContext) private var modelContext
    @AppStorage(GameSettings.reviewKey) private var reviewEnabled = true
    @State private var confirmReset = false
    @State private var editingName = false
    @State private var draftName = ""
    @State private var appleNonce = ""

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section("Profile") {
                if let p = identity.profile {
                    HStack(spacing: 12) {
                        profileAvatar(p.avatarSeed, PlayerIdentity.initials(p.name), 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.headline)
                            Text("\(p.streak.current)-day streak · \(p.stats.gamesPlayed) games").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Rename…") { draftName = p.name; editingName = true }
                    }
                    let acc = p.stats.questionsAnswered > 0 ? p.stats.correct * 100 / p.stats.questionsAnswered : 0
                    LabeledContent("Tidbits Rating", value: p.rating.provisional ? "\(Int(p.rating.value)) · provisional" : "\(Int(p.rating.value))")
                    LabeledContent("Accuracy", value: "\(acc)%")
                    LabeledContent("Live nights", value: "\(p.stats.liveNights)")
                    if identity.signedIn {
                        Label("Signed in — records sync to every device", systemImage: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Sign out") { Task { await identity.signOut() } }
                    } else {
                        SignInWithAppleButton(.signIn) { req in
                            appleNonce = AppleNonce.random(); req.requestedScopes = [.email, .fullName]; req.nonce = AppleNonce.sha256(appleNonce)
                        } onCompletion: { result in
                            if case .success(let auth) = result, let c = auth.credential as? ASAuthorizationAppleIDCredential,
                               let d = c.identityToken, let t = String(data: d, encoding: .utf8) {
                                let name = [c.fullName?.givenName, c.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                                Task { await identity.linkApple(idToken: t, rawNonce: appleNonce, appleName: name.isEmpty ? nil : name) }
                            }
                        }
                        .signInWithAppleButtonStyle(.black).frame(height: 36)
                    }
                } else {
                    Text("Setting up your profile…").foregroundStyle(.secondary)
                }
            }
            Section("Gameplay") {
                Toggle("Review questions", isOn: $reviewEnabled)
                Text("Occasionally re-asks questions you've missed, spaced out, so they stick. Turn off to only ever see new questions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Game Center") {
                LabeledContent("Status", value: gameCenter.isAuthenticated ? "Signed in" : "Not signed in")
                Button("Leaderboards & Achievements") { gameCenter.showDashboard() }
                    .disabled(!gameCenter.isAuthenticated)
            }
            Section("Data") {
                Button("Reset Seen Questions") { QuestionProvider.shared.resetSeen() }
                Button("Reset All Records…", role: .destructive) { confirmReset = true }
            }
            Section("About") {
                LabeledContent("Version", value: version)
                Link("Wikipedia", destination: URL(string: "https://www.wikipedia.org")!)
                Text("Content from Wikipedia, available under CC BY-SA. Tidbits is a learning game — every question is a door to learn more.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .confirmationDialog("Reset everything?", isPresented: $confirmReset) {
            Button("Reset Everything", role: .destructive) { resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your scores, streaks, and review list.")
        }
        .alert("Display name", isPresented: $editingName) {
            TextField("Name", text: $draftName)
            Button("Save") { Task { await identity.rename(draftName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The name other players and venues see on leaderboards.")
        }
    }

    /// A deterministic seeded avatar — shared shape with the iOS profile.
    private func profileAvatar(_ seed: String, _ initials: String, _ size: CGFloat) -> some View {
        Circle().fill(Color(hue: PlayerIdentity.avatarHue(seed), saturation: 0.55, brightness: 0.85))
            .overlay(Circle().strokeBorder(Tidbits.Palette.ink, lineWidth: 2))
            .overlay(Text(initials).font(.system(size: size / 2.6, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink))
            .frame(width: size, height: size)
    }

    private func resetAll() {
        try? modelContext.delete(model: GameRecord.self)
        try? modelContext.delete(model: DailyStreak.self)
        try? modelContext.delete(model: MissedFact.self)
        try? modelContext.delete(model: CalibrationTally.self)
        try? modelContext.save()
        QuestionProvider.shared.resetSeen()
    }
}
#endif
