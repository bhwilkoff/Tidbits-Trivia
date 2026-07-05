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
                                    let name = [c.fullName?.givenName, c.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                                    Task { await identity.linkApple(idToken: t, rawNonce: appleNonce, appleName: name.isEmpty ? nil : name, appleEmail: c.email) }
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
                Section("Leaderboard") {   // Wave E: cross-venue / season standings
                    NavigationLink("Cross-venue standings") { LeaderboardView_tvOS() }
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

/// Wave E: the cross-venue / season leaderboard on the TV — reuses the shared Core fetcher.
struct LeaderboardView_tvOS: View {
    @State private var overall: [LeaderboardRow] = []
    @State private var venues: [(venue: String, rows: [LeaderboardRow])] = []
    @State private var myUid = ""
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if overall.isEmpty && venues.isEmpty {
                Text("No standings yet. Play a live Tidbits night while signed in and the board fills in here — it refreshes hourly.")
                    .foregroundStyle(TVTheme.textSoft)
            } else {
                Section {   // L3 seasons: the fresh-start banner
                    HStack {
                        Text(PlayerIdentity.seasonDisplay(PlayerIdentity.currentSeason())).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        Text("Resets in \(PlayerIdentity.seasonResetDays()) days").foregroundStyle(TVTheme.textSoft)
                    }
                }
                if !overall.isEmpty {
                    Section("This season · Overall") { ForEach(Array(overall.enumerated()), id: \.element.id) { row($0.offset, $0.element) } }
                }
                ForEach(venues, id: \.venue) { v in
                    Section(v.venue) { ForEach(Array(v.rows.enumerated()), id: \.element.id) { row($0.offset, $0.element) } }
                }
            }
        }
        .navigationTitle("Leaderboard")
        .task { await load() }
    }

    private func row(_ i: Int, _ r: LeaderboardRow) -> some View {
        let mine = !myUid.isEmpty && r.uid == myUid   // Wave E: defendable titles
        return HStack(spacing: 18) {
            Text("\(i + 1)").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(i == 0 ? Color.white : TVTheme.textSoft).frame(width: 50, alignment: .leading)
            if i == 0 { Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow) }
            Text(r.name).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            if mine { Text("YOU").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.blue) }
            if i == 0 { Text("CHAMPION").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.coral) }
            Spacer()
            Text("\(r.score)").font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(.white)
        }
        .padding(.vertical, 6)
    }

    private func load() async {
        myUid = await FirebaseRTDB.shared.uid ?? ""
        let idx = await LeaderboardAPI.index()
        guard let season = idx.keys.sorted().last else { loading = false; return }
        overall = await LeaderboardAPI.overall(season: season)
        var vs: [(venue: String, rows: [LeaderboardRow])] = []
        for venue in (idx[season] ?? []).sorted() {
            let rows = await LeaderboardAPI.venue(season: season, venue: venue)
            if !rows.isEmpty { vs.append((venue, rows)) }
        }
        venues = vs
        loading = false
    }
}
#endif
