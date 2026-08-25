#if os(tvOS)
import SwiftUI
import CoreImage.CIFilterBuiltins

/// Host a casual **Trivia Night** from the Apple TV — on the shared Firebase RTDB
/// backend (owner architecture). The living-room screen shows a big join code + a
/// scannable QR; players join on their phones (the unified "Join a game"); the host
/// paces Reveal → Next with the remote. Twin of the iOS `NightHostView`; the Core
/// `LiveNightHost` is shared verbatim.
struct TVNightHostView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host: LiveNightHost
    @FocusState private var focus: Field?
    // F-009 diagnostic: counts Reveal-button action firings; shown on the
    // glass only under TIDBITS_QA_OVERLAY so OCR can tell "press never
    // reached the button" from "action fired but reveal() didn't complete".
    @State private var qaRevealPresses = 0
    private let qaOverlay = ProcessInfo.processInfo.environment["TIDBITS_QA_OVERLAY"] == "1"
    private enum Field: Hashable { case play, speed, start, lock, reveal, next, opt(Int) }

    init(plan: NightPlan, category: TriviaCategory) {
        _host = State(wrappedValue: LiveNightHost(plan: plan, category: category))
    }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            switch host.stage {
            case .lobby:   lobby
            case .playing: playing
            case .ended:   ended
            }
        }
        .task { await host.openRoom() }
        .onExitCommand { Task { await host.close(); dismiss() } }
    }

    // MARK: Lobby

    private var lobby: some View {
        HStack(spacing: 60) {
            VStack(spacing: 18) {
                Text("SCAN TO JOIN").font(.system(size: 25, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                if host.isOpen, let img = Self.qr("https://tidbitstrivia.com/live/\(host.code)") {
                    Image(uiImage: img).interpolation(.none).resizable().frame(width: 320, height: 320)
                        .padding(16).background(RoundedRectangle(cornerRadius: 18).fill(.white))
                } else {
                    ProgressView().frame(width: 320, height: 320)
                }
                Text(host.code.isEmpty ? "----" : host.code)
                    .font(.system(size: 64, weight: .black, design: .monospaced)).kerning(10).foregroundStyle(.white)
                Text("tidbitstrivia.com/live").font(.system(size: 23, weight: .semibold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
            VStack(alignment: .leading, spacing: 28) {
                Text("TRIVIA NIGHT").font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text("\(host.playerCount) in the room").font(.system(size: 31, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                if let e = host.errorText {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                }
                HStack(spacing: 20) {
                    Button(host.hostPlays ? "I'll play too: ON" : "I'll play too: OFF") { host.hostPlays.toggle() }
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.teal, selected: host.hostPlays))
                        .focused($focus, equals: .play)
                    Button(host.speedBonus ? "Speed bonus: ON" : "Speed bonus: OFF") { host.speedBonus.toggle() }
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: host.speedBonus))
                        .focused($focus, equals: .speed)
                }
                Button(host.isOpen ? "Start the Night" : "Opening room…") { Task { await host.start() } }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                    .focused($focus, equals: .start).disabled(!host.isOpen)
                Text("Players scan the code or open Tidbits → Join a game. You run the questions with the remote.")
                    .font(.system(size: 22, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft).frame(maxWidth: 520, alignment: .leading)
            }
        }
        .padding(90)
        .defaultFocus($focus, .start)
    }

    // MARK: Playing

    private var playing: some View {
        HStack(alignment: .top, spacing: 50) {
            VStack(alignment: .leading, spacing: 22) {
                if let q = host.current {
                    Text("ROUND \(host.roundNumber)/\(host.roundCount) · \(host.roundTitle.uppercased()) — Q\(host.questionInRound.n)/\(host.questionInRound.of) · \(host.answeredCount) answered")
                        .font(.system(size: 23, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    if let img = q.imageURL {
                        AsyncImage(url: img) { phase in
                            if let image = phase.image { image.resizable().scaledToFit() } else { Color.clear }
                        }
                        .frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Text(q.prompt).font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    if LiveNightHost.isMCQ(q) {
                        ForEach(Array(q.options.enumerated()), id: \.offset) { i, opt in
                            let chosen = host.hostChoice == i
                            let state: TVLiveOptionState = host.revealed
                                ? (i == q.correctIndex ? .correct : (chosen ? .wrong : .normal))
                                : (chosen ? .chosen : .normal)
                            Button { if host.hostPlays { Task { await host.hostAnswer(i) } } } label: {
                                HStack(spacing: 16) {
                                    Text("\(i + 1)").font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                                        .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.35)))
                                    Text(opt).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(TVLiveOptionStyle(state: state))
                            .focused($focus, equals: .opt(i))
                            .disabled(!host.hostPlays || host.revealed || host.hostAnswered)
                        }
                    } else {
                        Text("Players answer on their devices. Reveal when everyone's in.")
                            .font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        if host.revealed {
                            Text("Answer: \(LiveNightHost.answerLine(q))")
                                .font(.system(size: 31, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.bg)
                                .padding(.horizontal, 22).padding(.vertical, 12).background(RoundedRectangle(cornerRadius: 14).fill(Tidbits.Palette.mint))
                        }
                    }
                    HStack(spacing: 20) {
                        if !host.revealed {
                            if !host.locked {
                                Button("Lock") { Task { await host.lock() } }
                                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.yellow, selected: false)).focused($focus, equals: .lock)
                            }
                            Button("Reveal") { qaRevealPresses += 1; Task { await host.reveal() } }
                                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false)).focused($focus, equals: .reveal)
                        } else {
                            Button("Next") { Task { await host.next() } }
                                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false)).focused($focus, equals: .next)
                        }
                    }
                    if host.locked && !host.revealed {
                        Text("Answers locked — pencils down!").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                    }
                    if qaOverlay {
                        Text("QADBG presses=\(qaRevealPresses) stage=\(String(describing: host.stage)) revealed=\(host.revealed ? 1 : 0) locked=\(host.locked ? 1 : 0)")
                            .font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(Tidbits.Palette.yellow)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            standings.frame(width: 420)
        }
        .padding(70)
        .defaultFocus($focus, host.revealed ? .next : .reveal)
    }

    private var standings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STANDINGS").font(.system(size: 25, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            ForEach(Array(host.standings.prefix(8).enumerated()), id: \.element.id) { i, t in
                HStack {
                    if i == 0 { Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow) }
                    Text(t.name).font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    Text("\(t.score)").font(.system(size: 29, weight: .black, design: .rounded)).foregroundStyle(.white)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(TVTheme.panel))
            }
            if host.standings.isEmpty {
                Text("Players appear here as they join.").font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
        }
    }

    // MARK: Ended

    private var ended: some View {
        VStack(spacing: 30) {
            Text(StandingsOutcome.headline(host.standings.map { ($0.name, $0.score) }, empty: "That's a night!"))
                .font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(.white)
            standings.frame(maxWidth: 640)
            Button("Done") { Task { await host.close(); dismiss() } }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
        }
        .padding(90)
    }

    static func qr(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let ci = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
#endif
