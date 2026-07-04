#if os(tvOS)
import SwiftUI

/// Unified "Join a game" on Apple TV. One 4-letter code box joins any room on the
/// shared Firebase RTDB backend (`live/{code}`) — a Mac-hosted **Tidbits Live**
/// event OR a casual **Trivia Night** hosted from any device (owner architecture:
/// both ride one backend). Renders on the shared `LivePlayerClient`. Same verb
/// everywhere; the player never has to know which product hosts them.
struct TVJoinGameContainer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = LivePlayerClient.lastCode
    @State private var name = LivePlayerClient.lastTeam
    @State private var probing = false
    @State private var error: String?
    @State private var route: Route = .form
    @FocusState private var focus: Field?
    private enum Field: Hashable { case code, name, join }
    private enum Route: Equatable { case form, live }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            switch route {
            case .form:  joinForm
            case .live:  TVLivePlayerView(code: code, team: name, onClose: { dismiss() })
            }
        }
        .onExitCommand { if route == .form { dismiss() } }
        .task {
            // CI/device hook: auto-resolve a known code to verify the flow headless.
            if ProcessInfo.processInfo.environment["TIDBITS_LIVE_AUTOJOIN"] == "1",
               code.count >= 4, route == .form { await resolve() }
        }
    }

    private var joinForm: some View {
        VStack(alignment: .leading, spacing: 36) {
            Text("JOIN A GAME").font(.system(size: 64, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("Enter the code the host is showing.")
                .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            TextField("CODE", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .onChange(of: code) { _, v in code = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(4)) }
                .font(.system(size: 44, weight: .black, design: .rounded))
                .frame(maxWidth: 600).focused($focus, equals: .code)
            TextField("Your team name", text: $name)
                .font(.system(size: 33, weight: .bold, design: .rounded))
                .frame(maxWidth: 600).focused($focus, equals: .name)
            if probing {
                Label("Finding your game…", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
            }
            Button(probing ? "Finding…" : "Join") { Task { await resolve() } }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                .focused($focus, equals: .join).disabled(code.count < 4 || probing)
            Text("Enter a host's code — a Tidbits Live event or a Trivia Night. Works from anywhere.")
                .font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
        .padding(90)
        .defaultFocus($focus, .code)
    }

    /// Confirm a room exists at this code, then join it (Live event or Trivia
    /// Night — same backend). A miss is a clear not-found.
    private func resolve() async {
        let c = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard c.count >= 4 else { return }
        probing = true; error = nil
        let exists = (try? await FirebaseRTDB.shared.exists("\(LiveRoom.path(c))/meta")) ?? false
        probing = false
        if exists { route = .live } else { error = "No game found for that code." }
    }
}

// MARK: - Tidbits Live player (ten-foot)

/// A player in a Mac-hosted Tidbits Live event, rendered for the living room. The
/// tvOS twin of iOS `LiveJoinView`'s player, on the same shared `LivePlayerClient`
/// + `LiveRoom` contract. Auto-joins on appear with the code/team from the front.
struct TVLivePlayerView: View {
    let code: String
    let team: String
    var onClose: () -> Void
    @State private var client = LivePlayerClient()
    @FocusState private var focusedOption: Int?

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            content
        }
        .task { if !client.joined && !client.joining { await client.join(code: code, team: team) } }
        .onExitCommand { Task { await client.leave(); onClose() } }
    }

    @ViewBuilder private var content: some View {
        if !client.joined {
            connecting
        } else if let p = client.pub, p.phase != LiveRoom.Phase.ended, client.meta?.state != "ended" {
            VStack(spacing: 0) { header; ScrollView { questionView(p).padding(90) } }
        } else if client.meta?.state == "ended" || client.pub?.phase == LiveRoom.Phase.ended {
            ended
        } else {
            VStack(spacing: 0) { header; Spacer(); lobby; Spacer() }
        }
    }

    private var connecting: some View {
        VStack(spacing: 28) {
            if let e = client.errorText {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                Button("Back", action: onClose).buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
            } else {
                Label("Joining \(code)…", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 33, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
        }
        .padding(90)
    }

    private var header: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(team.isEmpty ? "Your team" : team).font(.system(size: 33, weight: .heavy, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                Text("CODE \(client.code)").font(.system(size: 21, weight: .heavy, design: .monospaced)).foregroundStyle(TVTheme.textSoft)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(String(client.score)).font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text("POINTS").font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
        }
        .padding(.horizontal, 90).padding(.top, 60).padding(.bottom, 20)
    }

    private var lobby: some View {
        VStack(spacing: 18) {
            Text("YOU'RE IN").font(.system(size: 25, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.bg)
                .padding(.horizontal, 22).padding(.vertical, 9).background(Capsule().fill(Tidbits.Palette.mint))
            Text("Waiting for the host to start…").font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("Keep this on screen — questions appear here.").font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
    }

    private var ended: some View {
        VStack(spacing: 26) {
            Text("THAT'S A WRAP").font(.system(size: 31, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.bg)
                .padding(.horizontal, 24).padding(.vertical, 10).background(Capsule().fill(Tidbits.Palette.coral))
            Text("Final score: \(client.score)").font(.system(size: 52, weight: .black, design: .rounded)).foregroundStyle(.white)
            Button("Done") { Task { await client.leave(); onClose() } }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
        }
        .padding(90)
    }

    @ViewBuilder private func questionView(_ p: LiveRoom.Pub) -> some View {
        let revealed = p.phase == LiveRoom.Phase.reveal
        let locked = revealed || client.hasAnswered
        VStack(alignment: .leading, spacing: 30) {
            Text("ROUND \(p.round) · \(p.roundTitle.uppercased()) — Q\(p.qNum)/\(p.qTotal)")
                .font(.system(size: 25, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            if let img = p.imageURL, let url = URL(string: img) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() } else { Color.clear }
                }
                .frame(maxWidth: .infinity, maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Text(p.prompt).font(.system(size: 48, weight: .black, design: .rounded)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let n = p.numeric {
                TVNumericAnswer(spec: n, locked: locked) { v in Task { await client.submit(number: v) } }.id(p.qid)
            } else if let options = p.options, !options.isEmpty {
                VStack(spacing: 20) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                        optionButton(i, opt, p: p, revealed: revealed)
                    }
                }
                .defaultFocus($focusedOption, 0)
            } else if p.orderItems != nil || p.matchKeys != nil || p.enumTarget != nil {
                Label("This round plays best on a phone — open Tidbits → Join a game on a handset to answer.", systemImage: "iphone")
                    .font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            } else {
                TVTextAnswer(locked: locked) { t in Task { await client.submit(text: t) } }.id(p.qid)
            }
            statusNote(p, revealed: revealed)
        }
    }

    private func optionButton(_ i: Int, _ opt: String, p: LiveRoom.Pub, revealed: Bool) -> some View {
        let chosen = client.chosen == i
        let state: TVLiveOptionState = revealed
            ? (p.answerIndex == i ? .correct : (chosen ? .wrong : .normal))
            : (chosen ? .chosen : .normal)
        return Button { Task { await client.submit(choice: i) } } label: {
            HStack(spacing: 20) {
                Text(String(i + 1)).font(.system(size: 27, weight: .black)).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.35)))
                Text(opt).font(.system(size: 33, weight: .bold, design: .rounded)).foregroundStyle(.white).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(TVLiveOptionStyle(state: state))
        .focused($focusedOption, equals: i)
        .disabled(revealed || client.hasAnswered)
    }

    @ViewBuilder private func statusNote(_ p: LiveRoom.Pub, revealed: Bool) -> some View {
        let note: (String, Color) = revealed
            ? (client.chosen == p.answerIndex ? ("Correct!", Tidbits.Palette.mint) : client.chosen == nil ? ("No answer submitted.", TVTheme.textSoft) : ("Not this time.", Tidbits.Palette.coral))
            : (client.hasAnswered ? ("Locked in — waiting for the reveal…", Tidbits.Palette.mint) : ("Choose your answer with the remote.", TVTheme.textSoft))
        Text(note.0).font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(note.1).padding(.top, 8)
    }
}

/// Ten-foot numeric estimate: a focusable −/+ stepper + Submit (tvOS has no Slider).
private struct TVNumericAnswer: View {
    let spec: LiveRoom.Numeric
    let locked: Bool
    var onSubmit: (Double) -> Void
    @State private var value: Double
    @State private var sent = false
    init(spec: LiveRoom.Numeric, locked: Bool, onSubmit: @escaping (Double) -> Void) {
        self.spec = spec; self.locked = locked; self.onSubmit = onSubmit
        _value = State(initialValue: ((spec.min + spec.max) / 2).rounded())
    }
    private var step: Double { spec.step > 0 ? spec.step : 1 }
    var body: some View {
        HStack(spacing: 28) {
            Button("−") { value = max(spec.min, value - step) }.buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false)).disabled(locked || sent)
            Text(value == value.rounded() ? "\(Int(value))\(unit)" : String(format: "%.1f%@", value, unit))
                .font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(.white).frame(minWidth: 220)
            Button("+") { value = min(spec.max, value + step) }.buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false)).disabled(locked || sent)
            if !sent {
                Button("Submit") { sent = true; onSubmit(value) }.buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false)).disabled(locked)
            }
        }
    }
    private var unit: String { spec.unit.isEmpty ? "" : " \(spec.unit)" }
}

