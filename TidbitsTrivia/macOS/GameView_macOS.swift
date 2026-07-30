#if os(macOS)
import SwiftUI

/// The Mac game surface (macOS-DESIGN Part B). Observes the shared, UI-agnostic
/// `GameEngine` and renders every question shape with pointer + keyboard
/// (number keys pick MCQ options, ⏎ continues, Esc quits). No new game logic —
/// the engine owns scoring, clocks, and shape routing.
struct GameView_macOS: View {
    @Bindable var game: GameEngine
    let onQuit: () -> Void
    /// Play-vs-CPU: when set, shows the running head-to-head + the bot's result.
    var versus: BotMatch? = nil
    /// Marathon only: how many questions were already answered in EARLIER
    /// sessions — added to `game.index` so the HUD shows the true position
    /// out of 200, not this session's local (resumed-slice) index. nil elsewhere.
    var marathonOffset: Int? = nil

    @FocusState private var typeFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            hud
            if let versus { versusStrip(versus) }
            Divider().overlay(Tidbits.Palette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let q = game.current {
                        if let cat = TriviaCategory.all.first(where: { $0.id == q.categoryID }) {
                            Text(cat.name.uppercased())
                                .font(Tidbits.TypeRamp.l5).foregroundStyle(cat.color.legibleAccent)
                        }
                        Text(q.prompt)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Tidbits.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if game.mode == .weakSpot, let reason = game.weakSpotReasons[q.id] { weakSpotReasonCaption(reason) }
                        if let url = q.imageURL { picture(url) }
                        shapePanel(q)
                        if game.phase == .reveal { revealFooter(q) }
                    }
                }
                .padding(28)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            // Store-screenshot autopilot (docs/STORE-SCREENSHOTS.md §2) — the Mac game view
            // had none, so the reveal + results shots came back as unanswered questions.
            guard DebugHooks.autopilot else { return }
            var stepsLeft = DebugHooks.autopilotSteps
            while game.phase != .finished && game.phase != .idle {
                if let n = stepsLeft, n <= 0 { return }
                try? await Task.sleep(for: .seconds(0.9))
                if stepsLeft != nil { stepsLeft! -= 1 }
                switch game.phase {
                case .playing:
                    if game.current?.closest != nil { game.submitGuess(); break }
                    if game.current?.ordering != nil { game.submitOrder(); break }
                    if game.current?.matching != nil { game.submitMatch(); break }
                    if game.current?.accepted != nil { game.typedText = game.current?.correctAnswer ?? ""; game.submitText(); break }
                    game.submit(DebugHooks.autopilotCorrect ? (game.current?.correctIndex ?? 0) : 0)
                case .reveal: game.advance()
                default: break
                }
            }
        }
        .background(Tidbits.Palette.bg)
        .navigationTitle(game.mode.title)
    }

    // MARK: HUD

    private var hud: some View {
        HStack(spacing: 14) {
            Button(action: onQuit) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Tidbits.Palette.surface))
                    .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)   // Esc quits

            if game.mode == .marathon {
                let offset = marathonOffset ?? 0
                Text("\(offset + game.index + 1) / \(offset + game.questions.count)")
                    .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
            } else if game.mode == .classic || game.mode == .daily {
                Text("\(min(game.index + 1, game.questions.count)) / \(game.questions.count)")
                    .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
            } else {
                Text(game.mode.title).font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
            }

            clockBar

            pill("\(game.score)", fill: Tidbits.Palette.yellow)
            if game.streak >= 2 { pill("🔥 \(game.streak)", fill: Tidbits.Palette.coral, fg: .white) }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var clockBar: some View {
        let budget = max(1, game.displayClockBudget)
        let frac = max(0, min(1, game.remaining / budget))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Tidbits.Palette.bgDeep)
                Capsule().fill(frac < 0.25 ? Tidbits.Palette.coral : Tidbits.Palette.blue)
                    .frame(width: max(2, geo.size.width * frac))
            }
            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
        }
        .frame(height: 14)
    }

    /// Weak-Spot Arena's "why you're seeing this" — transparency by
    /// construction, never an opaque model (docs/CLUB-FEATURES-BUILD.md).
    private func weakSpotReasonCaption(_ reason: String) -> some View {
        Text(reason)
            .font(Tidbits.TypeRamp.l5)
            .foregroundStyle(Tidbits.Palette.grape)
    }

    private func pill(_ text: String, fill: Color, fg: Color = Tidbits.Palette.ink) -> some View {
        Text(text).font(Tidbits.TypeRamp.l6).foregroundStyle(fg)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
    }

    // MARK: Versus (Play-vs-CPU)

    private func versusStrip(_ match: BotMatch) -> some View {
        HStack(spacing: 10) {
            Text("You \(game.score)").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
            Spacer(minLength: 0)
            ForEach(match.seats) { seat in
                HStack(spacing: 5) {
                    Text("\(seat.bot.name) \(seat.score)").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    CPUTag_macOS()
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Tidbits.Palette.surface)
    }

    // MARK: Shape router

    @ViewBuilder
    private func shapePanel(_ q: Question) -> some View {
        if q.closest != nil { closestPanel(q) }
        else if q.ordering != nil { orderingPanel(q) }
        else if q.matching != nil { matchingPanel(q) }
        else if q.accepted != nil { typePanel(q) }
        else if q.enumerate != nil { enumPanel(q) }
        else { mcqPanel(q) }
    }

    // MARK: MCQ (+ Stake chips)

    @ViewBuilder
    private func mcqPanel(_ q: Question) -> some View {
        if game.mode == .stake { stakeChips }
        VStack(spacing: 12) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, opt in
                Button { if game.phase == .playing { game.submit(i) } } label: {
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(Tidbits.Palette.inkSoft).frame(width: 20)
                        Text(opt).font(Tidbits.TypeRamp.l3).foregroundStyle(optionFG(q, i))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(optionBG(q, i)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                }
                .buttonStyle(.plain)
                .disabled(game.phase == .reveal || (game.mode == .stake && game.currentStake == 0))
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
            }
        }
    }

    private func optionBG(_ q: Question, _ i: Int) -> Color {
        guard game.phase == .reveal else { return Tidbits.Palette.surface }
        if i == q.correctIndex { return Tidbits.Palette.mint }
        if i == game.chosenIndex { return Tidbits.Palette.coral }
        return Tidbits.Palette.surface
    }
    private func optionFG(_ q: Question, _ i: Int) -> Color {
        guard game.phase == .reveal else { return Tidbits.Palette.ink }
        if i == q.correctIndex || i == game.chosenIndex { return .white }
        return Tidbits.Palette.ink
    }

    private var stakeChips: some View {
        HStack(spacing: 10) {
            ForEach(game.stakeTiers) { tier in
                Button { game.setStake(tier.value) } label: {
                    VStack(spacing: 2) {
                        Text(tier.label).font(.system(size: 14, weight: .black, design: .rounded))
                        Text("+\(tier.value) · \(tier.remaining) left").font(Tidbits.TypeRamp.l5)
                    }
                    .foregroundStyle(game.currentStake == tier.value ? Tidbits.Palette.ink : Tidbits.Palette.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(game.currentStake == tier.value ? Tidbits.Palette.mint : Tidbits.Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                }
                .buttonStyle(.plain)
                .disabled(game.phase == .reveal || tier.remaining == 0)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: Closest Call

    @ViewBuilder
    private func closestPanel(_ q: Question) -> some View {
        if let spec = q.closest {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(Int(game.currentGuess))\(spec.unit.isEmpty ? "" : " \(spec.unit)")")
                    .font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                Slider(value: Binding(get: { game.currentGuess }, set: { game.setGuess($0) }),
                       in: spec.min...spec.max, step: spec.step)
                    .disabled(game.phase == .reveal)
                Button("Lock it in") { game.submitGuess() }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.yellow, textColor: Tidbits.Palette.ink))
                    .disabled(game.phase == .reveal)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Type the answer

    @ViewBuilder
    private func typePanel(_ q: Question) -> some View {
        HStack(spacing: 10) {
            TextField("Type your answer", text: $game.typedText)
                .textFieldStyle(.plain).font(Tidbits.TypeRamp.l3)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Tidbits.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                .focused($typeFieldFocused)
                .disabled(game.phase == .reveal)
                .onSubmit { game.submitText() }
            Button("Submit") { game.submitText() }
                .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.mint, textColor: Tidbits.Palette.ink, prominent: true))
                .disabled(game.phase == .reveal)
        }
        .onAppear { typeFieldFocused = true }
    }

    // MARK: Enumeration

    @ViewBuilder
    private func enumPanel(_ q: Question) -> some View {
        if let spec = q.enumerate {
            VStack(alignment: .leading, spacing: 12) {
                Text("Named \(game.enumFilled.count) of \(spec.total)")
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                if game.phase == .playing {
                    HStack(spacing: 10) {
                        TextField("Name one…", text: $game.typedText)
                            .textFieldStyle(.plain).font(Tidbits.TypeRamp.l3).padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Tidbits.Palette.surface))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                            .focused($typeFieldFocused)
                            .onSubmit { game.submitEnumGuess(game.typedText) }
                        Button("Done") { game.finishEnum() }
                            .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink, prominent: true))
                    }
                    .onAppear { typeFieldFocused = true }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Array(spec.displayNames.enumerated()), id: \.offset) { i, name in
                        let got = game.enumFilled.contains(i)
                        Text(got || game.phase == .reveal ? name : "•••")
                            .font(Tidbits.TypeRamp.l5).lineLimit(1)
                            .foregroundStyle(got ? Tidbits.Palette.ink : Tidbits.Palette.inkSoft)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(got ? Tidbits.Palette.mint.opacity(0.3) : Tidbits.Palette.surface))
                    }
                }
            }
        }
    }

    // MARK: Ordering

    @ViewBuilder
    private func orderingPanel(_ q: Question) -> some View {
        // Ordering is partial-credit, so the reveal has to say WHICH items were misplaced —
        // otherwise the player gets a score and their own unmarked list and has to diff it
        // against the explanation by eye (iOS parity, QA-SWEEP-LOG Q7).
        let rank: [String: Int] = q.ordering.map {
            Dictionary(uniqueKeysWithValues: $0.enumerated().map { ($0.element, $0.offset) })
        } ?? [:]
        return VStack(spacing: 8) {
            ForEach(Array(game.currentOrder.enumerated()), id: \.offset) { i, item in
                let correctIdx = rank[item]
                let graded = game.phase != .playing && correctIdx != nil
                let right = graded && correctIdx == i
                HStack(spacing: 10) {
                    Text("\(i + 1)").font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Tidbits.Palette.inkSoft).frame(width: 20)
                    Text(item).font(Tidbits.TypeRamp.l3).frame(maxWidth: .infinity, alignment: .leading)
                    if graded {
                        Text(right ? "✓" : "→ \(correctIdx! + 1)")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(right ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                    }
                    if game.phase == .playing {
                        Button { game.moveOrderItem(i, up: true) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.bordered).disabled(i == 0)
                        Button { game.moveOrderItem(i, up: false) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.bordered).disabled(i == game.currentOrder.count - 1)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(
                    graded ? (right ? Tidbits.Palette.mint.opacity(0.22)
                                    : Tidbits.Palette.coral.opacity(0.18))
                           : Tidbits.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidbits.Palette.border, lineWidth: 2))
            }
            if game.phase == .playing {
                Button("Lock in order") { game.submitOrder() }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.blue, textColor: .white))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Matching

    @ViewBuilder
    private func matchingPanel(_ q: Question) -> some View {
        if let m = q.matching {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(m.keys.enumerated()), id: \.offset) { i, key in
                    let graded = game.phase != .playing
                    let truth = i < m.values.count ? m.values[i] : nil
                    let matched = game.matchedValue(forKey: i)
                    let right = graded && matched != nil && matched == truth
                    let row = HStack {
                        Text(key).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Spacer()
                        if graded && !right, let truth {
                            Text(truth).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.coral)
                        } else {
                            Text(matched ?? "—")
                                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        }
                        if graded {
                            Text(right ? "✓" : "✕")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(right ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(
                        graded ? (right ? Tidbits.Palette.mint.opacity(0.22)
                                        : Tidbits.Palette.coral.opacity(0.18))
                               : (game.matchSelectedKey == i ? Tidbits.Palette.yellow.opacity(0.4)
                                                             : Tidbits.Palette.surface)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                    // Plain view once graded: a DISABLED button dims its content, which turned
                    // the graded tint muddy and the key text grey on iOS.
                    if graded {
                        row
                    } else {
                        Button { game.selectMatchKey(i) } label: { row }.buttonStyle(.plain)
                    }
                }
                Text("Pick a row, then its match:").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(Array(game.matchValues.enumerated()), id: \.offset) { vi, val in
                        Button { game.assignMatchValue(vi) } label: {
                            Text(val).font(Tidbits.TypeRamp.l5).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Tidbits.Palette.bgDeep))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                        }
                        .buttonStyle(.plain).disabled(game.phase == .reveal || game.matchSelectedKey == nil)
                    }
                }
                if game.phase == .playing {
                    Button("Lock in matches") { game.submitMatch() }
                        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.blue, textColor: .white))
                }
            }
        }
    }

    // MARK: Picture

    private func picture(_ url: URL) -> some View {
        // v1: AsyncImage. macOS-DESIGN §B6c wants a shared ImagePipeline
        // (decoded NSCache + capped URLSession) — tracked follow-up for
        // picture rounds; fine for a single question at a time.
        AsyncImage(url: url) { img in
            img.resizable().scaledToFit()
        } placeholder: {
            RoundedRectangle(cornerRadius: 14).fill(Tidbits.Palette.bgDeep).frame(height: 220)
                .overlay(ProgressView())
        }
        .frame(maxHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
    }

    // MARK: Reveal

    private func revealFooter(_ q: Question) -> some View {
        let correct = game.lastAnswer?.isCorrect ?? false
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(correct ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                Text(correct ? "Correct" : "Answer: \(q.correctAnswer)")
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
            }
            if !q.explanation.isEmpty {
                Text(q.explanation).font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = q.sourceURL {
                Link("Read \(q.sourceTitle) on Wikipedia ↗", destination: url)
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.blue)
            }
            if let versus {
                ForEach(versus.seats) { seat in
                    HStack(spacing: 8) {
                        Image(systemName: seat.lastCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(seat.lastCorrect == true ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                        Text(versusLine(versus, seat)).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink)
                    }
                }
            }
            Button(game.mode == .survival && !correct ? "See results" : "Continue") { game.advance() }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chunkyCard(fill: Tidbits.Palette.bgDeep)
        .padding(.top, 8)
    }

    private func versusLine(_ match: BotMatch, _ seat: BotMatch.Seat) -> String {
        guard let answer = match.pending.first(where: { $0.botID == seat.bot.id }) else { return seat.bot.name }
        if !answer.answered { return "\(seat.bot.name) ran out of time" }
        let secs = answer.seconds.map { String(format: "%.1fs", $0) } ?? ""
        return seat.lastCorrect == true ? "\(seat.bot.name) got it in \(secs)" : "\(seat.bot.name) missed it"
    }
}

/// The honest label (Decision 038): every bot is visibly CPU, everywhere.
struct CPUTag_macOS: View {
    var body: some View {
        Text("CPU").font(.system(size: 11, weight: .black, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(Tidbits.Palette.ink)
            .background(Capsule().fill(.black.opacity(0.18)))
    }
}
#endif
