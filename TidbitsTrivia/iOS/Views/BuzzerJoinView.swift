#if os(iOS)
import SwiftUI

/// The phone side of Buzz Night — join the Apple TV's room with the code on
/// screen, then a single giant BUZZ button (Phase-1 Bonjour client, Decision
/// 030). The phone only buzzes; the TV is the stage, scoreboard, and the
/// authoritative "who was first" arbiter. The buzzer is a private input channel
/// — its whole job is to be fast and unambiguous, so it's one huge target.
struct BuzzerJoinView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var client = BuzzerClient()
    @State private var code = ""
    @State private var name = ""

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
            .navigationTitle("Buzz Night")
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
                        Text(statusLine).font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.inkSoft)
                            .multilineTextAlignment(.center).padding(.top, 4)
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

    private var statusLine: String {
        if client.resultCorrect == true { return "Correct! 🎉" }
        if client.resultCorrect == false {
            return client.winnerSeat == client.seat ? "Not quite — buzzers re-open to others." : "That wasn't it."
        }
        if client.isAnswering { return "You got the buzz! Tap your answer above." }
        if client.myAnswer != nil { return "Answer sent — waiting on the host…" }
        if let w = client.winnerSeat, w != client.seat {
            return "\(client.players.first { $0.seat == w }?.name ?? "Another player") buzzed first…"
        }
        if client.canBuzz { return "Buzzers are open — tap BUZZ the moment you know it." }
        return "Get ready…"
    }
}
#endif
