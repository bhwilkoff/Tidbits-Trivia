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
// MARK: - What the room sees (macOS-DESIGN §A8.7)

/// The host's per-element switches for the live slide. Everything except the
/// question and its answer can be turned off from the cockpit: a room that only
/// needs the question, or a host projecting onto a small screen, strips the
/// slide down instead of living with every element the show system offers.
///
/// Persisted, because a host sets this up once per venue and expects it back next
/// week. `TIDBITS_LIVE_HIDE=title,roundLine,...` applies a set for ONE launch
/// without persisting it, so the harness can photograph the stripped slide
/// without leaving the host's real preference changed underneath them (the QA
/// build shares the sandbox container with the installed app).
@Observable
@MainActor
final class LiveProjectorElements {
    static let shared = LiveProjectorElements()

    struct Element: Identifiable, Hashable {
        let id: String
        let title: String
    }
    /// Every switchable element, in the order the cockpit menu lists them —
    /// top of the slide to bottom.
    static let all: [Element] = [
        Element(id: "title", title: "Event name & venue"),
        Element(id: "roundLine", title: "Round line"),
        Element(id: "countdown", title: "Countdown"),
        Element(id: "chrome", title: "Format & difficulty"),
        Element(id: "picture", title: "Question picture"),
        Element(id: "tally", title: "Live vote bars"),
        Element(id: "status", title: "\"Answer on your phones\""),
        Element(id: "story", title: "Story on reveal"),
        Element(id: "teams", title: "Team standings strip"),
        Element(id: "joinPanel", title: "Scan-to-join panel"),
        Element(id: "sponsor", title: "Sponsor footer"),
    ]

    private static let key = "tidbits.projector.hidden"
    private let persists: Bool
    private(set) var hidden: Set<String> {
        didSet { if persists { UserDefaults.standard.set(Array(hidden).sorted(), forKey: Self.key) } }
    }

    init() {
        if let raw = ProcessInfo.processInfo.environment["TIDBITS_LIVE_HIDE"], !raw.isEmpty {
            hidden = Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            persists = false
        } else {
            hidden = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
            persists = true
        }
    }

    func shows(_ id: String) -> Bool { !hidden.contains(id) }
    func set(_ id: String, shown: Bool) { if shown { hidden.remove(id) } else { hidden.insert(id) } }
    func showEverything() { hidden = [] }
    var hiddenCount: Int { hidden.count }
}

