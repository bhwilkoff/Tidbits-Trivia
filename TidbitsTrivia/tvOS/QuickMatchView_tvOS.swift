#if os(tvOS)
import SwiftUI
import GameKit

/// Online Quick Match over Game Center on the TV (Decision 039) — the same
/// leader-election + GameKit-transport flow as iOS, rendered ten-foot.
struct TVQuickMatchContainer: View {
    @Environment(AppStore.self) private var store
    @Environment(GameCenterManager.self) private var gameCenter
    @Environment(\.dismiss) private var dismiss
    @State private var live: LiveNight?
    @State private var failed: String?

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            if let live {
                TVNightLiveContainer(live: live)
            } else if !gameCenter.isAuthenticated {
                message("Sign in to Game Center",
                        "Quick Match uses Game Center to find opponents. Sign in from Settings → Users and Accounts → Game Center.")
            } else if let failed {
                message("Couldn't find a match", failed)
            } else {
                TVMatchmakerSheet(onMatch: startMatch, onCancel: { dismiss() }, onError: { failed = $0 })
                    .ignoresSafeArea()
            }
        }
        .onExitCommand { dismiss() }
    }

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

    private func message(_ title: String, _ body: String) -> some View {
        VStack(spacing: 24) {
            Text(title).font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(TVTheme.text)
            Text(body).font(.system(size: 29, weight: .medium, design: .rounded))
                .foregroundStyle(TVTheme.textSoft).multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
        }
        .padding(90)
    }
}

private struct TVMatchmakerSheet: UIViewControllerRepresentable {
    let onMatch: (GKMatch) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> GKMatchmakerViewController {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 4
        let vc = GKMatchmakerViewController(matchRequest: request)!
        vc.matchmakerDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: GKMatchmakerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, GKMatchmakerViewControllerDelegate {
        let parent: TVMatchmakerSheet
        init(_ parent: TVMatchmakerSheet) { self.parent = parent }

        func matchmakerViewControllerWasCancelled(_ vc: GKMatchmakerViewController) { parent.onCancel() }
        func matchmakerViewController(_ vc: GKMatchmakerViewController, didFailWithError error: Error) {
            parent.onError(error.localizedDescription)
        }
        func matchmakerViewController(_ vc: GKMatchmakerViewController, didFind match: GKMatch) {
            parent.onMatch(match)
        }
    }
}
#endif
