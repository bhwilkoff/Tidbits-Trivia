#if os(iOS)
import SwiftUI
import SwiftData
import AuthenticationServices

/// The player's portable Tidbits identity, rendered native-iOS (chunky sticker cards).
/// Reads `PlayerIdentityStore` — the ONE shared profile that spans solo + live — and
/// surfaces the Apple-native pieces (Game Center) alongside it. Reached from Settings.
struct ProfileView: View {
    @Environment(PlayerIdentityStore.self) private var identity
    @Environment(GameCenterManager.self) private var gameCenter
    @Environment(EntitlementStore.self) private var entitlement
    @Environment(\.modelContext) private var modelContext
    @State private var showPaywall = false
    @State private var editingName = false
    @State private var draftName = ""
    @State private var appleNonce = ""
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleted = false

    var body: some View {
        ScrollView {
            if let p = identity.profile {
                VStack(spacing: 16) {
                    header(p)
                    ratingCard(p.rating)
                    streakCard(p.streak)
                    statsGrid(p.stats)
                    Button { showPaywall = true } label: {
                        Label(entitlement.isClub ? "Tidbits Club — Member" : "Join Tidbits Club",
                              systemImage: entitlement.isClub ? "star.circle.fill" : "star.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: entitlement.isClub ? Tidbits.Palette.surface : Tidbits.Palette.blue,
                                                   textColor: entitlement.isClub ? Tidbits.Palette.ink : .white))
                    NavigationLink { LeaderboardView() } label: {   // Wave E: cross-venue / season standings
                        Label("Leaderboard", systemImage: "trophy.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink))
                    NavigationLink { DuelsView() } label: {   // L5: async friend duels
                        Label("Duels", systemImage: "flag.2.crossed.fill").frame(maxWidth: .infinity)
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
                    deleteAccountSection
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
        .sheet(isPresented: $showPaywall) { ClubPaywallView() }
        .alert("Delete your Tidbits account?", isPresented: $confirmDelete) {
            Button("Delete Account", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Tidbits account and everything stored with it — your profile, rating, streak, Daily history, leaderboard standings, and friends list. It can't be undone.")
        }
    }

    /// App Store 5.1.1(v): an app that supports account creation must offer account DELETION
    /// in-app — not a deactivation, not a support email, not a website. Shown whether or not
    /// the player has signed in with Apple, because Tidbits provisions a real (anonymous)
    /// account for every player and that account holds their records too.
    @ViewBuilder private var deleteAccountSection: some View {
        VStack(spacing: 8) {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                HStack(spacing: 8) {
                    if deleting { ProgressView() }
                    Text(deleting ? "Deleting…" : "Delete Account")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.coral))
            .disabled(deleting)
            Text("Permanently deletes your account and all of its data — profile, rating, streak, Daily history, standings, and friends.")
                .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                .multilineTextAlignment(.center)
            if deleted {
                Text("Your account was deleted. This device is signed out and starting fresh.")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink)
                    .multilineTextAlignment(.center)
            }
            if let e = identity.deleteError {
                Text(e).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.coral)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 18)
    }

    /// Server-side account + every local trace of it. The local wipe runs on success only —
    /// a failed remote delete must leave the player exactly where they were.
    private func deleteAccount() async {
        deleting = true; deleted = false
        if await identity.deleteAccount() {
            try? modelContext.delete(model: GameRecord.self)
            try? modelContext.delete(model: MissedFact.self)
            try? modelContext.delete(model: DailyStreak.self)
            try? modelContext.delete(model: CalibrationTally.self)
            try? modelContext.save()
            QuestionProvider.shared.resetSeen()
            deleted = true
        }
        deleting = false
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
                    identity.reportAuthError(nil)
                    appleNonce = AppleNonce.random()
                    request.requestedScopes = [.email, .fullName]
                    request.nonce = AppleNonce.sha256(appleNonce)
                } onCompletion: { result in
                    // Never drop a failure on the floor: a silent onCompletion is exactly what
                    // made tvOS sign-in look broken to App Review.
                    switch result {
                    case .success(let auth):
                        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                              let data = cred.identityToken, let token = String(data: data, encoding: .utf8) else {
                            identity.reportAuthError("Apple didn't return an identity token — please try again."); return
                        }
                        let name = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                        Task { await identity.linkApple(idToken: token, rawNonce: appleNonce, appleName: name.isEmpty ? nil : name, appleEmail: cred.email) }
                    case .failure(let err):
                        if (err as? ASAuthorizationError)?.code == .canceled { return }
                        identity.reportAuthError("Apple sign-in failed: \((err as NSError).localizedDescription)")
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
                if let e = identity.authError {
                    Text(e).font(Tidbits.TypeRamp.l5).foregroundStyle(.red)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
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
    @State private var friends: [PlayerIdentity.Friend] = []
    @State private var challenged: Set<String> = []
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
                if !friends.isEmpty {   // L5 social graph: your people, ranked by their public standing
                    Section("Friends") { ForEach(Array(friendRanks.enumerated()), id: \.element.id) { friendRow($0.offset, $0.element) } }
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

    private struct FriendRank: Identifiable { let id: String; let name: String; let score: Int?; let isMe: Bool }
    private var friendRanks: [FriendRank] {
        var byUid: [String: Int] = [:]; for r in overall { byUid[r.uid] = r.score }
        var rows = friends.map { FriendRank(id: $0.uid, name: $0.name, score: byUid[$0.uid], isMe: false) }
        if let me = overall.first(where: { $0.uid == myUid }) {
            rows.append(FriendRank(id: myUid, name: "\(me.name) (you)", score: me.score, isMe: true))
        }
        return rows.sorted { ($0.score ?? -1) > ($1.score ?? -1) }
    }
    private func friendRow(_ i: Int, _ f: FriendRank) -> some View {
        HStack(spacing: 10) {
            Text("\(i + 1)").font(.headline.monospacedDigit()).foregroundStyle(Tidbits.Palette.inkSoft).frame(width: 30, alignment: .leading)
            Text(f.name).fontWeight(.semibold)
            if !f.isMe {   // L5: challenge to a duel
                if challenged.contains(f.id) {
                    Text("Sent").font(.caption2).foregroundStyle(Tidbits.Palette.inkSoft)
                } else {
                    Button("Duel") { Task { await challenge(f.id, f.name) } }
                        .buttonStyle(.borderless).font(.caption.weight(.bold)).foregroundStyle(Tidbits.Palette.blue)
                }
            }
            Spacer()
            Text(f.score.map(String.init) ?? "—").font(.headline.monospacedDigit()).foregroundStyle(f.score == nil ? Tidbits.Palette.inkSoft : Tidbits.Palette.ink)
        }
        .listRowBackground(f.isMe ? Tidbits.Palette.blue.opacity(0.12) : nil)
    }

    private func challenge(_ uid: String, _ name: String) async {
        let qs = await QuestionProvider.shared.questions(mode: .mix, category: .named("mixed"))
        let ds = qs.filter { $0.options.count >= 2 }.prefix(6).map { DuelQ(p: $0.prompt, o: $0.options, c: $0.correctIndex, e: $0.explanation) }
        if await DuelStore.shared.challenge(friendUID: uid, friendName: name, questions: Array(ds)) != nil { challenged.insert(uid) }
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
        await PlayerIdentityStore.shared.loadFriends()   // L5 social graph
        friends = PlayerIdentityStore.shared.friends
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

// MARK: - Async friend duels (L5)

struct PlayableDuel: Identifiable { let id: String; let questions: [Question] }

/// The duels list — incoming challenges + your duels with status (your-turn / waiting / result).
struct DuelsView: View {
    @State private var inbox: [DuelInvite] = []
    @State private var mine: [DuelStanding] = []
    @State private var loading = true
    @State private var playing: PlayableDuel?
    private let store = DuelStore.shared

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                let mineIDs = Set(mine.map(\.id))
                let pending = inbox.filter { !mineIDs.contains($0.id) }
                if pending.isEmpty && mine.isEmpty {
                    Text("No duels yet. Add friends from a live night, then tap Duel on the Leaderboard.")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                if !pending.isEmpty {
                    Section("Challenges for you") {
                        ForEach(pending) { inv in
                            HStack {
                                Text("\(inv.fromName) challenged you").fontWeight(.semibold)
                                Spacer()
                                Button("Play") { Task { await play(inv.id) } }
                                    .buttonStyle(.borderless).foregroundStyle(Tidbits.Palette.blue)
                            }
                        }
                    }
                }
                if !mine.isEmpty {
                    Section("Your duels") { ForEach(mine) { duelRow($0) } }
                }
            }
        }
        .navigationTitle("Duels")
        .task { await load() }
        .fullScreenCover(item: $playing) { pd in
            DuelGameContainer(duelId: pd.id, questions: pd.questions) { playing = nil; Task { await load() } }
        }
    }

    @ViewBuilder private func duelRow(_ d: DuelStanding) -> some View {
        HStack {
            Text("vs \(d.oppName)").fontWeight(.semibold)
            Spacer()
            if d.myDone && d.oppDone {
                Text(d.myScore > d.oppScore ? "Won \(d.myScore)-\(d.oppScore)" : d.myScore < d.oppScore ? "Lost \(d.myScore)-\(d.oppScore)" : "Tied \(d.myScore)-\(d.oppScore)")
                    .fontWeight(.bold).foregroundStyle(d.myScore > d.oppScore ? Tidbits.Palette.coral : Tidbits.Palette.inkSoft)
                if !d.oppUid.isEmpty {
                    Button("Rematch") { Task { await rematch(d.oppUid, d.oppName) } }
                        .buttonStyle(.borderless).font(.caption.weight(.bold)).foregroundStyle(Tidbits.Palette.blue)
                }
            } else if d.myDone {
                Text("Waiting on \(d.oppName)").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
            } else {
                Button("Your turn") { Task { await play(d.id) } }
                    .buttonStyle(.borderless).foregroundStyle(Tidbits.Palette.blue)
            }
        }
    }

    private func play(_ id: String) async {
        await store.accept(id)
        guard let d = await store.load(id) else { return }
        let qs = d.questions.prefix(10).map {
            Question(id: UUID().uuidString, prompt: $0.p, options: $0.o, correctIndex: $0.c,
                     categoryID: "mixed", difficulty: 3, explanation: $0.e, sourceTitle: "", sourceURL: nil, templateID: "duel")
        }
        playing = PlayableDuel(id: id, questions: Array(qs))
    }

    private func rematch(_ uid: String, _ name: String) async {
        let qs = await QuestionProvider.shared.questions(mode: .mix, category: .named("mixed"))
        let ds = qs.filter { $0.options.count >= 2 }.prefix(6).map { DuelQ(p: $0.prompt, o: $0.options, c: $0.correctIndex, e: $0.explanation) }
        _ = await store.challenge(friendUID: uid, friendName: name, questions: Array(ds))
        await load()
    }

    private func load() async {
        async let ib = store.inbox()
        async let mn = store.mine()
        inbox = await ib; mine = await mn; loading = false
    }
}

/// Plays a duel's shared question set on the game engine, then submits my score to my slot.
struct DuelGameContainer: View {
    let duelId: String
    let questions: [Question]
    let onDone: () -> Void
    @State private var game = GameEngine()
    @State private var started = false
    @State private var submitted = false

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                ProgressView().controlSize(.large).tint(Tidbits.Palette.ink)
            case .roundIntro, .playing, .reveal:
                GamePlayView(game: game, onQuit: close)
            case .finished:
                ResultsView(summary: game.summary, onPlayAgain: nil, onDone: close).onAppear(perform: submit)
            }
        }
        .onAppear { if !started { started = true; game.startCustom(mode: .mix, category: .named("mixed"), questions: questions) } }
    }
    private func submit() {
        guard !submitted else { return }; submitted = true
        let s = game.summary.score
        Task { await DuelStore.shared.submit(duelId, score: s) }
    }
    private func close() { game.quit(); onDone() }
}

#endif
