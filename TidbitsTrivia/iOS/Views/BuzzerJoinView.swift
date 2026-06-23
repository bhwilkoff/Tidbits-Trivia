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

    // MARK: Buzzer

    private var buzzer: some View {
        VStack(spacing: 18) {
            HStack {
                Text(client.roomName ?? "Connected").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                if let seat = client.seat {
                    Text("You're in · seat \(seat)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                }
            }
            .padding(.horizontal, Tidbits.Metric.pad)

            Spacer()
            buzzButton
            Text(statusLine).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.bottom, 24)
    }

    private var buzzButton: some View {
        Button { client.buzz() } label: {
            Text(client.canBuzz ? "BUZZ" : "WAIT")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 280, height: 280)
                .background(Circle().fill(buzzColor))
                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 5))
                .scaleEffect(client.canBuzz ? 1 : 0.92)
                .animation(.spring(duration: 0.25), value: client.canBuzz)
        }
        .buttonStyle(.plain)
        .disabled(!client.canBuzz)
        .sensoryFeedback(.impact(weight: .heavy), trigger: client.canBuzz)
    }

    private var buzzColor: Color {
        if client.iWon { return Tidbits.Palette.mint }
        if client.winnerSeat != nil { return Tidbits.Palette.inkSoft }
        return client.canBuzz ? Tidbits.Palette.coral : Tidbits.Palette.inkSoft
    }

    private var statusLine: String {
        if client.iWon { return "You got the buzz! Call out your answer." }
        if let w = client.winnerSeat, w != client.seat {
            return "\(client.players.first { $0.seat == w }?.name ?? "Another player") buzzed first."
        }
        if client.canBuzz { return "Buzzers are open — tap the moment you know it." }
        return "Wait for the next question…"
    }
}
#endif