struct LiveBigScreen_macOS: View {
    @Environment(LiveHostCoordinator.self) private var coordinator
    private var el: LiveProjectorElements { LiveProjectorElements.shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// §A8.5 — one show-timing spring, disabled under reduce-motion.
    private var showAnim: Animation? { reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.72) }
    /// A8.3 — the round number currently being announced (full-screen card), nil = none.
    @State private var introRound: Int?

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            // A8.9: one design canvas, scaled to the window — every slide is
            // composed at 1280x720 and fits any display without a single
            // hand-computed clearance.
            ProjectorCanvas(size: Self.canvas) {
                ZStack {
                    if let s = coordinator.session {
                        if s.showScores && !s.finished { standings(s, interim: true).transition(.opacity) }
                        // G5: the pick-a-category grid. Ahead of the break/standings slides
                        // because it is a phase of a LIVE round, not an interruption of one.
                        else if s.showBoard, let b = s.currentRoundBoard { boardSlide(b, chooser: s.boardChooser).transition(.opacity) }
                        else if s.onBreak { breakSlide(s).transition(.opacity) }   // adaptability: intermission hold
                        else if s.finished { standings(s).transition(.opacity) } else { live(s).transition(.opacity) }
                    } else {
                        splash.transition(.opacity)
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        // A8.10: a projector goes full screen. Double-click anywhere on the slide.
        .onTapGesture(count: 2) { LiveProjectorWindow.toggleFullScreen() }
        // TIDBITS_LIVE_FULLSCREEN=1 → the projector goes full screen on its own,
        // so the harness can photograph the state a real night runs in. No-op
        // in production.
        .task {
            guard ProcessInfo.processInfo.environment["TIDBITS_LIVE_FULLSCREEN"] == "1" else { return }
            try? await Task.sleep(for: .seconds(1.5))
            LiveProjectorWindow.diag("hook fired; isFullScreen=\(LiveProjectorWindow.isFullScreen)")
            if !LiveProjectorWindow.isFullScreen { LiveProjectorWindow.toggleFullScreen() }
        }
        .animation(showAnim, value: coordinator.session?.finished)
        .overlay {
            if let r = introRound, let s = coordinator.session, !s.finished {
                roundIntroCard(r, title: s.roundTitle, count: s.questionInRound.of,
                               letter: coordinator.session?.currentRoundLetter)
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

    /// G5 — the pick-a-category grid the room chooses from.
    ///
    /// A TAKEN cell keeps its place and goes quiet rather than disappearing: the
    /// room reads the board as a map of what is left, and a grid that reflows on
    /// every pick makes them re-find their column each time.
    private func boardSlide(_ board: LiveBoard, chooser: String?) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: max(board.categories.count, 1))
        return ZStack {
            Tidbits.Palette.ink.ignoresSafeArea()
            VStack(spacing: 20) {
                Text(chooser.map { "\($0.uppercased()) PICKS" } ?? "PICK A CATEGORY")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.coral)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(board.categories, id: \.self) { c in
                        Text(TriviaCategory.named(c).name.uppercased())
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).lineLimit(2).minimumScaleFactor(0.6)
                    }
                    ForEach(board.tiers, id: \.self) { t in
                        ForEach(board.categories, id: \.self) { c in
                            boardCell(board.cell(c, t))
                        }
                    }
                }
                Text("\(board.remaining.count) left · " + pluralized(board.pointsRemaining, "point") + " on the board")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(50)
        }
    }

    /// One cell. A HOLE (nil) is drawn as an empty slot, never as a pickable tile —
    /// the room must not be able to choose a cell the host cannot read.
    @ViewBuilder private func boardCell(_ cell: LiveBoardCell?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        if let cell {
            Text("\(cell.points)")
                .font(.system(size: 44, weight: .black, design: .rounded)).monospacedDigit()
                .foregroundStyle(cell.taken ? .white.opacity(0.22) : Tidbits.Palette.coral)
                .frame(maxWidth: .infinity).frame(height: 88)
                .background(shape.fill(cell.taken ? Color.white.opacity(0.04) : Color.white.opacity(0.10)))
                .overlay(shape.strokeBorder(.white.opacity(cell.taken ? 0.08 : 0.28), lineWidth: 2))
        } else {
            shape.fill(Color.white.opacity(0.03))
                .frame(maxWidth: .infinity).frame(height: 88)
        }
    }

    /// A8.3 — the full-screen round announcement ("ROUND 2 · HISTORY · 6 questions").
    private func roundIntroCard(_ round: Int, title: String, count: Int,
                                letter: Character? = nil) -> some View {
        ZStack {
            Tidbits.Palette.ink.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("ROUND \(round)").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                Text(title.isEmpty ? "LET'S PLAY" : title.uppercased())
                    .font(.system(size: 88, weight: .black, design: .rounded)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text("\(count) question\(count == 1 ? "" : "s")").font(.system(size: 32, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                // G4: the room must be told the rule, in the one moment the whole
                // room is looking at the screen. A host who only says it aloud
                // loses every table that was still ordering drinks.
                if let letter {
                    Text(LiveLetterRound.banner(for: letter))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(Tidbits.Palette.coral)
                        .padding(.top, 6)
                }
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
            sponsorLine(s).padding(.top, 20)
        }
    }

    // MARK: - The live slide (macOS-DESIGN A8.9: everything in the flow, the slide fits the window)

    /// The design canvas every slide is laid out on, then scaled to the window.
    /// Sizes below are canvas points. A 4K projector, a 720p bar TV and a
    /// laptop preview all show the SAME composition at the same proportions.
    static let canvas = CGSize(width: 1280, height: 720)

    private func live(_ s: LiveHostSession) -> some View {
        let showBottom = el.shows("teams") || (el.shows("joinPanel") && coordinator.net?.isOpen == true)
        return VStack(spacing: 0) {
            header(s)
            middle(s, bottomShown: showBottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showBottom { bottomRow(s).padding(.top, 12) }
            sponsorLine(s)
        }
        .padding(.horizontal, 36).padding(.top, 24).padding(.bottom, 20)
    }

    /// Event name & venue on the left, round line on the right. Hidden elements
    /// contribute nothing: with both off there is no header band at all.
    @ViewBuilder private func header(_ s: LiveHostSession) -> some View {
        if el.shows("title") || el.shows("roundLine") {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                if el.shows("title") {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(s.event.name.uppercased())
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(Color(hexString: s.event.brandHex) ?? Tidbits.Palette.ink)   // Wave D: white-label brand accent
                            .lineLimit(1).minimumScaleFactor(0.6)
                        if !s.event.venue.isEmpty {
                            Text(s.event.venue).font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(Tidbits.Palette.coral).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                if el.shows("roundLine") {
                    Text("ROUND \(s.roundNumber)/\(s.roundCount) · \(s.roundTitle)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .padding(.bottom, 10)
        }
    }

    /// The question and everything that belongs to it. Laid out top-down at
    /// natural size and then FITTED to whatever height the header and the
    /// bottom row left — so a long prompt, a picture, four vote bars and a
    /// three-line story shrink together instead of one of them landing on
    /// another. The media band yields first; the prompt shrinks before it wraps
    /// past three lines.
    private func middle(_ s: LiveHostSession, bottomShown: Bool) -> some View {
        FitToHeight {
            VStack(spacing: 12) {
                if let q = s.current {
                    let showCountdown = el.shows("countdown") && s.deadlineMs != nil && !s.revealed
                    if el.shows("chrome") || showCountdown {
                        HStack(alignment: .center, spacing: 16) {
                            if el.shows("chrome") { chromeRow(q, s) }
                            Spacer(minLength: 0)
                            if showCountdown, let d = s.deadlineMs { countdown(deadlineMs: d) }
                        }
                    }
                    let hasVideo = LiveVideoPlayer.shared.hasVideo
                    let hasPicture = el.shows("picture") && q.imageURL != nil && !hasVideo
                    let hasMedia = hasPicture || hasVideo
                    let hasVotes = !(coordinator.net?.answers.isEmpty ?? true)
                    // A2.10: a poll IS its tally — it shows even with the tally element switched off.
                    let tallyShown = (el.shows("tally") || s.currentIsPoll) && LiveNightHost.isMCQ(q) && (hasVotes || s.revealed)
                    let storyShown = el.shows("story") && s.revealed && !q.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    // A8.9 resizing: a slide with little on it gives the question the
                    // room — the prompt grows when the bottom band, the media and the
                    // votes are off, and FitToHeight still shrinks it if it must.
                    let sparse = !bottomShown && !hasMedia && !tallyShown && !storyShown
                    Text(q.prompt)
                        .font(.system(size: hasMedia ? 40 : (sparse ? 68 : 50), weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(hasMedia ? 3 : (sparse ? 5 : 4)).minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                        .id(q.id)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    if hasPicture, let img = q.imageURL {
                        LiveQuestionImage(url: img, cornerRadius: 16)
                            .frame(maxWidth: .infinity)
                            .frame(height: s.revealed ? 190 : 300)
                            .id(q.id)
                    }
                    if hasVideo, let vplayer = LiveVideoPlayer.shared.player {   // Wave B: video question
                        VideoPlayer(player: vplayer)
                            .frame(maxWidth: .infinity)
                            .frame(height: 340)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tidbits.Palette.border, lineWidth: 4))
                    }
                    if tallyShown {
                        voteTally(q, revealed: s.revealed && !s.currentIsPoll)   // A8: the room watches the votes land; a poll never lights a "right" bar
                    } else if s.revealed, !s.currentIsPoll {   // a poll has no answer capsule
                        Text(q.correctAnswer)
                            .font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(.white)
                            .lineLimit(2).minimumScaleFactor(0.5)   // a long answer fits the capsule
                            .padding(.horizontal, 28).padding(.vertical, 12)
                            .background(Capsule().fill(Tidbits.Palette.mint))
                            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 4))
                            .shadow(color: Tidbits.Palette.mint.opacity(reduceMotion ? 0 : 0.65), radius: 34)
                            .transition(.scale(scale: 0.55).combined(with: .opacity))   // A8.1 the reveal is theatre
                    } else {
                        // G1: on a buzz round the room needs to SEE who got there
                        // first — that is the whole drama of the format.
                        if s.currentRoundIsBuzz,
                           let uid = LiveNightHost.firstBuzz(coordinator.net?.answers ?? [:],
                                                             excluding: s.buzzedOut) {
                            let who = coordinator.net?.teams[uid]?.name ?? "Team"
                            Text("\(who) buzzed!")
                                .font(.system(size: 40, weight: .black, design: .rounded))
                                .foregroundStyle(Tidbits.Palette.coral)
                                .lineLimit(2).minimumScaleFactor(0.5)
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                        } else if s.currentRoundIsBuzz {
                            Text("BUZZ IN").font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(Tidbits.Palette.inkSoft)
                        } else if el.shows("status") {
                            Text("Answer on your phones").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
                        }
                    }
                    if storyShown {   // Wave A: the story behind the answer — the learning payoff on the big screen
                        let story = q.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
                        do {
                            Text(story)
                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                .foregroundStyle(Tidbits.Palette.inkSoft)
                                .multilineTextAlignment(.center)
                                .lineLimit(3).minimumScaleFactor(0.6)
                                .frame(maxWidth: 1000)
                                .padding(.top, 4)
                                .transition(.opacity)
                            // The charter on the big screen: name the article. Small, under
                            // the story, the same switch — the room learns where it came from.
                            let src = q.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !src.isEmpty {
                                Label("From Wikipedia · \(src)", systemImage: "book.closed")
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Tidbits.Palette.blue)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
            }
            .animation(showAnim, value: s.revealed)
            .animation(showAnim, value: s.current?.id)
        }
    }

    /// The team STRIP and the join card share one band at the bottom of the
    /// slide — in the flow, never over the question. Either alone takes the
    /// whole width; both off means no band.
    private func bottomRow(_ s: LiveHostSession) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            if el.shows("teams") { teamStrip(s) }
            Spacer(minLength: 0)
            if el.shows("joinPanel"), let net = coordinator.net, net.isOpen {
                LiveJoinCard(code: net.code)
            }
        }
    }

    /// A8.7 sponsor footer — one small line in the flow at the very bottom.
    @ViewBuilder private func sponsorLine(_ s: LiveHostSession) -> some View {
        if el.shows("sponsor"), !s.event.sponsor.isEmpty {
            Text("Brought to you by \(s.event.sponsor)")
                .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
                .padding(.vertical, 5).padding(.horizontal, 16)
                .background(Capsule().fill(Tidbits.Palette.surface))
                .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                .padding(.top, 10)
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
        return VStack(spacing: 6) {
            ForEach(q.options.indices, id: \.self) { i in
                let correct = revealed && i == q.correctIndex
                HStack(spacing: 12) {
                    Text(q.options[i])
                        .font(.system(size: correct ? 24 : 21, weight: correct ? .black : .heavy, design: .rounded))
                        .foregroundStyle(correct ? Tidbits.Palette.mint : (revealed ? Tidbits.Palette.inkSoft : Tidbits.Palette.ink))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(width: 360, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Tidbits.Palette.surface)
                            Capsule().fill(correct ? Tidbits.Palette.mint : Tidbits.Palette.blue.opacity(revealed ? 0.35 : 0.8))
                                .frame(width: max(10, geo.size.width * CGFloat(counts[i]) / CGFloat(total)))
                        }
                    }.frame(height: 22)
                    Text("\(counts[i])").font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(Tidbits.Palette.ink).frame(width: 44, alignment: .trailing)
                }
                .animation(showAnim, value: counts[i])
            }
        }
        .frame(maxWidth: 900)
    }

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

    /// A8.2/A8.7: the top five as one ROW of chips — a strip, not a column. Five
    /// stacked rows was 300pt of the slide and the thing that sat on the prompt.
    private func teamStrip(_ s: LiveHostSession) -> some View {
        let rows = Array(unifiedStandings(s).prefix(5))
        return FlowLayout(spacing: 8) {
            if rows.isEmpty {
                Text("Teams appear here as they join.").font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, team in
                    HStack(spacing: 8) {
                        if i == 0 { Image(systemName: "crown.fill").font(.system(size: 15)).foregroundStyle(Tidbits.Palette.yellow) }
                        else { Text("\(i + 1)").font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft) }
                        Text(team.name).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(team.score)").font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(Tidbits.Palette.ink)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(i == 0 ? Tidbits.Palette.yellow : Tidbits.Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                    .transition(.opacity)
                }
            }
        }
        .animation(showAnim, value: rows.map(\.id))   // A8.2 the leaderboard climbs
    }

    private func standings(_ s: LiveHostSession, interim: Bool = false) -> some View {
        let rows = unifiedStandings(s)
        return FitToHeight { VStack(spacing: 16) {
            let outcome = StandingsOutcome.headline(rows.map { ($0.name, $0.score) }, empty: "")
            if interim {
                // Between rounds the headline is the POSITION, not a winner: naming
                // a champion mid-night is wrong, and the celebration belongs to the
                // final slide.
                Text("SCORES AFTER ROUND \(s.roundNumber)")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
            } else if let winner = rows.first, winner.score > 0 {
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
                    Text(interim ? "No scores yet" : "No teams to rank")
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
            sponsorLine(s)
        } }
        .padding(.horizontal, 48).padding(.vertical, 24)
    }
}

// MARK: - The projector window (A8.10: full screen is first-class)

enum LiveProjectorWindow {
    static let id = "tidbits-bigscreen"
    /// SwiftUI does not promise the scene id lands on `NSWindow.identifier`
    /// (measured: it did not), so the title is the fallback — the projector is
    /// the only window titled "Tidbits Live".
    @MainActor static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == id }
            ?? NSApp.windows.first { $0.title == "Tidbits Live" }
    }
    @MainActor static var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }
    @MainActor static func toggleFullScreen() {
        guard let w = window else { diag("toggle: no window; titles=\(NSApp.windows.map(\.title))"); return }
        w.collectionBehavior.insert(.fullScreenPrimary)
        diag("toggle: \(w.title) fullScreen=\(w.styleMask.contains(.fullScreen))")
        w.toggleFullScreen(nil)
    }
    /// TIDBITS_LIVE_DIAG=1 writes what the full-screen path saw to the app's
    /// temp directory — the only way to read it when launched by LaunchServices.
    static func diag(_ line: String) {
        guard ProcessInfo.processInfo.environment["TIDBITS_LIVE_DIAG"] == "1" else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("projector-diag.txt")
        let text = ((try? String(contentsOf: url, encoding: .utf8)) ?? "") + line + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
    /// Put the projector on a given display and fill it. The host's laptop is
    /// screen 0; the projector is usually the other one.
    @MainActor static func fullScreen(on screen: NSScreen) {
        guard let w = window else { return }
        if w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
        w.setFrame(screen.visibleFrame, display: true)
        w.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { w.toggleFullScreen(nil) }
    }
}

// MARK: - Layout helpers (A8.9)

/// Chips that WRAP to the next line when the row is full — the team strip
/// next to the join card, instead of five chips squeezed into "The Qui…".
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: width.isFinite ? min(width, maxX) : maxX, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

/// Scales a fixed design canvas to whatever window it is in — the projector
/// version of a Viewbox. The composition is authored ONCE at
/// `LiveBigScreen_macOS.canvas`; a 4K wall and a laptop preview show the same
/// slide, letterboxed on a non-16:9 display.
struct ProjectorCanvas<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: () -> Content
    var body: some View {
        GeometryReader { g in
            let scale = min(g.size.width / size.width, g.size.height / size.height)
            content()
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: g.size.width, height: g.size.height)
        }
    }
}

/// Lays its content out at natural height and, when that is taller than the
/// space it was given, scales it down uniformly to fit — the rule that makes
/// "everything on" and "everything off" both readable without a fixed band
/// height anywhere. Content shorter than the space is centred.
struct FitToHeight<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var natural: CGFloat = 0
    var body: some View {
        GeometryReader { g in
            let scale = natural > 0 ? min(1, g.size.height / natural) : 1
            content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: g.size.width)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { natural = $0 }
                .scaleEffect(scale, anchor: .center)
                .frame(width: g.size.width, height: g.size.height)
        }
    }
}

/// The join card as a compact horizontal band — QR beside the code, ~120pt
/// tall — instead of the 280pt vertical panel that used to float over the
/// question.
struct LiveJoinCard: View {
    let code: String
    var body: some View {
        HStack(spacing: 14) {
            if let img = makeLiveQR(liveJoinURL(code)) {
                Image(nsImage: img).interpolation(.none).resizable()
                    .frame(width: 84, height: 84)
                    .padding(6).background(RoundedRectangle(cornerRadius: 10).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("SCAN TO JOIN").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
                Text("CODE \(code)").font(.system(size: 26, weight: .black, design: .monospaced)).foregroundStyle(Tidbits.Palette.ink).kerning(2)
                Text("or tidbitstrivia.com/live").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Tidbits.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tidbits.Palette.border, lineWidth: 3))
    }
}

// MARK: - Question pictures on the host surfaces

/// A question's picture on the projector and in the cockpit. Imported Kahoot
/// nights carry photos and animated GIFs, and SwiftUI's `Image` shows a GIF's
/// FIRST FRAME only, so this is an `NSImageView` with `animates` on. A failed
/// load says so on the glass: a blank band on the projector is the one failure
/// nobody in the room can diagnose, and a night that "looked complete" in the
/// builder is exactly how it would ship.
struct LiveQuestionImage: View {
    let url: URL
    var cornerRadius: CGFloat = 12
    @State private var state: LiveImageLoader.State = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                RoundedRectangle(cornerRadius: cornerRadius).fill(Tidbits.Palette.bgDeep)
                    .overlay(ProgressView())
            case .failed:
                RoundedRectangle(cornerRadius: cornerRadius).fill(Tidbits.Palette.bgDeep)
                    .overlay(
                        Label("Picture unavailable", systemImage: "photo.badge.exclamationmark")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tidbits.Palette.inkSoft))
            case .loaded(let image):
                // A GIF animates through AppKit; a still picture is a SwiftUI Image,
                // which scales cleanly and renders offline (ImageRenderer draws no
                // NSView, so the projector sim showed every picture as unavailable).
                if Self.isAnimated(image) {
                    AnimatedImageView(image: image)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                } else {
                    Image(nsImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            }
        }
        .task(id: url) {
            state = .loading
            state = await LiveImageLoader.shared.load(url)
        }
        // A picture already in the cache is drawn on the first frame — the offline
        // renderer (ImageRenderer) never runs `.task`, and a real advance to a
        // prefetched picture should not flash the spinner either.
        .onAppear {
            if let img = LiveImageLoader.shared.cached(url) { state = .loaded(img) }
        }
    }

