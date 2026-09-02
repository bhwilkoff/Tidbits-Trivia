#if os(macOS)
import SwiftUI
import AppKit
import AVKit
import CoreImage.CIFilterBuiltins

/// The canonical web join URL a QR encodes. `tidbitstrivia.com/live/{code}`
/// redirects (via 404.html) to the hash-routed web player with the code
/// prefilled — so scanning joins WITHOUT typing the 4-char code.
func liveJoinURL(_ code: String) -> String { "https://tidbitstrivia.com/live/\(code)" }

/// Wave D: white-label — a #RRGGBB hex ↔ SwiftUI Color round-trip for the host's brand accent.
extension Color {
    init?(hexString: String) {
        var h = hexString.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        self = Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((ns.redComponent * 255).rounded()), Int((ns.greenComponent * 255).rounded()), Int((ns.blueComponent * 255).rounded()))
    }
}

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
    /// A8.3 — the round number currently being announced (full-screen card), nil = none.
    @State private var introRound: Int?

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            if let s = coordinator.session {
                if s.onBreak { breakSlide(s).transition(.opacity) }   // adaptability: intermission hold
                else if s.finished { standings(s).transition(.opacity) } else { live(s).transition(.opacity) }
            } else {
                splash.transition(.opacity)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .overlay(alignment: .bottom) {   // Wave D: sponsor kit — a persistent branded footer (lobby + between rounds + play)
            if let s = coordinator.session, !s.event.sponsor.isEmpty {
                Text("Brought to you by \(s.event.sponsor)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
                    .padding(.vertical, 9).padding(.horizontal, 24)
                    .background(Capsule().fill(Tidbits.Palette.surface))
                    .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                    .padding(.bottom, 26)
            }
        }
        .animation(showAnim, value: coordinator.session?.finished)
        .overlay {
            if let r = introRound, let s = coordinator.session, !s.finished {
                roundIntroCard(r, title: s.roundTitle, count: s.questionInRound.of)
                    .transition(.opacity).zIndex(10)
            }
        }
        .animation(showAnim, value: introRound)
        .onChange(of: coordinator.session?.roundNumber) { _, n in
            if let n, coordinator.session?.finished == false { introRound = n }   // A8.3 announce each new round (and round 1)
        }
        .task(id: introRound) {
            guard introRound != nil else { return }
            try? await Task.sleep(for: .seconds(reduceMotion ? 1.4 : 2.6))
            introRound = nil
        }
    }

    /// A8.3 — the full-screen round announcement ("ROUND 2 · HISTORY · 6 questions").
    private func roundIntroCard(_ round: Int, title: String, count: Int) -> some View {
        ZStack {
            Tidbits.Palette.ink.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("ROUND \(round)").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                Text(title.isEmpty ? "LET'S PLAY" : title.uppercased())
                    .font(.system(size: 88, weight: .black, design: .rounded)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text("\(count) question\(count == 1 ? "" : "s")").font(.system(size: 32, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(60)
        }
    }

    private var splash: some View {
        VStack(spacing: 12) {
            Image(systemName: "megaphone.fill").font(.system(size: 64, weight: .black)).foregroundStyle(Tidbits.Palette.coral)
            Text("TIDBITS LIVE").font(.system(size: 72, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Text("The host will start the night shortly.").font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
        }
    }

    /// Adaptability: the intermission hold — the projector rests here on a break while the game
    /// position is preserved in the cockpit.
    private func breakSlide(_ s: LiveHostSession) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 56, weight: .black)).foregroundStyle(Tidbits.Palette.coral)
            Text(s.event.name.isEmpty ? "TIDBITS LIVE" : s.event.name.uppercased())
                .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
            Text("Back in a moment").font(.system(size: 72, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Text("Grab a drink — the next round is coming up.").font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
        }
    }

    private func live(_ s: LiveHostSession) -> some View {
        VStack(spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.event.name.uppercased()).font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Color(hexString: s.event.brandHex) ?? Tidbits.Palette.ink)   // Wave D: white-label brand accent
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if !s.event.venue.isEmpty {
                        Text(s.event.venue).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                    }
                }
                Spacer()
                Text("ROUND \(s.roundNumber)/\(s.roundCount) · \(s.roundTitle)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
                    .lineLimit(1).minimumScaleFactor(0.6)   // a long round title shrinks instead of wrapping/overflowing
            }
            if let d = s.deadlineMs, !s.revealed { countdown(deadlineMs: d) }   // Wave A: on-screen timer
            VStack(spacing: 12) {
                if let q = s.current {
                    chromeRow(q, s)   // Wave B: format + difficulty chrome
                    Text(q.prompt)
                        .font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                        .multilineTextAlignment(.center).lineLimit(5).minimumScaleFactor(0.45)
                        // The prompt gets a GUARANTEED band of the screen. Both bounds
                        // are load-bearing, and each was measured on the real projector:
                        //
                        //   no minHeight — the VStack squeezed the prompt to one line and
                        //   it truncated: "...rose from advisor to his father in 2…".
                        //   lineLimit(5) does not save it, because minimumScaleFactor
                        //   makes SwiftUI prefer shrinking one line over wrapping.
                        //
                        //   no maxHeight (or .fixedSize) — a long prompt wraps but grows
                        //   without limit, pushing the event title, the round line and the
                        //   join code off the screen entirely.
                        //
                        // A question the room cannot read, and a join code the room cannot
                        // see, are the two worst failures this surface has.
                        // On REVEAL the slide also carries the vote tally (one row per option) and the
                        // explanation, roughly 340pt more. Measured on the projector: with the
                        // question keeping its full band, that pushed the event title, the round
                        // line and the join code off the screen — the same overflow as the
                        // truncation fix, in the state the room stares at longest. The question
                        // has already been read aloud by then, so it yields the space.
                        .frame(maxWidth: 1200,
                               minHeight: s.revealed ? 90 : 150,
                               maxHeight: s.revealed ? 150 : 240)
                        .id(q.id)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    if LiveVideoPlayer.shared.hasVideo, let vplayer = LiveVideoPlayer.shared.player {   // Wave B: video question
                        VideoPlayer(player: vplayer)
                            .frame(maxWidth: .infinity, minHeight: 420, maxHeight: 560)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tidbits.Palette.border, lineWidth: 4))
                    }
                    let hasVotes = !(coordinator.net?.answers.isEmpty ?? true)
                    if LiveNightHost.isMCQ(q), hasVotes || s.revealed {
                        voteTally(q, revealed: s.revealed)   // A8: the room watches the votes land
                            // Same clearance as the explanation: the per-option VOTE
                            // COUNTS sit at the trailing end of each bar, and the join
                            // panel overlay was sitting on top of them. "How did the room
                            // vote" is the point of this panel.
                            .padding(.trailing, 360)
                    } else if s.revealed {
                        Text(q.correctAnswer)
                            .font(.system(size: 52, weight: .black, design: .rounded)).foregroundStyle(.white)
                            .lineLimit(2).minimumScaleFactor(0.5)   // a long answer fits the capsule
                            .padding(.horizontal, 28).padding(.vertical, 14)
                            .background(Capsule().fill(Tidbits.Palette.mint))
                            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 4))
                            .shadow(color: Tidbits.Palette.mint.opacity(reduceMotion ? 0 : 0.65), radius: 34)
                            .padding(.top, 12)
                            .transition(.scale(scale: 0.55).combined(with: .opacity))   // A8.1 the reveal is theatre
                    } else {
                        Text("Answer on your phones").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                    if s.revealed {   // Wave A: the story behind the answer — the learning payoff on the big screen
                        let story = q.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !story.isEmpty {
                            Text(story)
                                .font(.system(size: 30, weight: .medium, design: .rounded))
                                .foregroundStyle(Tidbits.Palette.inkSoft)
                                .multilineTextAlignment(.center)
                                // Wraps to three lines and shrinks rather than cutting.
                                // Without this a long payoff truncated —
                                // "...proscribed by the British government and in 1940 it
                                // was disp…" — and the explanation is the LEARNING, the
                                // reason the reveal is on the screen at all. The earlier
                                // pass here was luck: the scenario draws a random question
                                // and had happened to land a one-line explanation.
                                .lineLimit(3).minimumScaleFactor(0.55)
                                .frame(maxWidth: 1100, minHeight: 90, alignment: .top)
                                .padding(.top, 18)
                                // Clear the join panel. Moving that panel to an overlay
                                // stopped it pushing the header off the top, but an
                                // overlay OCCLUDES: the reveal explanation then ran
                                // underneath the QR — "...is an Ea", "...since" — and the
                                // room could not read the payoff. The panel is ~340pt
                                // wide in the trailing corner.
                                .padding(.trailing, 360)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .animation(showAnim, value: s.revealed)
            .animation(showAnim, value: s.current?.id)
            // The middle takes WHAT IS LEFT between the header and the join panel,
            // and never more. It used to sit between two Spacers, so on the reveal —
            // when the vote tally and the explanation appear — the stack grew past
            // the window, SwiftUI centred the overflow, and the event title, the
            // round line and the join code went off the top and bottom of the
            // projector. Measured three times at three different fixed heights
            // before fixing the structure instead of the numbers.
            .frame(maxHeight: .infinity)
        }
        .padding(48)
        // The team list and the JOIN PANEL are an OVERLAY, not a stacked row.
        //
        // This is what was actually overflowing the projector. The QR panel is
        // roughly 280pt tall, and in the vertical flow it competed with the
        // question, the vote tally and the explanation for the window's 720pt. On
        // the reveal the sum went over, SwiftUI centred the excess, and the event
        // title and round line went off the top while the explanation was squeezed
        // to one truncated line. Three different fixed heights were tried against
        // the symptom before measuring what actually occupied the space.
        //
        // As an overlay the panel renders in exactly the same corner — it sat in
        // empty space already — but contributes NO height, so the slide cannot push
        // its own header off the screen.
        .overlay(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 24) {
                leaderboard(s)
                Spacer(minLength: 0)
                if let net = coordinator.net, net.isOpen {
                    LiveJoinPanel(code: net.code)
                }
            }
            .padding(48)
        }
    }

    /// Wave B: the show chrome above each question — what KIND of question and how hard.
    @ViewBuilder private func chromeRow(_ q: Question, _ s: LiveHostSession) -> some View {
        let ri = q.roundIndex ?? 0
        let format = s.event.rounds.indices.contains(ri) ? s.event.rounds[ri].format : nil
        HStack(spacing: 16) {
            if let format {
                Label(format.title, systemImage: format.symbol)
                    .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            let (label, color): (String, Color) = q.difficulty <= 2 ? ("EASY", Tidbits.Palette.mint)
                : q.difficulty == 3 ? ("MEDIUM", Tidbits.Palette.blue) : ("HARD", Tidbits.Palette.coral)
            Text(label)
                .font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 5)
                .background(Capsule().fill(color))
        }
        .padding(.bottom, 4)
    }

    /// Wave A: the on-screen countdown — the room watches the clock; turns coral at ≤5s.
    @ViewBuilder private func countdown(deadlineMs: Int) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let remaining = max(0, deadlineMs - Int(Date().timeIntervalSince1970 * 1000))
            let secs = Int((Double(remaining) / 1000).rounded(.up))
            Text(secs >= 60 ? String(format: "%d:%02d", secs / 60, secs % 60) : "\(secs)")
                .font(.system(size: 60, weight: .black, design: .rounded)).monospacedDigit()
                .foregroundStyle(secs <= 5 ? Tidbits.Palette.coral : Tidbits.Palette.ink)
                .contentTransition(.numericText())
        }
    }

    /// A8/poll: live vote distribution — bars grow as answers land; the correct
    /// option lights mint on reveal. The "how did the room vote" show moment.
    private func voteTally(_ q: Question, revealed: Bool) -> some View {
        let answers = coordinator.net?.answers ?? [:]
        let counts = q.options.indices.map { i in answers.values.filter { $0.choice == i }.count }
        let total = max(counts.reduce(0, +), 1)
        return VStack(spacing: 10) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, opt in
                let n = counts[i]
                let correct = revealed && i == q.correctIndex
                HStack(spacing: 14) {
                    Text(opt).font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(correct ? Tidbits.Palette.mint : Tidbits.Palette.ink)
                        // A fixed 300pt with lineLimit(1) TRUNCATED the option on the
                        // big screen — measured: the correct answer read "Imperial House
                        // of Jap…". An answer the room cannot read is the same failure as
                        // a question it cannot read, and worse on the reveal, because
                        // this is the moment the answer is announced. Wider, two lines,
                        // and it shrinks rather than cuts.
                        .frame(width: 420, alignment: .leading)
                        .lineLimit(2).minimumScaleFactor(0.55)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Tidbits.Palette.surface)
                            Capsule().fill(correct ? Tidbits.Palette.mint : Tidbits.Palette.blue.opacity(revealed ? 0.35 : 0.7))
                                .frame(width: max(10, geo.size.width * CGFloat(n) / CGFloat(total)))
                        }
                    }.frame(height: 30)
                    Text("\(n)").font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(Tidbits.Palette.ink).frame(width: 52)
                }
            }
        }
        .frame(maxWidth: 900)
        .animation(showAnim, value: counts)
    }

    /// Wave C: the hybrid standings — networked phone teams AND in-room paper teams merged into
    /// ONE ranked list (the differentiator the field doesn't ship well).
    struct UnifiedStanding: Identifiable { let id: String; let name: String; let score: Int; let paper: Bool }
    private func unifiedStandings(_ s: LiveHostSession) -> [UnifiedStanding] {
        var rows: [UnifiedStanding] = []
        if let net = coordinator.net {
            for (uid, team) in net.teams where !s.blockedTeams.contains(uid) {   // Wave C: moderation — hidden names don't project
                rows.append(.init(id: uid, name: team.name, score: net.scores[uid] ?? 0, paper: false))
            }
        }
        for t in s.teams { rows.append(.init(id: "paper:\(t.id)", name: t.name, score: t.score, paper: true)) }
        return rows.sorted { $0.score > $1.score }
    }

    private func leaderboard(_ s: LiveHostSession) -> some View {
        let rows = unifiedStandings(s)
        return VStack(alignment: .leading, spacing: 10) {
            if rows.isEmpty {
                Text("Teams appear here as they join.").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
            } else {
                ForEach(Array(rows.prefix(5).enumerated()), id: \.element.id) { i, team in
                    HStack(spacing: 14) {
                        Text("\(i + 1)").font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(i == 0 ? Tidbits.Palette.ink : Tidbits.Palette.inkSoft).frame(width: 32)
                        if i == 0 { Image(systemName: "crown.fill").font(.system(size: 22)).foregroundStyle(Tidbits.Palette.yellow) }
                        Image(systemName: team.paper ? "pencil" : "iphone").font(.system(size: 15)).foregroundStyle(Tidbits.Palette.inkSoft)   // Wave C: paper vs phone
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
        .animation(showAnim, value: rows.prefix(5).map(\.id))   // A8.2 the leaderboard climbs
    }

    private func standings(_ s: LiveHostSession) -> some View {
        let rows = unifiedStandings(s)
        return VStack(spacing: 20) {
            let outcome = StandingsOutcome.headline(rows.map { ($0.name, $0.score) }, empty: "")
            if let winner = rows.first, winner.score > 0 {
                HStack(spacing: 16) {
                    Image(systemName: "party.popper.fill").font(.system(size: 40)).foregroundStyle(Tidbits.Palette.coral)
                    Text(outcome).font(.system(size: 60, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink).lineLimit(1).minimumScaleFactor(0.4)
                    Image(systemName: "party.popper.fill").font(.system(size: 40)).foregroundStyle(Tidbits.Palette.coral).scaleEffect(x: -1)
                }
                .symbolEffect(.bounce, options: reduceMotion ? .nonRepeating : .repeating)
            } else {
                Text("FINAL STANDINGS").font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            }
            // The night's CLIMAX was a blank screen with zero teams: the ForEach
            // below renders nothing and there was no empty state, so a host who
            // ends a night before anyone joined — or who ran the whole thing on
            // paper without adding the teams — puts "FINAL STANDINGS" over an empty
            // wall in front of the room. Every list gets its empty state
            // (universal-feature-states); this one is on a projector.
            if rows.isEmpty {
                VStack(spacing: 14) {
                    Text("No teams to rank")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(Tidbits.Palette.inkSoft)
                    Text("Add teams in the cockpit, or have players scan the code to join.")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tidbits.Palette.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)
            }
            ForEach(Array(rows.prefix(8).enumerated()), id: \.element.id) { i, team in
                HStack(spacing: 20) {
                    Text("\(i + 1)").font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft).frame(width: 60)
                    if i == 0 { Image(systemName: "crown.fill").font(.system(size: 34)).foregroundStyle(Tidbits.Palette.yellow) }
                    Image(systemName: team.paper ? "pencil" : "iphone").font(.system(size: 22)).foregroundStyle(Tidbits.Palette.inkSoft)
                    Text(team.name).font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink).lineLimit(1).minimumScaleFactor(0.5)
                    Spacer()
                    Text("\(team.score)").font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                }
                .padding(.horizontal, 28).padding(.vertical, 16)
                .frame(maxWidth: 760)
                .background(RoundedRectangle(cornerRadius: 18).fill(i == 0 ? Tidbits.Palette.yellow : Tidbits.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Tidbits.Palette.border, lineWidth: 3))
            }
            if !s.event.leadCaptureURL.isEmpty, let qr = makeLiveQR(s.event.leadCaptureURL) {   // Wave D: lead capture
                VStack(spacing: 12) {
                    Text("Join \(s.event.venue.isEmpty ? "our" : "\(s.event.venue)'s") mailing list")
                        .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
                    Image(nsImage: qr).interpolation(.none).resizable().frame(width: 180, height: 180)
                        .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(.white))
                }
                .padding(.top, 24)
            }
        }
        .padding(48)
    }
}
#endif
