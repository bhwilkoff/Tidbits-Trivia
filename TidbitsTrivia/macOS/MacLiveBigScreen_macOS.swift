#if os(macOS)
import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

/// The canonical web join URL a QR encodes. `tidbitstrivia.com/live/{code}`
/// redirects (via 404.html) to the hash-routed web player with the code
/// prefilled — so scanning joins WITHOUT typing the 4-char code.
func liveJoinURL(_ code: String) -> String { "https://tidbitstrivia.com/live/\(code)" }

/// Generate a crisp, scannable QR NSImage for a string (CoreImage, no network).
@MainActor func makeLiveQR(_ string: String) -> NSImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let ci = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
    let rep = NSCIImageRep(ciImage: ci)
    let img = NSImage(size: rep.size)
    img.addRepresentation(rep)
    return img
}

/// Big-screen join panel: a scannable QR + the 4-char code (for anyone typing).
/// The QR opens the web player with the code prefilled — join without typing.
struct LiveJoinPanel: View {
    let code: String
    var qrSize: CGFloat = 150
    var body: some View {
        VStack(spacing: 8) {
            Text("SCAN TO JOIN").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
            if let img = makeLiveQR(liveJoinURL(code)) {
                Image(nsImage: img).interpolation(.none).resizable()
                    .frame(width: qrSize, height: qrSize)
                    .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidbits.Palette.border, lineWidth: 3))
            }
            Text("CODE \(code)").font(.system(size: 26, weight: .black, design: .monospaced)).foregroundStyle(Tidbits.Palette.ink).kerning(2)
            Text("or tidbitstrivia.com/live").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Tidbits.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Tidbits.Palette.border, lineWidth: 3))
    }
}

/// Shares the active host session between the cockpit window and the projector
/// window (macOS-DESIGN §A1.1 — two views of ONE live event, never mirrored).
@Observable
@MainActor
final class LiveHostCoordinator {
    var session: LiveHostSession?
    /// The networked room (nil for a paper-only night) — shared so the projector
    /// can show the join code + the joined-team leaderboard.
    var net: LiveHostNet?
}

/// The big-screen (projector) output — ten-foot UI (§A1.2). Shows ONLY the
/// current question, the join info, and the team leaderboard — never a
/// host-only affordance. Opens as its own window; drag it to the projector.
struct LiveBigScreen_macOS: View {
    @Environment(LiveHostCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// §A8.5 — one show-timing spring, disabled under reduce-motion.
    private var showAnim: Animation? { reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.72) }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            if let s = coordinator.session {
                if s.finished { standings(s).transition(.opacity) } else { live(s).transition(.opacity) }
            } else {
                splash.transition(.opacity)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .animation(showAnim, value: coordinator.session?.finished)
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
            VStack(spacing: 12) {
                if let q = s.current {
                    Text(q.prompt)
                        .font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .id(q.id)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    if s.revealed {
                        Text(q.correctAnswer)
                            .font(.system(size: 52, weight: .black, design: .rounded)).foregroundStyle(.white)
                            .padding(.horizontal, 28).padding(.vertical, 14)
                            .background(Capsule().fill(Tidbits.Palette.mint))
                            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 4))
                            .shadow(color: Tidbits.Palette.mint.opacity(reduceMotion ? 0 : 0.65), radius: 34)
                            .padding(.top, 12)
                            .transition(.scale(scale: 0.55).combined(with: .opacity))   // A8.1 the reveal is theatre
                    } else {
                        Text("Answers on your team sheet").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                }
            }
            .animation(showAnim, value: s.revealed)
            .animation(showAnim, value: s.current?.id)
            Spacer()
            HStack(alignment: .bottom, spacing: 24) {
                leaderboard(s)
                Spacer(minLength: 0)
                if let net = coordinator.net, net.isOpen {
                    LiveJoinPanel(code: net.code)
                }
            }
        }
        .padding(48)
    }

    private func leaderboard(_ s: LiveHostSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if s.teams.isEmpty {
                Text("Teams appear here as they join.").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
            } else {
                ForEach(Array(s.standings.prefix(5).enumerated()), id: \.element.id) { i, team in
                    HStack(spacing: 14) {
                        Text("\(i + 1)").font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(i == 0 ? Tidbits.Palette.ink : Tidbits.Palette.inkSoft).frame(width: 32)
                        if i == 0 { Image(systemName: "crown.fill").font(.system(size: 22)).foregroundStyle(Tidbits.Palette.yellow) }
                        Text(team.name).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
                        Spacer(minLength: 20)
                        Text("\(team.score)").font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(Tidbits.Palette.ink)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12).frame(width: 460)
                    .background(RoundedRectangle(cornerRadius: 16).fill(i == 0 ? Tidbits.Palette.yellow : Tidbits.Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tidbits.Palette.border, lineWidth: 3))
                    .transition(.opacity)
                }
            }
        }
        .animation(showAnim, value: s.standings.prefix(5).map(\.id))   // A8.2 the leaderboard climbs
    }

    private func standings(_ s: LiveHostSession) -> some View {
        VStack(spacing: 20) {
            if let winner = s.standings.first, winner.score > 0 {
                HStack(spacing: 16) {
                    Image(systemName: "party.popper.fill").font(.system(size: 40)).foregroundStyle(Tidbits.Palette.coral)
                    Text("\(winner.name) wins!").font(.system(size: 60, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                    Image(systemName: "party.popper.fill").font(.system(size: 40)).foregroundStyle(Tidbits.Palette.coral).scaleEffect(x: -1)
                }
                .symbolEffect(.bounce, options: reduceMotion ? .nonRepeating : .repeating)
            } else {
                Text("FINAL STANDINGS").font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            }
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
