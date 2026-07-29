#if os(tvOS)
import SwiftUI
import SwiftData
import AuthenticationServices
import UIKit

/// tvOS Settings — ten-foot, dark-first, and built from the SAME hand-rolled
/// idiom as every other tvOS screen (ContentView_tvOS / RecordsView_tvOS):
/// ZStack + TVTheme.bg + ScrollView + TVRecordsCard panels + custom
/// ButtonStyles. This deliberately does NOT use `Form`/`List`/`NavigationStack`
/// — those render as a translucent system list that looks like a web settings
/// page next to the rest of the app, and (per an App Store rejection,
/// Guideline 2.1(a)) the SwiftUI `SignInWithAppleButton` embedded in a Form
/// row could silently swallow the Siri Remote's select click. The sign-in
/// control here is a plain, always-focusable `Button` that drives
/// `ASAuthorizationController` directly (see `TVAppleSignInCoordinator`
/// below), and both success AND failure are surfaced — a failed/cancelled
/// sign-in used to fail silently, which is exactly what "no action occurred"
/// looks like from the remote.
struct SettingsView_tvOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(GameCenterManager.self) private var gameCenter
    @Environment(PlayerIdentityStore.self) private var identity
    @AppStorage(GameSettings.reviewKey) private var reviewEnabled = true
    @State private var confirmReset = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleted = false
    @State private var showLeaderboard = false
    @State private var appleCoordinator: TVAppleSignInCoordinator?
    @State private var signingIn = false
    @FocusState private var focus: SettingsFocus?

    private enum SettingsFocus: Hashable { case appleSignIn, gameplayToggle, deleteAccount }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    Text("SETTINGS")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(TVTheme.text)
                    profileSection
                    gameplaySection
                    leaderboardSection
                    gameCenterSection
                    dataSection
                    aboutSection
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onExitCommand { dismiss() }   // Menu button leaves Settings (modal: allowed)
        .confirmationDialog("Reset all records?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Everything", role: .destructive) { resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your scores, streaks, and review list.")
        }
        .fullScreenCover(isPresented: $showLeaderboard) { LeaderboardView_tvOS() }
        .confirmationDialog("Delete your Tidbits account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Tidbits account and everything stored with it — your profile, rating, streak, Daily history, leaderboard standings, and friends list. It can't be undone.")
        }
    }

    // MARK: Profile + Sign in with Apple

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Profile")
            if let p = identity.profile {
                TVRecordsCard(fill: TVTheme.panel) {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 24) {
                            Circle()
                                .fill(Color(hue: PlayerIdentity.avatarHue(p.avatarSeed), saturation: 0.55, brightness: 0.85))
                                .overlay(
                                    Text(PlayerIdentity.initials(p.name))
                                        .font(.system(size: 30, weight: .black, design: .rounded))
                                        .foregroundStyle(.black)
                                )
                                .frame(width: 84, height: 84)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(p.name).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.text)
                                Text("Rating \(Int(p.rating.value)) · \(p.streak.current)-day streak")
                                    .font(.system(size: 26, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                            }
                            Spacer()
                        }
                        HStack(spacing: 40) {
                            profileStat("Games played", "\(p.stats.gamesPlayed)")
                            profileStat("Live nights", "\(p.stats.liveNights)")
                        }
                    }
                }
                signInArea
                deleteAccountArea
            } else {
                TVRecordsCard(fill: TVTheme.panel) {
                    Text("Setting up your profile…").font(.system(size: 28, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                }
            }
        }
        .focusSection()
    }

    private func profileStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 32, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(TVTheme.text)
            Text(label.uppercased()).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
    }

    /// The one piece App Review actually flagged: an UNMISTAKABLE visual
    /// difference between signed-in (a filled mint badge) and signed-out (the
    /// real Sign in with Apple button, plus any error IN FULL VIEW — never
    /// silently dropped).
    @ViewBuilder private var signInArea: some View {
        if identity.signedIn {
            HStack(spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 26, weight: .bold))
                    Text("Signed in — records sync to every device").font(.system(size: 25, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Tidbits.Palette.mint)
                .padding(.horizontal, 26).padding(.vertical, 14)
                .background(Capsule().fill(Tidbits.Palette.mint.opacity(0.16)))
                Spacer()
                Button("Sign out") { Task { await identity.signOut() } }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    print("[AppleSignIn/tvOS] button action fired")
                    let coordinator = TVAppleSignInCoordinator(identity: identity)
                    coordinator.onStateChange = { signingIn = $0 }
                    appleCoordinator = coordinator
                    coordinator.start()
                } label: {
                    HStack(spacing: 18) {
                        if signingIn {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "apple.logo").font(.system(size: 32, weight: .medium))
                        }
                        Text(signingIn ? "Signing in…" : "Sign in with Apple").font(.system(size: 32, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 48).padding(.vertical, 22)
                }
                .buttonStyle(TVAppleSignInButtonStyle())
                .focused($focus, equals: .appleSignIn)
                .disabled(signingIn)
                if let e = identity.authError {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 22, weight: .bold))
                        Text(e).font(.system(size: 24, weight: .medium, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Tidbits.Palette.coral)
                }
            }
        }
    }

    /// App Store 5.1.1(v): an app that supports account creation must offer account DELETION
    /// in-app — not a deactivation, not a support email, not a website. Shown whether or not
    /// the player has signed in with Apple, because Tidbits provisions a real (anonymous)
    /// account for every player and that account holds their records too.
    @ViewBuilder private var deleteAccountArea: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 20) {
                Button {
                    confirmDelete = true
                } label: {
                    HStack(spacing: 14) {
                        if deleting { ProgressView().tint(.white) }
                        else { Image(systemName: "trash.fill").font(.system(size: 24, weight: .bold)) }
                        Text(deleting ? "Deleting…" : "Delete Account")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                    }
                }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                .focused($focus, equals: .deleteAccount)
                .disabled(deleting)
                Spacer()
            }
            Text("Permanently deletes your Tidbits account and all of its data — profile, rating, streak, Daily history, standings, and friends.")
                .font(.system(size: 22, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            if deleted {
                Text("Your account was deleted. This device is signed out and starting fresh.")
                    .font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.mint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let e = identity.deleteError {
                Text(e).font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Gameplay

    private var gameplaySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Gameplay")
            // NOT a TVRecordsCard: that wrapper makes the whole card its own
            // focusable region (for scroll continuity on read-only info cards
            // elsewhere on this page), which OVERLAPS the real "On/Off" button
            // below and makes it unreachable/inconsistent — a static panel
            // background here leaves the button as the section's one, unambiguous
            // focus target (the reported "Review questions is not possible to
            // access" bug).
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Review questions").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.text)
                    Spacer()
                    Button(reviewEnabled ? "On" : "Off") { reviewEnabled.toggle() }
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: reviewEnabled))
                        .focused($focus, equals: .gameplayToggle)
                }
                Text("Occasionally re-asks questions you've missed, spaced out, so they stick. Turn off to only ever see new questions.")
                    .font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(TVTheme.panel))
        }
        .focusSection()
    }

    // MARK: Leaderboard

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Leaderboard")
            Button { showLeaderboard = true } label: {
                HStack(spacing: 24) {
                    Image(systemName: "trophy.fill").font(.system(size: 36, weight: .black)).foregroundStyle(Tidbits.Palette.yellow)
                    Text("Cross-venue standings").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.text)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 24, weight: .bold)).foregroundStyle(TVTheme.textSoft)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.grape, selected: false))
        }
        .focusSection()
    }

    // MARK: Game Center

    private var gameCenterSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Game Center")
            TVRecordsCard(fill: TVTheme.panel) {
                HStack {
                    Text("Status").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.text)
                    Spacer()
                    Text(gameCenter.isAuthenticated ? "Signed in" : "Not signed in")
                        .font(.system(size: 26, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                }
            }
            if gameCenter.isAuthenticated {
                Button("Leaderboards & Achievements") { gameCenter.showDashboard() }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
            }
        }
        .focusSection()
    }

    // MARK: Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Data")
            HStack(spacing: 24) {
                Button("Reset Seen Questions") { QuestionProvider.shared.resetSeen() }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                Button("Reset All Records", role: .destructive) { confirmReset = true }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
            }
        }
        .focusSection()
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("About")
            TVRecordsCard(fill: TVTheme.panel) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Version").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.text)
                        Spacer()
                        Text(version).font(.system(size: 26, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    }
                    Text("Questions from Wikipedia, available under CC BY-SA. Tidbits is a learning game — every question is a door to learn more.")
                        .font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .focusSection()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundStyle(TVTheme.textSoft)
    }

    /// Server-side account + every local trace of it. The local wipe runs on success only —
    /// a failed remote delete must leave the player exactly where they were.
    private func deleteAccount() async {
        deleting = true; deleted = false
        let ok = await identity.deleteAccount()
        if ok {
            resetAll()
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

// MARK: - Sign in with Apple, driven directly (never wrapped in Form/List)

/// Drives `ASAuthorizationController` by hand instead of the SwiftUI
/// `SignInWithAppleButton` wrapper. On tvOS that wrapper embeds a UIKit
/// `ASAuthorizationAppleIDButton` inside a representable; nested inside a
/// `Form` row it can end up NOT forwarding the Siri Remote's select click to
/// the button's own target-action (the row's own selection handling wins) —
/// indistinguishable, from the remote, from "nothing happened," which matches
/// the App Store rejection exactly. A plain `Button` + `ButtonStyle` is
/// guaranteed focusable/clickable (it's the same pattern every other tvOS
/// screen in this app uses), and this coordinator owns the request end to end.
@MainActor
final class TVAppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var rawNonce = ""
    private let identity: PlayerIdentityStore

    init(identity: PlayerIdentityStore) {
        self.identity = identity
    }

    /// Flips true the moment `.performRequests()` is called, false once the
    /// delegate calls back (success OR failure) — read by the button so a tap
    /// gives IMMEDIATE visible feedback ("Signing in…") distinct from "did the
    /// tap even register." Also gives future test passes a second checkpoint:
    /// if this never goes true, the tap itself isn't reaching `start()`.
    var onStateChange: ((Bool) -> Void)?

    func start() {
        print("[AppleSignIn/tvOS] start() — requesting Apple ID authorization")
        onStateChange?(true)
        identity.reportAuthError(nil)
        rawNonce = AppleNonce.random()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = AppleNonce.sha256(rawNonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            let anchor = scene?.windows.first { $0.isKeyWindow }
            print("[AppleSignIn/tvOS] presentationAnchor — foreground scene found: \(scene != nil), key window found: \(anchor != nil)")
            return anchor ?? ASPresentationAnchor()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        print("[AppleSignIn/tvOS] didCompleteWithAuthorization — credential type: \(type(of: authorization.credential))")
        onStateChange?(false)
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
            print("[AppleSignIn/tvOS] no identityToken on the credential — aborting")
            identity.reportAuthError("Apple didn't return an identity token — please try again.")
            return
        }
        print("[AppleSignIn/tvOS] identityToken decoded (\(token.count) chars), email present: \(credential.email != nil), fullName present: \(credential.fullName != nil) — calling linkApple")
        let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
        Task {
            await identity.linkApple(idToken: token, rawNonce: rawNonce, appleName: name.isEmpty ? nil : name, appleEmail: credential.email)
            print("[AppleSignIn/tvOS] linkApple returned — identity.signedIn is now \(identity.signedIn), authError: \(identity.authError ?? "none")")
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("[AppleSignIn/tvOS] didCompleteWithError — \(error)")
        onStateChange?(false)
        if (error as? ASAuthorizationError)?.code == .canceled {
            print("[AppleSignIn/tvOS] user cancelled — no error nag shown")
            return
        }
        identity.reportAuthError("Apple sign-in failed: \((error as NSError).localizedDescription)")
    }
}

/// White pill + Apple logo, matching Apple's Sign in with Apple HIG — the
/// same focus-scale-and-glow treatment as every other tvOS button style here.
struct TVAppleSignInButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Tidbits.Palette.blue.opacity(focused ? 0.9 : 0), lineWidth: 5))
                .scaleEffect(focused ? 1.05 : 1.0)
                .shadow(color: .white.opacity(focused ? 0.35 : 0), radius: 24, y: 8)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
    }
}