    static func isAnimated(_ image: NSImage) -> Bool {
        guard let rep = image.representations.first as? NSBitmapImageRep,
              let frames = rep.value(forProperty: .frameCount) as? Int else { return false }
        return frames > 1
    }
}

/// One decoded-image cache for the cockpit and the projector, so the same
/// picture is fetched once and the projector shows it the instant the host
/// advances. `prefetch` warms it with the whole night when hosting starts, which
/// is what keeps a slow venue Wi-Fi from becoming a blank projector mid-round.
@MainActor
final class LiveImageLoader {
    static let shared = LiveImageLoader()
    enum State { case loading, failed, loaded(NSImage) }

    private var cache: [URL: NSImage] = [:]
    private var inflight: [URL: Task<NSImage?, Never>] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: c)
    }()

    func cached(_ url: URL) -> NSImage? { cache[url] }

    func load(_ url: URL) async -> State {
        if let img = cache[url] { return .loaded(img) }
        if url.isFileURL {   // a picture on disk (the offline renderer, a dropped file)
            guard let img = NSImage(contentsOf: url) else { return .failed }
            cache[url] = img
            return .loaded(img)
        }
        // A `tidbits-media:` reference is a file in the store (LIVE-PACKAGE-FORMAT
        // §5.2); anything else is fetched. A missing store file is a visible failure.
        let task = inflight[url] ?? Task { [session] in
            if LiveMediaStore.id(from: url) != nil {
                guard let file = LiveMediaStore.resolve(url), let data = try? Data(contentsOf: file) else { return nil }
                return NSImage(data: data)
            }
            guard let (data, resp) = try? await session.data(from: url) else { return nil }
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            return NSImage(data: data)
        }
        inflight[url] = task
        let img = await task.value
        inflight[url] = nil
        guard let img else { return .failed }
        cache[url] = img
        return .loaded(img)
    }

    func prefetch(_ urls: [URL]) {
        for url in urls where cache[url] == nil && inflight[url] == nil {
            Task { _ = await load(url) }
        }
    }
}

/// `NSImageView` fills whatever SwiftUI proposes and scales the picture
/// proportionally inside it, so the band's height is the layout's decision and
/// the picture never distorts.
private struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.imageAlignment = .alignCenter
        v.animates = true
        v.image = image
        for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            v.setContentHuggingPriority(.defaultLow, for: axis)
            v.setContentCompressionResistancePriority(.defaultLow, for: axis)
        }
        return v
    }

    func updateNSView(_ v: NSImageView, context: Context) {
        if v.image !== image { v.image = image }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? image.size.width, height: proposal.height ?? image.size.height)
    }
}
#endif