/// Ten-foot free-text answer (uses the tvOS on-screen keyboard).
private struct TVTextAnswer: View {
    let locked: Bool
    var onSubmit: (String) -> Void
    @State private var text = ""
    @State private var sent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TextField("Type your answer", text: $text).autocorrectionDisabled()
                .font(.system(size: 36, weight: .bold, design: .rounded)).frame(maxWidth: 700).disabled(locked || sent)
            if !sent {
                Button("Submit") {
                    let t = text.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { sent = true; onSubmit(t) }
                }.buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false)).disabled(locked)
            }
        }
    }
}

enum TVLiveOptionState { case normal, chosen, correct, wrong }

/// Option row focus treatment for the Live player. Never `.plain` (kills focus on
/// tvOS); brightness/scale mark focus, fill marks answer state after the reveal.
struct TVLiveOptionStyle: ButtonStyle {
    let state: TVLiveOptionState
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration, state: state) }
    struct Inner: View {
        let configuration: Configuration; let state: TVLiveOptionState
        @Environment(\.isFocused) private var focused
        private var base: Color {
            switch state {
            case .correct: return Tidbits.Palette.mint
            case .wrong:   return Tidbits.Palette.coral
            case .chosen:  return Tidbits.Palette.blue
            case .normal:  return TVTheme.panel
            }
        }
        var body: some View {
            let fill = focused && state == .normal ? Tidbits.Palette.blue.opacity(0.85) : base
            configuration.label
                .padding(.horizontal, 34).padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 4))
                .scaleEffect(focused ? 1.03 : 1.0)
                .animation(.easeOut(duration: 0.16), value: focused)
        }
    }
}
#endif