/// Wave E: the cross-venue / season leaderboard on the TV — reuses the shared Core fetcher.
struct LeaderboardView_tvOS: View {
    @Environment(\.dismiss) private var dismiss
    @State private var overall: [LeaderboardRow] = []
    @State private var venues: [(venue: String, rows: [LeaderboardRow])] = []
    @State private var friends: [PlayerIdentity.Friend] = []
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
        .onExitCommand { dismiss() }   // presented via fullScreenCover from Settings (modal: allowed)
        .task { await load() }
    }

    private struct FriendRank: Identifiable { let id: String; let name: String; let score: Int? }
    private var friendRanks: [FriendRank] {
        var byUid: [String: Int] = [:]; for r in overall { byUid[r.uid] = r.score }
        var rows = friends.map { FriendRank(id: $0.uid, name: $0.name, score: byUid[$0.uid]) }
        if let me = overall.first(where: { $0.uid == myUid }) {
            rows.append(FriendRank(id: myUid, name: "\(me.name) (you)", score: me.score))
        }
        return rows.sorted { ($0.score ?? -1) > ($1.score ?? -1) }
    }
    private func friendRow(_ i: Int, _ f: FriendRank) -> some View {
        HStack(spacing: 18) {
            Text("\(i + 1)").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(TVTheme.textSoft).frame(width: 50, alignment: .leading)
            Text(f.name).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Spacer()
            Text(f.score.map(String.init) ?? "—").font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(f.score == nil ? TVTheme.textSoft : .white)
        }
        .padding(.vertical, 6)
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
#endif
