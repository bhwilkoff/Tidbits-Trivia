#if os(iOS)
import SwiftUI
import AuthenticationServices

/// The player's portable Tidbits identity, rendered native-iOS (chunky sticker cards).
/// Reads `PlayerIdentityStore` — the ONE shared profile that spans solo + live — and
/// surfaces the Apple-native pieces (Game Center) alongside it. Reached from Settings.
struct ProfileView: View {
    @Environment(PlayerIdentityStore.self) private var identity
    @Environment(GameCenterManager.self) private var gameCenter
    @State private var editingName = false
    @State private var draftName = ""
    @State private var appleNonce = ""

    var body: some View {
        ScrollView {
            if let p = identity.profile {
                VStack(spacing: 16) {
                    header(p)
                    ratingCard(p.rating)
                    streakCard(p.streak)
                    statsGrid(p.stats)
                    NavigationLink { LeaderboardView() } label: {   // Wave E: cross-venue / season standings
                        Label("Leaderboard", systemImage: "trophy.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink))
                    if gameCenter.isAuthenticated {
                        Button { gameCenter.showDashboard() } label: {
                            Label("Game Center — Leaderboards & Achievements", systemImage: "gamecontroller.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.blue, textColor: .white))
                    }
                    saveProgress
                }
                .padding(Tidbits.Metric.pad)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Setting up your profile…").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                .frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .background(Tidbits.Palette.bg)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Display name", isPresented: $editingName) {
            TextField("Name", text: $draftName)
            Button("Save") { Task { await identity.rename(draftName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is the name other players and venues see on leaderboards.")
        }
    }

    private func header(_ p: PlayerIdentity.Profile) -> some View {
        VStack(spacing: 12) {
            Avatar(seed: p.avatarSeed, initials: Self.initials(p.name)).frame(width: 96, height: 96)
                .onTapGesture { Task { await identity.rerollAvatar() } }   // L4 cosmetics
            Text("Tap your avatar to shuffle its color").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
            Button { draftName = p.name; editingName = true } label: {
                HStack(spacing: 6) {
                    Text(p.name).font(Tidbits.TypeRamp.l1).foregroundStyle(Tidbits.Palette.ink)
                    Image(systemName: "pencil").font(.system(size: 15, weight: .bold)).foregroundStyle(Tidbits.Palette.inkSoft)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }

    private func ratingCard(_ r: PlayerIdentity.Rating) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TIDBITS RATING").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                Text(r.provisional ? "Provisional · \(r.games)/\(PlayerIdentity.Rating.establishedAt) games" : "\(r.games) games rated")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Spacer()
            Text("\(Int(r.value))").font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(Tidbits.Palette.ink)
        }
        .padding(16).frame(maxWidth: .infinity).chunkyCard(fill: Tidbits.Palette.surface)
    }

    private func streakCard(_ s: PlayerIdentity.Streak) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("STREAK").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                Text("Longest \(s.longest) · \(s.freezes) freeze\(s.freezes == 1 ? "" : "s")")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").font(.system(size: 26)).foregroundStyle(Tidbits.Palette.coral)
                Text("\(s.current)").font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(Tidbits.Palette.ink)
            }
        }
        .padding(16).frame(maxWidth: .infinity).chunkyCard(fill: Tidbits.Palette.surface)
    }

    private func statsGrid(_ st: PlayerIdentity.Stats) -> some View {
        let accuracy = st.questionsAnswered > 0 ? Int(Double(st.correct) / Double(st.questionsAnswered) * 100) : 0
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile("Games", "\(st.gamesPlayed)")
            statTile("Accuracy", "\(accuracy)%")
            statTile("Live nights", "\(st.liveNights)")
            statTile("Venues", "\(st.venuesVisited)")
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(Tidbits.Palette.ink)
            Text(label.uppercased()).font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16).chunkyCard(fill: Tidbits.Palette.surface)
    }

    @ViewBuilder private var saveProgress: some View {
        if identity.signedIn {
            VStack(spacing: 10) {
                Label("Signed in — your records sync to every device", systemImage: "checkmark.seal.fill")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                Button("Sign out") { Task { await identity.signOut() } }
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .padding(.top, 6)
        } else {
            VStack(spacing: 8) {
                Text("Save your progress").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Text("Sign in so your records follow you to any device.")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).multilineTextAlignment(.center)
                SignInWithAppleButton(.signIn) { request in
                    appleNonce = AppleNonce.random()
                    request.requestedScopes = [.email, .fullName]
                    request.nonce = AppleNonce.sha256(appleNonce)
                } onCompletion: { result in
                    if case .success(let auth) = result,
                       let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                       let data = cred.identityToken, let token = String(data: data, encoding: .utf8) {
                        let name = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                        Task { await identity.linkApple(idToken: token, rawNonce: appleNonce, appleName: name.isEmpty ? nil : name, appleEmail: cred.email) }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
            }
            .padding(.top, 10)
        }
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
}

/// A deterministic sticker avatar — a seeded color with the player's initials. No network,
/// no asset; the seed makes it stable across devices.
struct Avatar: View {
    let seed: String
    let initials: String
    var body: some View {
        let stable = seed.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }   // djb2 — stable across launches
        let hue = Double(abs(stable) % 360) / 360.0
        Circle()
            .fill(Color(hue: hue, saturation: 0.55, brightness: 0.85))
            .overlay(Circle().strokeBorder(Tidbits.Palette.ink, lineWidth: 3))
            .overlay(Text(initials).font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink))
    }
}

/// Wave E: the cross-venue / season leaderboard — reads the static JSON the cron commits.
struct LeaderboardView: View {
    @State private var overall: [LeaderboardRow] = []
    @State private var venues: [(venue: String, rows: [LeaderboardRow])] = []
    @State private var myUid = ""
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if overall.isEmpty && venues.isEmpty {
                Text("No standings yet. Play a live Tidbits night while signed in and you'll climb the board here — it refreshes hourly.")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            } else {
                Section {   // L3 seasons: the fresh-start banner
                    HStack {
                        Text(PlayerIdentity.seasonDisplay(PlayerIdentity.currentSeason())).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Spacer()
                        Text("Resets in \(PlayerIdentity.seasonResetDays()) days").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                    .listRowBackground(Tidbits.Palette.coral.opacity(0.15))
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
        return HStack(spacing: 10) {
            Text("\(i + 1)").font(.headline.monospacedDigit()).foregroundStyle(i == 0 ? Tidbits.Palette.ink : Tidbits.Palette.inkSoft).frame(width: 30, alignment: .leading)
            if i == 0 { Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow) }
            Text(r.name).fontWeight(.semibold)
            if mine { Text("YOU").font(.caption2.weight(.black)).foregroundStyle(Tidbits.Palette.blue) }
            if i == 0 { Text("CHAMPION").font(.caption2.weight(.black)).foregroundStyle(Tidbits.Palette.coral) }
            Spacer()
            Text("\(r.score)").font(.headline.monospacedDigit())
        }
        .listRowBackground(mine ? Tidbits.Palette.blue.opacity(0.12) : nil)
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
