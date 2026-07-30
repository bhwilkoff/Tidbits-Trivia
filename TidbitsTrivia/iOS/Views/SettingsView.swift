#if os(iOS)
import SwiftUI
import SwiftData
import AuthenticationServices

/// Settings — a sheet behind a toolbar gear, not a tab (the tab bar is for
/// content verbs). Native Form is the right idiom here (native-platform-first).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(GameCenterManager.self) private var gameCenter
    @Environment(PlayerIdentityStore.self) private var identity
    @AppStorage(Haptics.defaultsKey) private var hapticsEnabled = true
    @AppStorage(GameSettings.reviewKey) private var reviewEnabled = true
    @State private var confirmReset = false
    @State private var appleNonce = ""
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleted = false
    /// TIDBITS_PROFILE=1 pushes Profile on open — the surface that owns Sign in with Apple and
    /// (App Store 5.1.1(v)) Delete Account, so both stay screenshot-verifiable from the CLI.
    @State private var path: [String] = DebugHooks.openProfile ? ["profile"] : []

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    NavigationLink(value: "profile") {
                        HStack(spacing: 12) {
                            if let p = identity.profile {
                                Avatar(seed: p.avatarSeed, initials: ProfileView.initials(p.name)).frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                                    Text("Rating \(Int(p.rating.value)) · \(p.streak.current)-day streak")
                                        .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                                }
                            } else {
                                Text("Your Profile")
                            }
                        }
                    }
                }
                // Sign in with Apple belongs HERE, not only one tap deeper inside Profile.
                // Settings is where every platform's player looks for their account, and macOS
                // and tvOS both put it in Settings — an iPhone that shows a Game Center section
                // and no Apple sign-in reads as "this app has no account".
                Section("Account") {
                    if identity.signedIn {
                        Label("Signed in — your records sync to every device", systemImage: "checkmark.seal.fill")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Sign out") { Task { await identity.signOut() } }
                    } else {
                        SignInWithAppleButton(.signIn) { req in
                            identity.reportAuthError(nil)
                            appleNonce = AppleNonce.random()
                            req.requestedScopes = [.email, .fullName]
                            req.nonce = AppleNonce.sha256(appleNonce)
                        } onCompletion: { result in
                            switch result {
                            case .success(let auth):
                                guard let c = auth.credential as? ASAuthorizationAppleIDCredential,
                                      let d = c.identityToken, let t = String(data: d, encoding: .utf8) else {
                                    identity.reportAuthError("Apple didn't return an identity token — please try again."); return
                                }
                                let name = [c.fullName?.givenName, c.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                                Task { await identity.linkApple(idToken: t, rawNonce: appleNonce, appleName: name.isEmpty ? nil : name, appleEmail: c.email) }
                            case .failure(let err):
                                if (err as? ASAuthorizationError)?.code == .canceled { return }   // user backed out — no error nag
                                identity.reportAuthError("Apple sign-in failed: \((err as NSError).localizedDescription)")
                            }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 44)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        Text("Keeps your records, rating, and streak if you change phones.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let e = identity.authError {
                            Text(e).font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
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
                // App Store 5.1.1(v): account DELETION must be reachable in-app. It already
                // lives in Profile; it belongs beside sign-in too, because that is where a
                // reviewer (and a player) looks for it.
                Section("Delete account") {
                    Button(deleting ? "Deleting…" : "Delete Account…", role: .destructive) { confirmDelete = true }
                        .disabled(deleting)
                    Text("Permanently deletes your Tidbits account and all of its data — profile, rating, streak, Daily history, standings, and friends.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if deleted {
                        Label("Your account was deleted. This iPhone is signed out and starting fresh.", systemImage: "checkmark.circle.fill")
                            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let e = identity.deleteError {
                        Text(e).font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
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
            .navigationDestination(for: String.self) { _ in ProfileView() }
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
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) { Task { await deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. Your profile, rating, streak, Daily history, standings, and friends are permanently deleted.")
            }
        }
    }

    private func deleteAccount() async {
        deleting = true
        if await identity.deleteAccount() {
            resetAll()          // the local SwiftData records are part of "all of its data"
            deleted = true
        }
        deleting = false
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
