#if os(iOS)
import SwiftUI

/// Unified "Join a game" on iPhone/iPad. One code box joins any room on the shared
/// Firebase RTDB backend (`live/{code}`) — a Mac-hosted **Tidbits Live** event OR a
/// casual **Trivia Night** hosted from any device (owner architecture: both ride one
/// backend). Renders on the shared `LivePlayerClient` (native twin of js/live.js).
/// Same verb; the player never has to know which product hosts them.
struct LiveJoinView: View {
    var initialCode: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var client = LivePlayerClient()
    @State private var code = ""
    @State private var team = ""
    @State private var probing = false
    @State private var formError: String?

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            if client.joined { player } else { joinForm }
        }
        .onAppear { if code.isEmpty { code = initialCode.uppercased() } }
        .interactiveDismissDisabled(client.joined)
        .task {
            // CI/device hook: auto-resolve a known room to verify the flow headless.
            if ProcessInfo.processInfo.environment["TIDBITS_LIVE_AUTOJOIN"] == "1",
               !initialCode.isEmpty, !client.joined {
                code = initialCode; team = "iOS Tester"; await resolve()
            }
        }
    }

    /// Confirm a room exists at this code, then join it (Live event or Trivia
    /// Night — same backend). A miss is a clear not-found, not a silent LAN search.
    private func resolve() async {
        let c = code.uppercased().filter { $0.isLetter || $0.isNumber }
        let t = team.trimmingCharacters(in: .whitespaces)
        guard c.count >= 4 else { formError = "Enter the 4-letter code from the screen."; return }
        guard !t.isEmpty else { formError = "Enter a team name."; return }
        formError = nil; probing = true
        let exists = (try? await FirebaseRTDB.shared.exists("\(LiveRoom.path(c))/meta")) ?? false
        probing = false
        if exists { await client.join(code: c, team: t) }
        else { formError = "No game found for that code. Check it and try again." }
    }

    // MARK: Join

    private var joinForm: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("TIDBITS LIVE")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Tidbits.Palette.coral))
                .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            Text("Join the game").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Text("Enter a host's code — a Tidbits Live event or a nearby Trivia Night.").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).multilineTextAlignment(.center)
            TextField("CODE", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .multilineTextAlignment(.center).font(.system(size: 30, weight: .black, design: .monospaced))
                .kerning(8).padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                .onChange(of: code) { _, v in
                    let c = v.uppercased().filter { $0.isLetter || $0.isNumber }
                    if c != v { code = String(c.prefix(4)) } else if c.count > 4 { code = String(c.prefix(4)) }
                }
            TextField("Your team name", text: $team)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            if let e = formError ?? client.errorText {
                Text(e).font(Tidbits.TypeRamp.l5).foregroundStyle(.red)
            }
            Button {
                Task { await resolve() }
            } label: {
                Text(probing || client.joining ? "Joining…" : "Join").frame(maxWidth: .infinity)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
            .disabled(client.joining || probing)
            Button("Cancel") { dismiss() }.font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).padding(.top, 4)
            Spacer()
        }
        .padding(24)
    }

    // MARK: Play

    private var player: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    if let p = client.pub, p.phase != LiveRoom.Phase.ended, client.meta?.state != "ended" {
                        questionView(p)
                    } else if client.meta?.state == "ended" || client.pub?.phase == LiveRoom.Phase.ended {
                        endedView
                    } else {
                        lobbyView
                    }
                }
                .padding(20)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(team.isEmpty ? "Your team" : team).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
                Text("CODE \(client.code)").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(client.score)").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                Text("points").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Button { Task { await client.leave(); dismiss() } } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Tidbits.Palette.ink)
                    .frame(width: 34, height: 34).background(Circle().fill(.white)).overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            }
        }
        .padding(16)
    }

    private var lobbyView: some View {
        VStack(spacing: 10) {
            Text("YOU'RE IN").font(Tidbits.TypeRamp.l5).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(Tidbits.Palette.mint))
            Text("Waiting for the host to start…").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink).multilineTextAlignment(.center)
            Text("Keep this open — questions appear here.").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .padding(.top, 40)
    }

    private var endedView: some View {
        VStack(spacing: 10) {
            Text("THAT'S A WRAP").font(Tidbits.TypeRamp.l5).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(Tidbits.Palette.coral))
            Text("Final score: \(client.score)").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Button("Done") { Task { await client.leave(); dismiss() } }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white)).padding(.top, 8)
        }
        .padding(.top, 40)
    }

    @ViewBuilder private func questionView(_ p: LiveRoom.Pub) -> some View {
        let revealed = p.phase == LiveRoom.Phase.reveal
        VStack(alignment: .leading, spacing: 14) {
            Text("ROUND \(p.round) · \(p.roundTitle.uppercased()) — Q\(p.qNum)/\(p.qTotal)")
                .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
            Text(p.prompt).font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let options = p.options, !options.isEmpty {
                ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                    optionButton(i, opt, p: p, revealed: revealed)
                }
            } else {
                Text("Answer on your team sheet — the host is scoring this round.")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            statusNote(p, revealed: revealed)
        }
    }

    private func optionButton(_ i: Int, _ opt: String, p: LiveRoom.Pub, revealed: Bool) -> some View {
        let chosen = client.chosen == i
        let correct = revealed && p.answerIndex == i
        let wrong = revealed && chosen && p.answerIndex != i
        let fill: Color = correct ? Tidbits.Palette.mint : wrong ? Color(red: 0.95, green: 0.82, blue: 0.80) : chosen ? Tidbits.Palette.blue.opacity(0.18) : .white
        return Button { Task { await client.submit(choice: i) } } label: {
            HStack(spacing: 12) {
                Text("\(i + 1)").font(.system(size: 15, weight: .black)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8).fill(Tidbits.Palette.ink))
                Text(opt).font(Tidbits.TypeRamp.l3).foregroundStyle(correct ? .white : Tidbits.Palette.ink).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).chunkyCard(fill: fill)
        }
        .buttonStyle(.plain)
        .disabled(revealed || client.hasAnswered)
    }

    @ViewBuilder private func statusNote(_ p: LiveRoom.Pub, revealed: Bool) -> some View {
        let note: (String, Color) = revealed
            ? (client.chosen == p.answerIndex ? ("Correct!", Tidbits.Palette.mint) : client.chosen == nil ? ("No answer submitted.", Tidbits.Palette.inkSoft) : ("Not this time.", .red))
            : (client.hasAnswered ? ("Locked in — waiting for the reveal…", Tidbits.Palette.mint) : ("Tap your answer.", Tidbits.Palette.inkSoft))
        Text(note.0).font(Tidbits.TypeRamp.l4).foregroundStyle(note.1).frame(maxWidth: .infinity).padding(.top, 6)
    }
}
#endif
