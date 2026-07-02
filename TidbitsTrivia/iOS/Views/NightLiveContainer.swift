#if os(iOS)
import SwiftUI
import SwiftData

/// Runs a NETWORKED Trivia Night on this device (Decision 033) — host or joiner.
/// The `LiveNight` coordinator owns the role + transport and drives the shared
/// `GameEngine`; this view just renders the right stage: a join form (joiner,
/// pre-join), the lobby, the live game (the same `GamePlayView` every mode uses,
/// with `live` wired in), and the final standings.
struct NightLiveContainer: View {
    @State private var live: LiveNight
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var recorded = false
    @State private var code = NightClient.lastCode
    @State private var name = NightClient.lastName

    /// Host a night others can join — opens the room immediately (the lobby shows
    /// the code while joiners arrive).
    init(hosting plan: NightPlan, category: TriviaCategory, engine: GameEngine, hostName: String) {
        _live = State(wrappedValue: LiveNight(hostingPlan: plan, category: category, hostName: hostName, engine: engine))
    }

    /// Join a night someone else is hosting.
    init(joining engine: GameEngine) {
        _live = State(wrappedValue: LiveNight(joiningEngine: engine))
    }

    /// Run a prebuilt night (online Quick Match hands one over with GameKit
    /// transports already wired — Decision 039).
    init(live: LiveNight) {
        _live = State(wrappedValue: live)
    }

    private var game: GameEngine { live.engine }
    private var joinerNeedsToJoin: Bool {
        live.role == .joiner && live.client?.status != .joined
    }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            if joinerNeedsToJoin {
                joinFlow
            } else {
                switch live.stage {
                case .lobby:    lobby
                case .playing:  GamePlayView(game: game, live: live, onQuit: close)
                case .finished: finish
                }
            }
        }
    }

    // MARK: Joiner — find + join a room

    @ViewBuilder private var joinFlow: some View {
        switch live.client?.status ?? .idle {
        case .searching, .connecting: connecting
        default: joinForm
        }
    }

    private var joinForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Join a Night").font(Tidbits.TypeRamp.l1).foregroundStyle(Tidbits.Palette.ink)
                    Spacer()
                    Button("Close") { close() }.tint(Tidbits.Palette.inkSoft)
                }
                Text("Enter the code the host is showing").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
                TextField("CODE", text: $code)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .onChange(of: code) { _, v in code = String(v.uppercased().prefix(4)) }
                    .padding(16).chunkyCard(fill: Tidbits.Palette.surface).padding(.trailing, Tidbits.Metric.shadowOffset)
                TextField("Your name", text: $name)
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    .textInputAutocapitalization(.words)
                    .padding(16).chunkyCard(fill: Tidbits.Palette.surface).padding(.trailing, Tidbits.Metric.shadowOffset)
                if case .failed(let msg) = live.client?.status {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.coral)
                }
                Button("Join") { live.join(code: code, name: name) }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: Tidbits.Palette.coral.legibleForeground))
                    .disabled(code.count < 4)
                Text("On the same Wi-Fi as the host. You'll be asked to allow local-network access.")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .padding(Tidbits.Metric.pad)
        }
    }

    private var connecting: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large).tint(Tidbits.Palette.ink)
            Text(live.client?.status == .searching ? "Finding the room…" : "Connecting…")
                .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
            Button("Cancel") { close() }.tint(Tidbits.Palette.inkSoft)
        }
    }

    // MARK: Lobby

    private var lobby: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 16, weight: .black)) }
                        .tint(Tidbits.Palette.ink)
                    Spacer()
                    Text("TRIVIA NIGHT").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft).kerning(1)
                    Spacer()
                    Color.clear.frame(width: 38, height: 1)
                }
                if live.role == .host && !live.autoPace {
                    VStack(spacing: 6) {
                        Text("SCAN-FREE JOIN CODE").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        Text(live.roomCode).font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundStyle(Tidbits.Palette.ink).kerning(4)
                        Text("Others open Tidbits → Join a Night and enter this code.")
                            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(20)
                    .chunkyCard(fill: Tidbits.Palette.bgDeep).padding(.trailing, Tidbits.Metric.shadowOffset)
                } else if live.autoPace {
                    Text("Match found").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                } else {
                    Text(live.roomName.isEmpty ? "You're in" : "You're in · \(live.roomName)")
                        .font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                }

                rosterList

                if live.role == .host && live.autoPace {
                    HStack(spacing: 10) {
                        ProgressView().tint(Tidbits.Palette.inkSoft)
                        Text("Starting…").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                } else if live.role == .host {
                    Button("Start the Night") { Task { await live.startNight() } }
                        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: Tidbits.Palette.coral.legibleForeground))
                    Text("You'll play too — answer on this device, then reveal for everyone.")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).multilineTextAlignment(.center)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().tint(Tidbits.Palette.inkSoft)
                        Text("Waiting for the host to start…").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                }
            }
            .padding(Tidbits.Metric.pad)
        }
    }

    private var rosterList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(live.playerCount) IN THE ROOM").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(live.players) { p in
                HStack(spacing: 8) {
                    Image(systemName: p.isHost ? "star.fill" : "person.fill")
                        .font(.system(size: 13)).foregroundStyle(p.isHost ? Tidbits.Palette.yellow : Tidbits.Palette.inkSoft)
                    Text(p.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    if p.seat == live.mySeat { Text("YOU").font(.system(size: 10, weight: .black)).foregroundStyle(Tidbits.Palette.coral) }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .chunkyCard(fill: Tidbits.Palette.surface).padding(.trailing, Tidbits.Metric.shadowOffset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Finish

    private var finish: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(finishHeadline).font(Tidbits.TypeRamp.l1).foregroundStyle(Tidbits.Palette.ink)
                    .multilineTextAlignment(.center)
                NightStandingsCard(live: live)
                Text("You answered \(game.summary.correct) of \(game.summary.total) · \(game.summary.score) pts")
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
                Button("Done") { close() }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.ink, textColor: .white))
            }
            .padding(Tidbits.Metric.pad)
        }
        .onAppear(perform: persistIfNeeded)
    }

    private var finishHeadline: String {
        guard let leader = live.players.max(by: { $0.score < $1.score }), leader.score > 0 else { return "That's a night!" }
        return leader.seat == live.mySeat ? "You won! 🎉" : "\(leader.name) takes it!"
    }

    private func persistIfNeeded() {
        guard !recorded else { return }
        recorded = true
        RecordsStore.record(game.summary, in: modelContext)
    }

    private func close() { live.end(); dismiss() }
}
#endif
