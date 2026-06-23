#if os(iOS)
import SwiftUI

/// The phone side of a TV-hosted Trivia Night — join the Apple TV's room with
/// the code on screen, read the question, buzz, and (if you're first) answer on
/// your own device (Phase-1 Bonjour client, Decision 030). Every phone sees the
/// same live story — who buzzed, who got it, the points, the scoreboard — so it
/// feels like one game everyone's playing together.
struct BuzzerJoinView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var client = BuzzerClient()
    // Pre-filled from the last room this device joined — a recognized device
    // just taps Join (no retyping the code); the host restores its seat + score.
    @State private var code = BuzzerClient.lastCode
    @State private var name = BuzzerClient.lastName

    var body: some View {
        NavigationStack {
            ZStack {
                Tidbits.Palette.bg.ignoresSafeArea()
                switch client.status {
                case .idle, .failed:        joinForm
                case .searching, .connecting: connecting
                case .joined:               buzzer
                }
            }
            .navigationTitle("Trivia Night")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { client.leave(); dismiss() } } }
        }
    }

    // MARK: Join form

    private var joinForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Enter the code on the TV")
                    .font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                TextField("CODE", text: $code)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .onChange(of: code) { _, v in code = String(v.uppercased().prefix(4)) }
                    .padding(16).chunkyCard(fill: Tidbits.Palette.surface)
                    .padding(.trailing, Tidbits.Metric.shadowOffset)
                TextField("Your name", text: $name)
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    .textInputAutocapitalization(.words)
                    .padding(16).chunkyCard(fill: Tidbits.Palette.surface)
                    .padding(.trailing, Tidbits.Metric.shadowOffset)
                if case .failed(let msg) = client.status {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.coral)
                }
                Button("Join") { client.join(code: code, name: name) }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: Tidbits.Palette.coral.legibleForeground))
                    .disabled(code.count < 4)
                Text("On the same Wi-Fi as the Apple TV. You'll be asked to allow local-network access.")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .padding(Tidbits.Metric.pad)
        }
    }

    private var connecting: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large).tint(Tidbits.Palette.ink)
            Text(client.status == .searching ? "Finding the TV…" : "Connecting…")
                .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
            Button("Cancel") { client.leave() }.tint(Tidbits.Palette.inkSoft)
        }
    }

    // MARK: Buzzer + on-device answering

    private var buzzer: some View {
        VStack(spacing: 16) {
            HStack {
                Text(client.roomName ?? "Connected").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                if let seat = client.seat {
                    Text("You're in · seat \(seat)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                }
            }
            .padding(.horizontal, Tidbits.Metric.pad)

            if let prompt = client.prompt {
                ScrollView {
                    VStack(spacing: 14) {
                        Text(prompt).font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).chunkyCard(fill: Tidbits.Palette.surface).padding(.trailing, Tidbits.Metric.shadowOffset)
                        ForEach(Array(client.options.enumerated()), id: \.offset) { i, opt in
                            answerRow(i, opt)
                        }
                        Text(statusLine).font(Tidbits.TypeRamp.l3).foregroundStyle(statusTint)
                            .multilineTextAlignment(.center).padding(.top, 4)
                            .fixedSize(horizontal: false, vertical: true)
                        if betweenQuestions { miniScoreboard }   // the leaderboard moment
                    }
                    .padding(.horizontal, Tidbits.Metric.pad)
                }
                if client.canBuzz { buzzButton }
            } else {
                Spacer()
                Image(systemName: "hourglass").font(.system(size: 44, weight: .bold)).foregroundStyle(Tidbits.Palette.inkSoft)
                Text(client.lockedOut ? "You're out this question — next one's yours." : "Waiting for the next question…")
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft).multilineTextAlignment(.center)
                Spacer()
            }
        }
        .padding(.bottom, 18)
    }

    /// An answer option — tappable only when it's your turn (you won the buzz).
    /// After judging, the correct answer goes green and your wrong pick goes red.
    private func answerRow(_ i: Int, _ opt: String) -> some View {
        let letter = String(UnicodeScalar(65 + i)!)
        return Button { client.submitAnswer(i) } label: {
            HStack(spacing: 10) {
                Text(letter).font(.system(size: 17, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                Text(opt).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14).chunkyCard(fill: rowFill(i)).padding(.trailing, Tidbits.Metric.shadowOffset)
        }
        .buttonStyle(.plain)
        .disabled(!client.isAnswering)
        .opacity(client.isAnswering || rowFill(i) != Tidbits.Palette.surface ? 1 : 0.7)
    }

    private func rowFill(_ i: Int) -> Color {
        if let ci = client.resultCorrectIndex {                 // judged: reveal the answer
            if i == ci { return Tidbits.Palette.mint.opacity(0.3) }
            if i == client.myAnswer && client.resultCorrect == false { return Tidbits.Palette.coral.opacity(0.3) }
        } else if client.myAnswer == i {                        // sent, awaiting judgement
            return Tidbits.Palette.yellow.opacity(0.3)
        }
        return Tidbits.Palette.surface
    }

    private var buzzButton: some View {
        Button { client.buzz() } label: {
            Text("BUZZ")
                .font(.system(size: 52, weight: .black, design: .rounded)).foregroundStyle(.white)
                .frame(width: 200, height: 200)
                .background(Circle().fill(Tidbits.Palette.coral))
                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 5))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .heavy), trigger: client.canBuzz)
    }

    /// The question has resolved (someone got it, or the answer was revealed) —
    /// the leaderboard moment before the next question.
    private var betweenQuestions: Bool { client.resultCorrectIndex != nil }

    private var statusTint: Color {
        if client.resultCorrect == true { return Tidbits.Palette.mint }
        if client.resultCorrect == false { return Tidbits.Palette.coral }
        if client.canBuzz || client.isAnswering { return Tidbits.Palette.ink }
        return Tidbits.Palette.inkSoft
    }

    /// One shared story every phone reads — who buzzed, who got it + points, who
    /// missed and what they said. The buzz-winner sees a personal "You got it!".
    private var statusLine: String {
        let mine = client.winnerSeat == client.seat
        if let name = client.resultName {
            if client.resultCorrect == true {
                let pts = client.resultPoints ?? 0
                return mine ? "You got it! +\(pts) 🎉" : "\(name) got it! +\(pts)"
            } else {                                     // a wrong answer reopened it
                if mine { return "Not quite — buzzers re-open to the others." }
                if let c = client.resultChosen, client.options.indices.contains(c) {
                    return "\(name) said “\(client.options[c])” — buzzers reopen!"
                }
                return "\(name) missed — buzzers reopen!"
            }
        }
        if client.resultCorrectIndex != nil {
            return client.resultTimedOut ? "Time's up — nobody buzzed in." : "Nobody got it right."
        }
        if client.isAnswering { return "You got the buzz! Tap your answer above." }
        if client.myAnswer != nil { return "Answer sent — waiting on the host…" }
        if let who = client.buzzedName { return "🔔 \(who) buzzed in…" }
        if client.lockedOut { return "You're out this question — next one's yours." }
        if client.canBuzz { return "Buzzers are open — tap BUZZ the moment you know it." }
        return "Get ready…"
    }

    /// Standings between questions — your row highlighted, the leader crowned.
    private var miniScoreboard: some View {
        let sorted = client.players.sorted { $0.score > $1.score }
        let leader = sorted.first.flatMap { $0.score > 0 ? $0.seat : nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text("SCOREBOARD").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(sorted) { p in
                HStack(spacing: 8) {
                    if leader == p.seat { Image(systemName: "crown.fill").font(.system(size: 13)).foregroundStyle(Tidbits.Palette.yellow) }
                    Text(p.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Spacer()
                    Text("\(p.score)").font(.system(size: 17, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(Tidbits.Palette.ink)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .chunkyCard(fill: p.seat == client.seat ? Tidbits.Palette.mint.opacity(0.22) : Tidbits.Palette.surface)
                .padding(.trailing, Tidbits.Metric.shadowOffset)
            }
        }
        .padding(.top, 8)
    }
}
#endif
