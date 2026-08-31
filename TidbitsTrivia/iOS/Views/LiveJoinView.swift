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
    /// Regular width = iPad (and a wide iPhone in landscape). The live player was
    /// a phone layout stretched across 12.9 inches: full-bleed question text at a
    /// ludicrous measure, four options in one tall column, and everything jammed
    /// against the top with the bottom half of the display empty.
    @Environment(\.horizontalSizeClass) private var hSize
    private var isWide: Bool { hSize == .regular }
    @Environment(\.scenePhase) private var scenePhase
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
        .onAppear {
            if code.isEmpty { code = initialCode.isEmpty ? LivePlayerClient.lastCode : initialCode.uppercased() }
            if team.isEmpty { team = LivePlayerClient.lastTeam }
        }
        .interactiveDismissDisabled(client.joined)
        .onChange(of: scenePhase) { _, phase in   // Wave C: flag leaving the app mid-question (soft cheat signal)
            if phase != .active, client.pub?.phase == LiveRoom.Phase.question, !client.hasAnswered { client.blurred = true }
        }
        .task {
            // CI/device hook: auto-resolve a known room to verify the flow headless.
            if ProcessInfo.processInfo.environment["TIDBITS_LIVE_AUTOJOIN"] == "1",
               !initialCode.isEmpty, !client.joined {
                // TIDBITS_LIVE_NAME first: a hard-coded "iOS Tester" meant the iPhone
                // and the iPad joined a room under the SAME name — two rows the host
                // cannot tell apart, and a join count that read "3 of 4 landed" when
                // all four had. Android's twin (tidbits_live_name) already took a name.
                code = initialCode
                team = DebugHooks.liveJoinName ?? "iOS Tester"
                await resolve()
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
                .padding(isWide ? 32 : 20)
                // A capped measure, centred. Reading a clue set across the full
                // width of a 12.9" display is the classic stretched-phone tell.
                .frame(maxWidth: isWide ? 900 : .infinity)
                .frame(maxWidth: .infinity)
                // Centre the column in the window instead of pinning it to the
                // top over an empty lower half.
                .centeredInScroll(isWide)
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
            if !client.coplayers.isEmpty { coplayersView }
            Button("Done") { Task { await client.leave(); dismiss() } }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white)).padding(.top, 8)
        }
        .padding(.top, 40)
    }

    /// L5 social graph: "Add the people you played with" — the captured co-players → the private friend graph.
    private var coplayersView: some View {
        let store = PlayerIdentityStore.shared
        return VStack(spacing: 6) {
            Text("Add the people you played with").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(client.coplayers) { c in
                HStack {
                    Text(c.name).fontWeight(.semibold).foregroundStyle(Tidbits.Palette.ink)
                    Spacer()
                    if store.isFriend(c.uid) {
                        Text("Added").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                    } else {
                        Button("Add") { Task { await store.addFriend(uid: c.uid, name: c.name) } }
                            .buttonStyle(.borderless).foregroundStyle(Tidbits.Palette.blue)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Tidbits.Palette.surface))
            }
        }
        .frame(maxWidth: 320).padding(.top, 6)
    }

    @ViewBuilder private func questionView(_ p: LiveRoom.Pub) -> some View {
        let revealed = p.phase == LiveRoom.Phase.reveal
        VStack(alignment: .leading, spacing: 14) {
            Text("ROUND \(p.round) · \(p.roundTitle.uppercased()) — Q\(p.qNum)/\(p.qTotal)")
                .font(isWide ? .system(size: 16, weight: .heavy, design: .rounded)
                             : Tidbits.TypeRamp.l6)
                .foregroundStyle(Tidbits.Palette.inkSoft)
            if let img = p.imageURL, let url = URL(string: img) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() }
                    else if phase.error != nil { EmptyView() }
                    else { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
                }
                .frame(maxWidth: .infinity, maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            // 24pt is a phone size read at arm's length; a 12.9" iPad is held
            // further away and usually shared, so the clue carries at 34.
            Text(p.prompt)
                .font(.system(size: isWide ? 34 : 24, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let d = p.deadline, !revealed { countdownView(d) }   // Wave A: on-screen timer
            if p.wager == true, !revealed { wagerStepper() }        // Wave A: wager round
            answerSurface(p, revealed: revealed)
            statusNote(p, revealed: revealed)
            if revealed, let story = p.story, !story.isEmpty {   // Wave A: the story behind the answer
                Text(story)
                    .font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Tidbits.Palette.surface))
            }
        }
    }

    /// Wave A: the stake input on a wager question — bet 0…your score.
    @ViewBuilder private func wagerStepper() -> some View {
        let maxBet = max(0, client.score)
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR WAGER").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.coral)
            Stepper(value: Binding(get: { min(client.wager, maxBet) }, set: { client.wager = $0 }),
                    in: 0...maxBet, step: max(1, maxBet / 10)) {
                Text("\(min(client.wager, maxBet)) of \(maxBet) pts")
                    .font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            }
            .disabled(maxBet == 0)
            if maxBet == 0 { Text("No points to wager yet.").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Tidbits.Palette.coral.opacity(0.12)))
    }

    /// Wave A: the shared countdown, ticking to the host's deadline (coral at ≤5s).
    @ViewBuilder private func countdownView(_ deadlineMs: Int) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let remaining = max(0, deadlineMs - Int(Date().timeIntervalSince1970 * 1000))
            let secs = Int((Double(remaining) / 1000).rounded(.up))
            Text(secs >= 60 ? String(format: "%d:%02d", secs / 60, secs % 60) : "\(secs)s")
                .font(.system(size: 32, weight: .black, design: .rounded)).monospacedDigit()
                .foregroundStyle(secs <= 5 ? Tidbits.Palette.coral : Tidbits.Palette.inkSoft)
        }
    }

    /// The right input for the question's type. The host auto-scores each on reveal.
    @ViewBuilder private func answerSurface(_ p: LiveRoom.Pub, revealed: Bool) -> some View {
        let locked = revealed || client.hasAnswered || p.locked == true
        if let n = p.numeric {
            LiveNumericAnswer(spec: n, locked: locked) { v in Task { await client.submit(number: v) } }.id(p.qid)
        } else if let items = p.orderItems, !items.isEmpty {
            LiveOrderingAnswer(items: items, locked: locked) { o in Task { await client.submit(order: o) } }.id(p.qid)
        } else if let keys = p.matchKeys, let values = p.matchValues, !keys.isEmpty {
            LiveMatchingAnswer(keys: keys, values: values, locked: locked) { pr in Task { await client.submit(pairs: pr) } }.id(p.qid)
        } else if p.enumTarget != nil {
            LiveEnumerateAnswer(target: p.enumTarget ?? 0, locked: locked) { l in Task { await client.submit(list: l) } }.id(p.qid)
        } else if let options = p.options, !options.isEmpty {
            // Two columns on iPad. Four full-width rows down a 12.9" screen is a
            // lot of travel for a tap and reads as a phone list that grew; a 2x2
            // grid is the shape a quiz answer set actually wants at this size.
            if isWide {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                    GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                        optionButton(i, opt, p: p, revealed: revealed)
                    }
                }
            } else {
                ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                    optionButton(i, opt, p: p, revealed: revealed)
                }
            }
        } else {
            LiveTextAnswer(locked: locked) { t in Task { await client.submit(text: t) } }.id(p.qid)
        }
    }

    private func optionButton(_ i: Int, _ opt: String, p: LiveRoom.Pub, revealed: Bool) -> some View {
        let chosen = client.chosen == i
        let correct = revealed && p.answerIndex == i
        let wrong = revealed && chosen && p.answerIndex != i
        let fill: Color = correct ? Tidbits.Palette.mint : wrong ? Color(red: 0.95, green: 0.82, blue: 0.80) : chosen ? Tidbits.Palette.blue.opacity(0.18) : .white
        return Button { Task { await client.submit(choice: i) } } label: {
            HStack(spacing: 12) {
                Text("\(i + 1)").font(.system(size: isWide ? 19 : 15, weight: .black)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8).fill(Tidbits.Palette.ink))
                Text(opt)
                    .font(isWide ? .system(size: 24, weight: .semibold, design: .rounded)
                                 : Tidbits.TypeRamp.l3)
                    .foregroundStyle(correct ? .white : Tidbits.Palette.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).chunkyCard(fill: fill)
        }
        .buttonStyle(.plain)
        .disabled(revealed || client.hasAnswered || p.locked == true)
    }

    @ViewBuilder private func statusNote(_ p: LiveRoom.Pub, revealed: Bool) -> some View {
        let note: (String, Color) = revealed
            ? (client.chosen == p.answerIndex ? ("Correct!", Tidbits.Palette.mint) : client.chosen == nil ? ("No answer submitted.", Tidbits.Palette.inkSoft) : ("Not this time.", .red))
            : (client.hasAnswered ? ("Locked in — waiting for the reveal…", Tidbits.Palette.mint)
               : p.locked == true ? ("Answers locked — pencils down!", Tidbits.Palette.coral) : ("Tap your answer.", Tidbits.Palette.inkSoft))
        Text(note.0).font(Tidbits.TypeRamp.l4).foregroundStyle(note.1).frame(maxWidth: .infinity).padding(.top, 6)
    }
}

