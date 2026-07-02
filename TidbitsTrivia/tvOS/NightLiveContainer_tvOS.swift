#if os(tvOS)
import SwiftUI
import SwiftData

/// Runs a NETWORKED Trivia Night on Apple TV (Decision 033) — the TV is a peer
/// like any other Apple device: it can HOST (show a big join code on the living-
/// room screen, play along, and pace the night) or JOIN one a phone/iPad hosts.
/// Reuses the shared `GameEngine` + ten-foot `TVGamePlayView`, with `live` wired in.
struct TVNightLiveContainer: View {
    @State private var live: LiveNight
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var recorded = false
    @State private var code = NightClient.lastCode
    @State private var name = NightClient.lastName
    @FocusState private var focus: Field?
    private enum Field: Hashable { case code, name, join, start }

    init(hosting plan: NightPlan, category: TriviaCategory, engine: GameEngine, hostName: String) {
        _live = State(wrappedValue: LiveNight(hostingPlan: plan, category: category, hostName: hostName, engine: engine))
    }
    /// Run a prebuilt night (online Quick Match hands one over with GameKit
    /// transports already wired — Decision 039).
    init(live: LiveNight) {
        _live = State(wrappedValue: live)
    }

    init(joining engine: GameEngine) {
        _live = State(wrappedValue: LiveNight(joiningEngine: engine))
    }

    private var game: GameEngine { live.engine }
    private var joinerNeedsToJoin: Bool { live.role == .joiner && live.client?.status != .joined }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            if joinerNeedsToJoin {
                joinForm
            } else {
                switch live.stage {
                case .lobby:    lobby
                case .playing:  TVGamePlayView(onQuit: close, live: live)
                case .finished: finish
                }
            }
        }
        .onExitCommand(perform: close)
    }

    // MARK: Joiner — enter the code

    private var joinForm: some View {
        VStack(alignment: .leading, spacing: 36) {
            Text("JOIN A NIGHT").font(.system(size: 64, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("Enter the code the host is showing.").font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            TextField("CODE", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .onChange(of: code) { _, v in code = String(v.uppercased().prefix(4)) }
                .font(.system(size: 44, weight: .black, design: .rounded))
                .frame(maxWidth: 600).focused($focus, equals: .code)
            TextField("Your name", text: $name)
                .font(.system(size: 33, weight: .bold, design: .rounded))
                .frame(maxWidth: 600).focused($focus, equals: .name)
            if case .failed(let msg) = live.client?.status {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
            } else if live.client?.status == .searching || live.client?.status == .connecting {
                Label("Finding the room…", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
            Button("Join") { live.join(code: code, name: name) }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                .focused($focus, equals: .join).disabled(code.count < 4)
            Text("On the same Wi-Fi as the host. You'll be asked to allow local-network access.")
                .font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
        .padding(90)
        .defaultFocus($focus, .code)
    }

    // MARK: Lobby

    private var lobby: some View {
        ScrollView {
            VStack(spacing: 44) {
                Text("TRIVIA NIGHT").font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(.white)
                if live.role == .host {
                    VStack(spacing: 12) {
                        Text("JOIN CODE").font(.system(size: 31, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        Text(live.roomCode).font(.system(size: 140, weight: .black, design: .rounded)).foregroundStyle(.white).kerning(8)
                        Text("On each phone or iPad: open Tidbits → Join a Night → enter this code.")
                            .font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text(live.roomName.isEmpty ? "You're in" : "You're in · \(live.roomName)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                }
                roster
                if live.role == .host {
                    Button("Start the Night") { Task { await live.startNight() } }
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                        .focused($focus, equals: .start)
                    Text("You'll play too — answer with the remote, then reveal for everyone.")
                        .font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                } else {
                    Label("Waiting for the host to start…", systemImage: "hourglass")
                        .font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                }
            }
            .padding(90).frame(maxWidth: .infinity)
        }
        .defaultFocus($focus, .start)
    }

    private var roster: some View {
        VStack(spacing: 12) {
            Text("\(live.playerCount) IN THE ROOM").font(.system(size: 25, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            ForEach(live.players) { p in
                HStack(spacing: 16) {
                    Image(systemName: p.isHost ? "star.fill" : "person.fill")
                        .foregroundStyle(p.isHost ? Tidbits.Palette.yellow : TVTheme.textSoft)
                    Text(p.name).font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    if p.seat == live.mySeat { Text("YOU").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.coral) }
                    Spacer()
                }
                .padding(.horizontal, 28).padding(.vertical, 14).frame(maxWidth: 900)
                .background(RoundedRectangle(cornerRadius: 16).fill(TVTheme.panel))
            }
        }
    }

    // MARK: Finish

    private var finish: some View {
        ScrollView {
            VStack(spacing: 30) {
                Text(finishHeadline).font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(.white)
                TVNightStandings(live: live)
                Text("You answered \(game.summary.correct) of \(game.summary.total) · \(game.summary.score) pts")
                    .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                Button("Done", action: close)
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
            }
            .padding(90).frame(maxWidth: .infinity)
        }
        .onAppear(perform: persistIfNeeded)
    }

    private var finishHeadline: String {
        guard let leader = live.players.max(by: { $0.score < $1.score }), leader.score > 0 else { return "That's a night!" }
        return leader.seat == live.mySeat ? "You won!" : "\(leader.name) takes it!"
    }

    private func persistIfNeeded() {
        guard !recorded else { return }
        recorded = true
        RecordsStore.record(game.summary, in: modelContext)
    }

    private func close() { live.end(); dismiss() }
}
#endif
