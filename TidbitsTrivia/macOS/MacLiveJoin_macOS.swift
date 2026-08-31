#if os(macOS)
import SwiftUI

/// "Join a game" on the Mac — the surface macOS never had.
///
/// PARITY.md has claimed "host from iOS/iPadOS/tvOS/Android AND web; **join from all
/// + the Mac**" since Decision 044. The Mac could not join anything: there was no
/// join view, no code box, and nothing that consumed `TIDBITS_LIVE_JOIN`. The Mac was
/// listed as a player in every cross-platform night run, sat on its Home screen, and
/// was reported as "device blind" — a false cell in the matrix, not a broken feature.
///
/// Deliberately the same Core client every other platform uses (`LivePlayerClient`,
/// the RTDB REST twin) rather than a Mac-specific path: a joiner that reached the room
/// by different code would prove nothing about what the other five platforms do.
///
/// Mac idiom, not the iPhone sheet resized (macOS-DESIGN §0): a real window-width
/// centred measure, keyboard-first (the code field takes focus, Return joins), and
/// Escape leaves. No `.plain` button styles — pointer hit targets stay chunky.
struct MacLiveJoinView_macOS: View {
    var initialCode: String = ""
    var onClose: () -> Void

    @State private var client = LivePlayerClient()
    @State private var code = ""
    @State private var team = ""
    @State private var formError: String?
    @FocusState private var codeFocused: Bool

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            if client.joined { player } else { joinForm }
        }
        .frame(minWidth: 560, minHeight: 460)
        .onAppear {
            if code.isEmpty {
                code = initialCode.isEmpty ? LivePlayerClient.lastCode : initialCode.uppercased()
            }
            if team.isEmpty { team = LivePlayerClient.lastTeam }
            codeFocused = true
        }
        .task {
            // TIDBITS_LIVE_JOIN / TIDBITS_LIVE_NAME — the same driven-join hook every
            // other platform honours. Without it the Mac could be told to join and
            // would land on Home, which is exactly what a matrix run photographed.
            guard let c = DebugHooks.openLiveJoin, !client.joined else { return }
            code = c
            team = DebugHooks.liveJoinName ?? "Mac"
            await resolve()
        }
    }

    // MARK: - Join form

    private var joinForm: some View {
        VStack(spacing: 18) {
            Text("JOIN A GAME")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
            Text("Enter the 4-character code from the host's screen.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)

            TextField("CODE", text: $code)
                .textFieldStyle(.plain)
                .font(.system(size: 40, weight: .black, design: .monospaced))
                .multilineTextAlignment(.center)
                .focused($codeFocused)
                .frame(width: 260)
                .padding(.vertical, 10)
                .chunkyCard(fill: Tidbits.Palette.surface)
                .onChange(of: code) { _, new in
                    // The host shows an uppercase code; typing lowercase should still
                    // join rather than silently miss.
                    let clean = new.uppercased().filter { $0.isLetter || $0.isNumber }
                    if clean != new { code = String(clean.prefix(4)) }
                }

            TextField("Your team name", text: $team)
                .textFieldStyle(.plain)
                .font(Tidbits.TypeRamp.l3)
                .multilineTextAlignment(.center)
                .frame(width: 260)
                .padding(.vertical, 8)
                .chunkyCard(fill: Tidbits.Palette.surface)

            if let formError {
                Text(formError).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.coral)
            }

            HStack(spacing: 12) {
                Button("Cancel", action: onClose)
                Button(client.joining ? "Joining…" : "Join") { Task { await resolve() } }
                    .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.coral,
                                                    textColor: .white, prominent: true))
                    .keyboardShortcut(.defaultAction)     // Return joins
                    .disabled(client.joining)
            }
        }
        .padding(36)
    }

    /// Confirm the room exists, then join. A miss is a clear not-found — the same
    /// contract as every other platform's join, so a wrong code never looks like a
    /// network failure.
    private func resolve() async {
        let c = code.uppercased().filter { $0.isLetter || $0.isNumber }
        let t = team.trimmingCharacters(in: .whitespaces)
        guard c.count >= 4 else { formError = "Enter the 4-character code from the screen."; return }
        guard !t.isEmpty else { formError = "Enter a team name."; return }
        formError = nil
        await client.join(code: c, team: t)
        if !client.joined { formError = client.errorText ?? "No game found with that code." }
    }

    // MARK: - Playing

    private var player: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(team).font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                    Text("CODE \(client.code)")
                        .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(client.score)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Tidbits.Palette.ink).monospacedDigit()
                    Text("points").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                Button("Leave") { Task { await client.leave(); onClose() } }
                    .padding(.leading, 10)
            }
            .padding(20)

            Spacer(minLength: 0)
            if let pub = client.pub {
                question(pub)
            } else {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    Text("Waiting for the host to start…")
                        .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .onExitCommand { Task { await client.leave(); onClose() } }
    }

    @ViewBuilder
    private func question(_ pub: LiveRoom.Pub) -> some View {
        VStack(spacing: 16) {
            // Same eyebrow the other joiners show, built from the wire fields rather
            // than a convenience the Pub does not have.
            Text("ROUND \(pub.round) · \(pub.roundTitle.uppercased()) — Q\(pub.qNum)/\(pub.qTotal)")
                .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
            Text(pub.prompt)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)

            // Two columns: a Mac window is wide, and a single stacked column of four
            // options wastes the measure the platform actually has.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array((pub.options ?? []).enumerated()), id: \.offset) { i, opt in
                    Button { Task { await client.submit(choice: i) } } label: {
                        Text(opt).font(Tidbits.TypeRamp.l3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12).padding(.horizontal, 14)
                    }
                    .buttonStyle(ChunkyButtonStyle(
                        fill: client.chosen == i ? Tidbits.Palette.coral : Tidbits.Palette.surface,
                        textColor: client.chosen == i ? .white : Tidbits.Palette.ink))
                    .disabled(client.hasAnswered)
                }
            }
            .frame(maxWidth: 640)

            Text(client.hasAnswered ? "Answer locked in." : "Click your answer.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .padding(24)
    }
}
#endif