// MARK: - Per-type answer surfaces (host auto-scores each on reveal)

private struct LiveNumericAnswer: View {
    let spec: LiveRoom.Numeric
    let locked: Bool
    var onSubmit: (Double) -> Void
    @State private var value: Double
    @State private var sent = false
    init(spec: LiveRoom.Numeric, locked: Bool, onSubmit: @escaping (Double) -> Void) {
        self.spec = spec; self.locked = locked; self.onSubmit = onSubmit
        _value = State(initialValue: ((spec.min + spec.max) / 2).rounded())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(value == value.rounded() ? "\(Int(value))\(unit)" : String(format: "%.1f%@", value, unit))
                .font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Slider(value: $value, in: spec.min...spec.max, step: spec.step > 0 ? spec.step : 1)
                .tint(Tidbits.Palette.blue).disabled(locked || sent)
            if !sent { submitButton(disabled: locked) { sent = true; onSubmit(value) } }
        }
    }
    private var unit: String { spec.unit.isEmpty ? "" : " \(spec.unit)" }
}

private struct LiveTextAnswer: View {
    let locked: Bool
    var onSubmit: (String) -> Void
    @State private var text = ""
    @State private var sent = false
    var body: some View {
        VStack(spacing: 10) {
            TextField("Type your answer", text: $text).textFieldStyle(.roundedBorder).autocorrectionDisabled().disabled(locked || sent)
            if !sent {
                submitButton(disabled: locked || text.trimmingCharacters(in: .whitespaces).isEmpty) {
                    sent = true; onSubmit(text.trimmingCharacters(in: .whitespaces))
                }
            }
        }
    }
}

