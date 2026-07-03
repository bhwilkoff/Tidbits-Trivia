#if os(macOS)
import SwiftUI

/// Shares the active host session between the cockpit window and the projector
/// window (macOS-DESIGN §A1.1 — two views of ONE live event, never mirrored).
@Observable
@MainActor
final class LiveHostCoordinator {
    var session: LiveHostSession?
}

/// The big-screen (projector) output — ten-foot UI (§A1.2). Shows ONLY the
/// current question, the join info, and the team leaderboard — never a
/// host-only affordance. Opens as its own window; drag it to the projector.
struct LiveBigScreen_macOS: View {
    @Environment(LiveHostCoordinator.self) private var coordinator

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            if let s = coordinator.session {
                if s.finished { standings(s) } else { live(s) }
            } else {
                splash
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private var splash: some View {
        VStack(spacing: 12) {
            Image(systemName: "megaphone.fill").font(.system(size: 64, weight: .black)).foregroundStyle(Tidbits.Palette.coral)
            Text("TIDBITS LIVE").font(.system(size: 72, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Text("The host will start the night shortly.").font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
        }
    }

    private func live(_ s: LiveHostSession) -> some View {
        VStack(spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.event.name.uppercased()).font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                    if !s.event.venue.isEmpty {
                        Text(s.event.venue).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                    }
                }
                Spacer()
                Text("ROUND \(s.roundNumber)/\(s.roundCount) · \(s.roundTitle)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Spacer()
            if let q = s.current {
                Text(q.prompt)
                    .font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if s.revealed {
                    Text(q.correctAnswer)
                        .font(.system(size: 52, weight: .black, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 28).padding(.vertical, 14)
                        .background(Capsule().fill(Tidbits.Palette.mint))
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 4))
                        .padding(.top, 12)
                } else {
                    Text("Answers on your team sheet").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
                }
            }
            Spacer()
            leaderboard(s)
        }
        .padding(48)
    }

    private func leaderboard(_ s: LiveHostSession) -> some View {
        HStack(spacing: 16) {
            ForEach(Array(s.standings.prefix(5).enumerated()), id: \.element.id) { i, team in
                HStack(spacing: 10) {
                    if i == 0 { Image(systemName: "crown.fill").font(.system(size: 22)).foregroundStyle(Tidbits.Palette.yellow) }
                    Text(team.name).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
                    Text("\(team.score)").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16).fill(i == 0 ? Tidbits.Palette.yellow : Tidbits.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tidbits.Palette.border, lineWidth: 3))
            }
            if s.teams.isEmpty {
                Text("Teams appear here as the host adds them.").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
            }
        }
    }

    private func standings(_ s: LiveHostSession) -> some View {
        VStack(spacing: 20) {
            Text("FINAL STANDINGS").font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            ForEach(Array(s.standings.prefix(8).enumerated()), id: \.element.id) { i, team in
                HStack(spacing: 20) {
                    Text("\(i + 1)").font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft).frame(width: 60)
                    if i == 0 { Image(systemName: "crown.fill").font(.system(size: 34)).foregroundStyle(Tidbits.Palette.yellow) }
                    Text(team.name).font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                    Spacer()
                    Text("\(team.score)").font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                }
                .padding(.horizontal, 28).padding(.vertical, 16)
                .frame(maxWidth: 760)
                .background(RoundedRectangle(cornerRadius: 18).fill(i == 0 ? Tidbits.Palette.yellow : Tidbits.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Tidbits.Palette.border, lineWidth: 3))
            }
        }
        .padding(48)
    }
}
#endif
