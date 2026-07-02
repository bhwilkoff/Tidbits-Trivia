#if os(iOS)
import SwiftUI
import GameKit

/// Online Quick Match over Game Center (Decision 039) — Apple's native
/// matchmaking (invites + automatch) in front of the SAME night machinery the
/// local Trivia Night runs; GameKit is just another transport behind the
/// `NightPeerLink` seam. Zero servers.
struct QuickMatchContainer: View {
    @Environment(AppStore.self) private var store
    @Environment(GameCenterManager.self) private var gameCenter
    @Environment(\.dismiss) private var dismiss
    @State private var live: LiveNight?
    @State private var failed: String?

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            if let live {
                NightLiveContainer(live: live)
            } else if !gameCenter.isAuthenticated {
                authNeeded
            } else if let failed {
                failView(failed)
            } else {
                MatchmakerSheet(onMatch: startMatch, onCancel: { dismiss() }, onError: { failed = $0 })
                    .ignoresSafeArea()
            }
        }
    }

    /// The match arrived: every device elects the same leader (lowest player
    /// id); the leader hosts, everyone else joins the leader — all over the
    /// GameKit link, auto-paced (no human host taps between strangers).
    private func startMatch(_ match: GKMatch) {
        let session = GameKitSession(match: match)
        let players = match.players.count + 1
        if session.isLeader {
            live = LiveNight(hostingPlan: .quick, category: .named("mixed"),
                             hostName: GKLocalPlayer.local.displayName,
                             engine: store.game,
                             transport: GameKitHostTransport(session: session),
                             roomCode: Night.gameKitCode,
                             autoPace: true, expectedPlayers: players)
        } else {
            let joining = LiveNight(joiningEngine: store.game,
                                    transport: GameKitClientTransport(session: session))
            joining.join(code: Night.gameKitCode, name: GKLocalPlayer.local.displayName)
            live = joining
        }
    }

    private var authNeeded: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe.americas.fill").font(.system(size: 44, weight: .black))
                .foregroundStyle(Tidbits.Palette.blue)
            Text("Sign in to Game Center").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("Quick Match uses Game Center to find opponents. Sign in from Settings → Game Center, then come back.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
        }
        .padding(32)
        .onAppear { GameCenterManager.shared.authenticate() }
    }

    private func failView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Couldn't find a match").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text(message).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
        }
        .padding(32)
    }
}

/// Apple's stock matchmaking UI (invites + automatch to fill empty slots).
private struct MatchmakerSheet: UIViewControllerRepresentable {
    let onMatch: (GKMatch) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> GKMatchmakerViewController {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 4
        request.inviteMessage = "Trivia — same questions, fastest correct answers win."
        let vc = GKMatchmakerViewController(matchRequest: request)!
        vc.matchmakerDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: GKMatchmakerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, GKMatchmakerViewControllerDelegate {
        let parent: MatchmakerSheet
        init(_ parent: MatchmakerSheet) { self.parent = parent }

        func matchmakerViewControllerWasCancelled(_ vc: GKMatchmakerViewController) {
            parent.onCancel()
        }
        func matchmakerViewController(_ vc: GKMatchmakerViewController, didFailWithError error: Error) {
            parent.onError(error.localizedDescription)
        }
        func matchmakerViewController(_ vc: GKMatchmakerViewController, didFind match: GKMatch) {
            parent.onMatch(match)
        }
    }
}
#endif