private struct LiveEnumerateAnswer: View {
    let target: Int
    let locked: Bool
    var onSubmit: ([String]) -> Void
    @State private var entry = ""
    @State private var items: [String] = []
    @State private var sent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Name as many as you can \(target > 0 ? "(\(items.count)/\(target))" : "(\(items.count))")")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            if !items.isEmpty {
                Text(items.joined(separator: " · ")).font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            if !sent {
                HStack {
                    TextField("Add one…", text: $entry).textFieldStyle(.roundedBorder).autocorrectionDisabled().disabled(locked)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(locked || entry.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                submitButton(title: "Done", disabled: locked || items.isEmpty) { sent = true; onSubmit(items) }
            }
        }
    }
    private func add() {
        let t = entry.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !items.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        items.append(t); entry = ""
    }
}

private struct LiveOrderingAnswer: View {
    let items: [String]
    let locked: Bool
    var onSubmit: ([Int]) -> Void
    @State private var order: [Int]
    @State private var sent = false
    init(items: [String], locked: Bool, onSubmit: @escaping ([Int]) -> Void) {
        self.items = items; self.locked = locked; self.onSubmit = onSubmit
        _order = State(initialValue: Array(items.indices))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Put them in order (top = first).").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(Array(order.enumerated()), id: \.element) { pos, idx in
                HStack(spacing: 10) {
                    Text("\(pos + 1).").font(.system(size: 15, weight: .black)).foregroundStyle(Tidbits.Palette.inkSoft)
                    Text(items[idx]).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Spacer(minLength: 0)
                    if !locked && !sent {
                        Button { move(pos, -1) } label: { Image(systemName: "chevron.up") }.disabled(pos == 0).buttonStyle(.plain)
                        Button { move(pos, 1) } label: { Image(systemName: "chevron.down") }.disabled(pos == order.count - 1).buttonStyle(.plain)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).chunkyCard(fill: .white)
            }
            if !sent { submitButton(disabled: locked) { sent = true; onSubmit(order) } }
        }
    }
    private func move(_ pos: Int, _ d: Int) { let n = pos + d; guard order.indices.contains(n) else { return }; order.swapAt(pos, n) }
}

private struct LiveMatchingAnswer: View {
    let keys: [String]
    let values: [String]
    let locked: Bool
    var onSubmit: ([Int]) -> Void
    @State private var pairs: [Int]
    @State private var sent = false
    init(keys: [String], values: [String], locked: Bool, onSubmit: @escaping ([Int]) -> Void) {
        self.keys = keys; self.values = values; self.locked = locked; self.onSubmit = onSubmit
        _pairs = State(initialValue: Array(repeating: -1, count: keys.count))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Match each to its pair.").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                HStack {
                    Text(key).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Spacer(minLength: 8)
                    Menu {
                        ForEach(Array(values.enumerated()), id: \.offset) { vi, v in Button(v) { pairs[i] = vi } }
                    } label: {
                        Text(pairs[i] >= 0 ? values[pairs[i]] : "Choose…")
                            .font(Tidbits.TypeRamp.l4).foregroundStyle(pairs[i] >= 0 ? Tidbits.Palette.blue : Tidbits.Palette.inkSoft)
                    }.disabled(locked || sent)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).chunkyCard(fill: .white)
            }
            if !sent { submitButton(disabled: locked || pairs.contains(-1)) { sent = true; onSubmit(pairs) } }
        }
    }
}

/// Shared submit button for the answer surfaces.
@ViewBuilder private func submitButton(title: String = "Submit", disabled: Bool, _ action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
        .disabled(disabled).frame(maxWidth: .infinity)
}

private extension View {
    /// Make the content at least as tall as the scroll container and centre it, so a
    /// short round sits in the middle of an iPad rather than clinging to the top edge
    /// with the lower half empty. A no-op on compact width, where the content already
    /// fills the screen.
    ///
    /// INSIDE the `#if os(iOS)`: `import SwiftUI` is itself inside that guard, so this
    /// sitting after the `#endif` compiled fine for iOS and broke every other Apple
    /// platform with "cannot find type 'View' in scope" — a file whose whole body is
    /// iOS-only has no imports at all once the guard is off.
    @ViewBuilder func centeredInScroll(_ active: Bool) -> some View {
        if active {
            self.containerRelativeFrame(.vertical, alignment: .center)
        } else {
            self
        }
    }
}
#endif
