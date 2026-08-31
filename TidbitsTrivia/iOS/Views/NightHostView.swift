#if os(iOS)
import SwiftUI
import CoreImage.CIFilterBuiltins

/// Host a casual **Trivia Night** from an iPhone/iPad — on the SAME Firebase RTDB
/// backend as Tidbits Live (owner architecture). Build the night, show a join code
/// + QR, then run it as game master: Reveal → Next while phones/web/other apps
/// answer and auto-score. The player side is the unified "Join a game"
/// (`LivePlayerClient` / `FirebaseNet` / `js/live.js`). The rich, Mac-only Tidbits
/// Live host is the marquee cousin on this same plumbing.
struct NightHostView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host: LiveNightHost

    init(plan: NightPlan, category: TriviaCategory) {
        _host = State(wrappedValue: LiveNightHost(plan: plan, category: category))
    }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch host.stage {
            case .lobby:   lobby
            case .playing: playing
            case .ended:   ended
            }
        }
        .task { await host.openRoom() }
        .interactiveDismissDisabled(host.stage == .playing)
    }

    // MARK: Lobby

    private var lobby: some View {
        ScrollView {
            VStack(spacing: 18) {
                topBar("Trivia Night")
                if let e = host.errorText { errorLabel(e) }
                joinCard
                rosterCard
                hostPlaysCard
                toggleCard(title: "Speed bonus", sub: "Fastest correct answers earn +3 / +2 / +1.",
                           isOn: Binding(get: { host.speedBonus }, set: { host.speedBonus = $0 }))
                Button(host.isOpen ? "Start the Night" : "Opening room…") { Task { await host.start() } }
                    .task(id: host.isOpen) {
                        // TIDBITS_NIGHT_AUTOSTART=<seconds> — begin without the press.
                        // Keyed on isOpen so it fires once the room actually exists;
                        // starting before that publishes into a room nobody can join.
                        guard host.isOpen, let wait = DebugHooks.nightAutostart else { return }
                        try? await Task.sleep(for: .seconds(wait))
                        await host.start()
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
                    .disabled(!host.isOpen)
                Text("Players scan the code or join at tidbitstrivia.com/live. You run the questions and reveal for everyone.")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).multilineTextAlignment(.center)
            }
            .padding(Tidbits.Metric.pad)
        }
    }

    private var joinCard: some View {
        VStack(spacing: 12) {
            Text("SCAN TO JOIN").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            if host.isOpen, let img = Self.qrImage("https://tidbitstrivia.com/live/\(host.code)") {
                Image(uiImage: img).interpolation(.none).resizable().frame(width: 180, height: 180)
                    .padding(10).background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            } else {
                ProgressView().frame(width: 180, height: 180)
            }
            Text(host.code.isEmpty ? "----" : host.code)
                .font(.system(size: 40, weight: .black, design: .monospaced)).kerning(6).foregroundStyle(Tidbits.Palette.ink)
            Text("tidbitstrivia.com/live").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(20)
        .chunkyCard(fill: Tidbits.Palette.surface).padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(host.playerCount) IN THE ROOM").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            if host.standings.isEmpty {
                Text("Waiting for players to join…").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
            } else {
                ForEach(host.standings) { t in
                    HStack {
                        Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(Tidbits.Palette.inkSoft)
                        Text(t.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .chunkyCard(fill: Tidbits.Palette.surface).padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var hostPlaysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { host.hostPlays }, set: { host.hostPlays = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I'll play too").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Text("Answer on this device and join the standings.").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                }
            }
            .tint(Tidbits.Palette.coral)
            if host.hostPlays {
                TextField("Your name", text: Binding(get: { host.hostName }, set: { host.hostName = $0 }))
                    .textInputAutocapitalization(.words)
                    .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tidbits.Palette.border, lineWidth: 2))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .chunkyCard(fill: Tidbits.Palette.surface).padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private func toggleCard(title: String, sub: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Text(sub).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
        }
        .tint(Tidbits.Palette.coral)
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .chunkyCard(fill: Tidbits.Palette.surface).padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    // MARK: Playing

    private var playing: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topBar(host.roundTitle.isEmpty ? "Trivia Night" : host.roundTitle)
                if let q = host.current {
                    Text("ROUND \(host.roundNumber)/\(host.roundCount) · Q\(host.questionInRound.n)/\(host.questionInRound.of) · \(host.answeredCount) answered")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    if let img = q.imageURL {
                        AsyncImage(url: img) { phase in
                            if let image = phase.image { image.resizable().scaledToFit() } else if phase.error != nil { EmptyView() } else { ProgressView().frame(maxWidth: .infinity, minHeight: 140) }
                        }
                        .frame(maxWidth: .infinity, maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text(q.prompt).font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if LiveNightHost.isMCQ(q) {
                        ForEach(Array(q.options.enumerated()), id: \.offset) { i, opt in
                            let chosen = host.hostChoice == i
                            let correct = host.revealed && i == q.correctIndex
                            let wrong = host.revealed && chosen && i != q.correctIndex
                            let fill: Color = correct ? Tidbits.Palette.mint : wrong ? Color(red: 0.95, green: 0.82, blue: 0.80) : chosen ? Tidbits.Palette.blue.opacity(0.18) : .white
                            Button {
                                if host.hostPlays { Task { await host.hostAnswer(i) } }
                            } label: {
                                HStack(spacing: 10) {
                                    Text("\(i + 1)").font(.system(size: 14, weight: .black)).foregroundStyle(.white)
                                        .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 7).fill(Tidbits.Palette.ink))
                                    Text(opt).font(Tidbits.TypeRamp.l3).foregroundStyle(correct ? .white : Tidbits.Palette.ink).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .chunkyCard(fill: fill).padding(.trailing, Tidbits.Metric.shadowOffset)
                            }
                            .buttonStyle(.plain)
                            .disabled(!host.hostPlays || host.revealed || host.hostAnswered)
                        }
                        if host.hostPlays && !host.revealed {
                            Text(host.hostAnswered ? "Locked in — reveal when everyone's ready." : "Tap your answer, then Reveal.")
                                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        }
                    } else {
                        Text("Players answer on their devices. Reveal when everyone's in.")
                            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        if host.revealed {
                            Text("Answer: \(LiveNightHost.answerLine(q))").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading).chunkyCard(fill: Tidbits.Palette.mint)
                        }
                    }
                }
                HStack(spacing: 12) {
                    if !host.revealed {
                        if !host.locked {
                            Button("Lock") { Task { await host.lock() } }
                                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink))
                        }
                        Button("Reveal") { Task { await host.reveal() } }
                            .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.blue, textColor: .white))
                    } else {
                        Button("Next") { Task { await host.next() } }
                            .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
                    }
                }
                if host.locked && !host.revealed {
                    Text("Answers locked — pencils down!").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.coral)
                }
                standingsCard
            }
            .padding(Tidbits.Metric.pad)
        }
    }

    private var standingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STANDINGS").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(Array(host.standings.enumerated()), id: \.element.id) { i, t in
                HStack {
                    if i == 0 { Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow) }
                    Text(t.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Spacer()
                    Text("\(t.score)").font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(Tidbits.Palette.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .chunkyCard(fill: Tidbits.Palette.surface).padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    // MARK: Ended

    private var ended: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(StandingsOutcome.headline(host.standings.map { ($0.name, $0.score) }, empty: "That's a night!"))
                    .font(Tidbits.TypeRamp.l1).foregroundStyle(Tidbits.Palette.ink).multilineTextAlignment(.center)
                standingsCard
                Button("Done") { Task { await host.close(); dismiss() } }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.ink, textColor: .white))
            }
            .padding(Tidbits.Metric.pad)
        }
    }

    // MARK: Chrome

    private func topBar(_ title: String) -> some View {
        HStack {
            Text(title).font(Tidbits.TypeRamp.l1).foregroundStyle(Tidbits.Palette.ink)
            Spacer()
            Button(action: { Task { await host.close(); dismiss() } }) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .black))
            }.tint(Tidbits.Palette.ink)
        }
    }
    private func errorLabel(_ e: String) -> some View {
        Label(e, systemImage: "exclamationmark.triangle.fill").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.coral)
    }

    static func qrImage(_ string: String) -> UIImage? {
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
