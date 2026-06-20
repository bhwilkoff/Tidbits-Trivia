#if os(iOS)
import SwiftUI

/// The live question screen. Observes the shared GameEngine and renders
/// the current question, answer choices, and — after answering — the
/// "learn the fact" reveal that turns every miss (and hit) into a
/// curiosity door (the learning-orientation mandate).
struct GamePlayView: View {
    let game: GameEngine
    let onQuit: () -> Void
    @FocusState private var enumFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            hud
            if let q = game.current {
                ScrollView {
                    VStack(spacing: 18) {
                        if let img = q.imageURL { pictureHeader(img) }
                        QuestionCard(question: q)
                        if game.mode == .sweep { sweepGrid }
                        if game.mode == .stake && game.phase == .playing { stakeSelector }
                        if let spec = q.enumerate { enumeratePanel(spec) }
                        else if q.accepted != nil { typeAnswerPanel() }
                        else if let m = q.matching { matchingPanel(m) }
                        else if q.ordering != nil { orderingPanel() }
                        else if let spec = q.closest { closestPanel(spec) }
                        else { answers(for: q) }
                        if game.phase == .reveal { reveal(for: q) }
                    }
                    .padding(.horizontal, Tidbits.Metric.pad)
                    .padding(.bottom, 24)
                    // Stable per-question identity so the prompt AND the four
                    // option buttons swap as ONE atomic subtree on advance —
                    // not an in-place diff that mutates the reused buttons a
                    // frame before/after the prompt (the "text loads after the
                    // buttons / options don't match the last question" jank).
                    .id(game.index)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            Spacer(minLength: 0)
            if game.phase == .reveal { nextBar }
        }
        .background(Tidbits.Palette.bg.ignoresSafeArea())
        .task {
            // Screenshot/CI autopilot — no-op unless TIDBITS_AUTOPILOT=1.
            guard DebugHooks.autopilot else { return }
            while game.phase != .finished && game.phase != .idle {
                try? await Task.sleep(for: .seconds(0.9))
                switch game.phase {
                case .playing:
                    if game.mode == .closestCall { game.submitGuess(); break }
                    if game.mode == .ordering { game.submitOrder(); break }
                    if game.mode == .matching { game.submitMatch(); break }
                    if game.mode == .typeAnswer { game.typedText = game.current?.correctAnswer ?? ""; game.submitText(); break }
                    if game.mode == .enumerate {
                        let names = game.current?.enumerate?.displayNames ?? []
                        if game.enumNamed.count < 3, names.indices.contains(game.enumNamed.count) {
                            game.submitEnumGuess(names[game.enumNamed.count])
                        } else { game.finishEnum() }
                        break
                    }
                    if game.mode == .stake && game.currentStake == 0,
                       let tier = game.stakeTiers.first(where: { $0.remaining > 0 }) { game.setStake(tier.value) }
                    game.submit(0)
                case .reveal:  game.advance()
                default:       break
                }
            }
        }
    }

    // MARK: HUD

    private var hud: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onQuit) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Tidbits.Palette.ink)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Tidbits.Palette.surface))
                        .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                }
                Spacer()
                StreakPill(streak: game.streak)
                Spacer()
                ScorePill(score: game.score)
            }
            ClockBar(remaining: game.remaining,
                     budget: game.mode.perQuestionSeconds ?? game.mode.globalClockSeconds ?? 30,
                     tint: game.mode.accent,
                     label: progressLabel)
        }
        .padding(.horizontal, Tidbits.Metric.pad)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var progressLabel: String {
        switch game.mode {
        case .timeAttack, .survival: return "#\(game.index + 1)"
        default: return "\(game.index + 1) / \(game.questions.count)"
        }
    }

    // MARK: Answers

    private func answers(for q: Question) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { idx, option in
                AnswerButton(
                    text: option,
                    state: answerState(idx: idx, q: q),
                    action: { game.submit(idx) }
                )
                // Stake mode: you must commit a confidence chip before answering.
                .disabled(game.phase != .playing || (game.mode == .stake && game.currentStake == 0))
            }
        }
    }

    // MARK: Stake selector

    private var stakeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(game.currentStake == 0 ? "How sure are you?" : "Staked: \(game.stakeLabel)")
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
            HStack(spacing: 10) {
                ForEach(game.stakeTiers) { tier in
                    StakeChip(tier: tier,
                              selected: game.currentStake == tier.value,
                              action: { game.setStake(tier.value) })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .chunkyCard(fill: Tidbits.Palette.bgDeep)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    // MARK: Type-the-answer

    private func typeAnswerPanel() -> some View {
        let live = game.phase == .playing
        return VStack(spacing: 12) {
            TextField("Type your answer…", text: Binding(get: { game.typedText }, set: { game.typedText = $0 }))
                .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                .autocorrectionDisabled().textInputAutocapitalization(.words)
                .submitLabel(.done).onSubmit { game.submitText() }
                .padding(14)
                .chunkyCard(fill: Tidbits.Palette.surface)
                .padding(.trailing, Tidbits.Metric.shadowOffset)
                .disabled(!live)
            if live {
                Button("Submit") { game.submitText() }
                    .buttonStyle(ChunkyButtonStyle(fill: game.mode.accent, textColor: game.mode.accent.legibleForeground))
                    .disabled(game.typedText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: Enumeration (Q8) — name as many as you can

    private func enumeratePanel(_ spec: EnumSpec) -> some View {
        let live = game.phase == .playing
        let cols = [GridItem(.adaptive(minimum: 110), spacing: 8)]
        return VStack(spacing: 12) {
            HStack {
                Text("\(game.enumFilled.count) / \(spec.total)")
                    .font(Tidbits.TypeRamp.l2.monospacedDigit())
                    .foregroundStyle(game.mode.accent)
                Spacer()
                if live {
                    Button("Done") { enumFocused = false; game.finishEnum() }
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.inkSoft)
                }
            }
            if live {
                TextField("Name one…", text: Binding(get: { game.typedText }, set: { game.typedText = $0 }))
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    .autocorrectionDisabled().textInputAutocapitalization(.words)
                    .submitLabel(.next).focused($enumFocused)
                    .onSubmit { game.submitEnumGuess(game.typedText); enumFocused = true }
                    .padding(14)
                    .chunkyCard(fill: game.enumLastHit ? game.mode.accent.opacity(0.2) : Tidbits.Palette.surface)
                    .padding(.trailing, Tidbits.Metric.shadowOffset)
                    .onAppear { enumFocused = true }
            }
            if !game.enumNamed.isEmpty {
                LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                    ForEach(game.enumNamed, id: \.self) { name in
                        Text(name)
                            .font(Tidbits.TypeRamp.l5).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8).padding(.horizontal, 6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(game.mode.accent.opacity(0.18)))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(game.mode.accent, lineWidth: 2))
                            .foregroundStyle(Tidbits.Palette.ink)
                    }
                }
            }
        }
    }

    // MARK: Matching

    private func matchingPanel(_ m: MatchSpec) -> some View {
        let live = game.phase == .playing
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return VStack(spacing: 12) {
            VStack(spacing: 8) {
                ForEach(Array(m.keys.enumerated()), id: \.offset) { i, key in
                    let matched = game.matchedValue(forKey: i)
                    Button { game.selectMatchKey(i) } label: {
                        HStack {
                            Text(key).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(matched ?? "tap a value →").font(Tidbits.TypeRamp.l5)
                                .foregroundStyle(matched != nil ? Tidbits.Palette.ink : Tidbits.Palette.inkSoft)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .chunkyCard(fill: game.matchSelectedKey == i ? game.mode.accent.opacity(0.22) : Tidbits.Palette.surface)
                        .padding(.trailing, Tidbits.Metric.shadowOffset)
                    }
                    .buttonStyle(.plain).disabled(!live)
                }
            }
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(Array(game.matchValues.enumerated()), id: \.offset) { j, val in
                    let used = game.matchAssign.contains(j)
                    Button { game.assignMatchValue(j) } label: {
                        Text(val).font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(Tidbits.Palette.ink)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Tidbits.Palette.bgDeep))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                            .opacity(used ? 0.35 : 1)
                    }
                    .buttonStyle(.plain).disabled(!live || used)
                }
            }
            if live {
                Button("Submit") { game.submitMatch() }
                    .buttonStyle(ChunkyButtonStyle(fill: game.mode.accent, textColor: game.mode.accent.legibleForeground))
            }
        }
    }

    // MARK: Ordering

    private func orderingPanel() -> some View {
        let live = game.phase == .playing
        return VStack(spacing: 10) {
            ForEach(Array(game.currentOrder.enumerated()), id: \.element) { idx, item in
                HStack(spacing: 10) {
                    Text("\(idx + 1)").font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(Tidbits.Palette.inkSoft).frame(width: 22)
                    Text(item).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if live {
                        Button { game.moveOrderItem(idx, up: true) } label: { Image(systemName: "chevron.up") }
                            .disabled(idx == 0)
                        Button { game.moveOrderItem(idx, up: false) } label: { Image(systemName: "chevron.down") }
                            .disabled(idx == game.currentOrder.count - 1)
                    }
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Tidbits.Palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .chunkyCard(fill: Tidbits.Palette.surface)
                .padding(.trailing, Tidbits.Metric.shadowOffset)
            }
            if live {
                Button("Submit Order") { game.submitOrder() }
                    .buttonStyle(ChunkyButtonStyle(fill: game.mode.accent,
                                                   textColor: game.mode.accent.legibleForeground))
            }
        }
    }

    // MARK: Closest Call slider

    private func closestFmt(_ v: Double, _ spec: ClosestSpec) -> String {
        let n = Int(v.rounded())
        // Years (no unit) read without a thousands separator; sized units keep it.
        if spec.unit.isEmpty { return String(n) }
        let s = abs(n) >= 1000 ? n.formatted(.number.grouping(.automatic)) : String(n)
        return "\(s) \(spec.unit)"
    }

    private func closestPanel(_ spec: ClosestSpec) -> some View {
        let live = game.phase == .playing
        return VStack(spacing: 14) {
            Text(closestFmt(game.currentGuess, spec))
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
                .contentTransition(.numericText())
            Slider(value: Binding(get: { game.currentGuess }, set: { game.setGuess($0) }),
                   in: spec.min...spec.max, step: spec.step)
                .tint(game.mode.accent)
                .disabled(!live)
            HStack {
                Text(closestFmt(spec.min, spec)).font(Tidbits.TypeRamp.l5)
                Spacer()
                Text(closestFmt(spec.max, spec)).font(Tidbits.TypeRamp.l5)
            }
            .foregroundStyle(Tidbits.Palette.inkSoft)
            if live {
                Button("Lock In") { game.submitGuess() }
                    .buttonStyle(ChunkyButtonStyle(fill: game.mode.accent,
                                                   textColor: game.mode.accent.legibleForeground))
            }
        }
        .padding(16)
        .chunkyCard(fill: Tidbits.Palette.bgDeep)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    // MARK: Picture ID header

    /// The image to identify (Picture mode). `.fit` inside a fixed-height frame —
    /// never fill-in-an-infinite-frame (the layout-blowup gotcha). Async with a
    /// loading + failure fallback (the image needs the network; the bundled
    /// corpus stays offline for every other mode).
    private func pictureHeader(_ url: URL) -> some View {
        AsyncImage(url: url, transaction: .init(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fit)
            case .failure:
                VStack(spacing: 6) {
                    Image(systemName: "photo").font(.system(size: 34, weight: .bold))
                    Text("Couldn't load the image").font(Tidbits.TypeRamp.l5)
                }.foregroundStyle(Tidbits.Palette.inkSoft).frame(maxWidth: .infinity)
            default:
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .background(Tidbits.Palette.bgDeep)
        .clipShape(RoundedRectangle(cornerRadius: Tidbits.Metric.radius, style: .continuous))
        .chunkyCard(fill: Tidbits.Palette.bgDeep)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    // MARK: Sweep fill-grid

    /// The persistent "set" scoreboard — one cell per question. Filled green
    /// (hit) / coral (miss) as you go, the current cell outlined, the rest dim.
    /// The grid IS the progress indicator and the reward (Sporcle's 37/45).
    private var sweepGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 7), count: 6)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Set: \(game.score) / \(game.questions.count)")
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
            LazyVGrid(columns: cols, spacing: 7) {
                ForEach(0..<game.questions.count, id: \.self) { i in
                    let answered = i < game.answered.count
                    let hit = answered && game.answered[i].isCorrect
                    let current = i == game.index
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(answered ? (hit ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                                       : Tidbits.Palette.surface)
                        .frame(height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Tidbits.Palette.border,
                                          lineWidth: current ? 2.5 : 1.5))
                        .opacity(answered || current ? 1 : 0.45)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .chunkyCard(fill: Tidbits.Palette.bgDeep)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private func answerState(idx: Int, q: Question) -> AnswerButton.State {
        guard game.phase == .reveal else { return .idle }
        if idx == q.correctIndex { return .correct }
        if idx == game.chosenIndex { return .wrong }
        return .dimmed
    }

    // MARK: Reveal / learn

    private func reveal(for q: Question) -> some View {
        let correct = game.lastAnswer?.isCorrect ?? false
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: correct ? "checkmark.seal.fill" : "lightbulb.fill")
                    .foregroundStyle(correct ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                Text(correct ? "Nice — you knew it." : "Now you know.")
                    .font(Tidbits.TypeRamp.l3)
                    .foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                if game.mode == .stake {
                    Text(correct ? "+\(game.currentStake)" : "+0")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(correct ? Tidbits.Palette.mint.legibleForeground : Tidbits.Palette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(correct ? Tidbits.Palette.mint : Tidbits.Palette.surface))
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                }
                if game.mode == .closestCall {
                    Text("+\(game.lastGuessPoints)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(game.lastGuessPoints > 0 ? Tidbits.Palette.mint.legibleForeground : Tidbits.Palette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(game.lastGuessPoints > 0 ? Tidbits.Palette.mint : Tidbits.Palette.surface))
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                }
                if game.mode == .ordering {
                    Text("+\(game.lastOrderPoints)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(game.lastOrderPoints > 0 ? Tidbits.Palette.mint.legibleForeground : Tidbits.Palette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(game.lastOrderPoints > 0 ? Tidbits.Palette.mint : Tidbits.Palette.surface))
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                }
                if game.mode == .matching {
                    Text("+\(game.lastMatchPoints)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(game.lastMatchPoints > 0 ? Tidbits.Palette.mint.legibleForeground : Tidbits.Palette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(game.lastMatchPoints > 0 ? Tidbits.Palette.mint : Tidbits.Palette.surface))
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                }
            }
            if let spec = q.closest {
                let off = Int(abs(game.currentGuess - spec.answer).rounded())
                Text("You said \(closestFmt(game.currentGuess, spec)) · actual \(spec.formattedAnswer) · off by \(off)")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            if q.accepted != nil {
                Text("Answer: \(q.correctAnswer)")
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
            }
            if let spec = q.enumerate {
                let named = Set(game.enumNamed)
                Text("You named \(game.enumFilled.count) of \(spec.total)")
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(spec.displayNames, id: \.self) { name in
                        let got = named.contains(name)
                        Text(name)
                            .font(Tidbits.TypeRamp.l5).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6).padding(.horizontal, 5)
                            .background(RoundedRectangle(cornerRadius: 8).fill(got ? Tidbits.Palette.mint.opacity(0.22) : Tidbits.Palette.surface))
                            .foregroundStyle(got ? Tidbits.Palette.ink : Tidbits.Palette.inkSoft)
                    }
                }
            }
            if !q.explanation.isEmpty {
                Text(q.explanation)
                    .font(Tidbits.TypeRamp.l4)
                    .foregroundStyle(Tidbits.Palette.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = q.sourceURL {
                Link(destination: url) {
                    Label("Read \(q.sourceTitle) on Wikipedia", systemImage: "arrow.up.right.square")
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .chunkyCard(fill: Tidbits.Palette.bgDeep)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var nextBar: some View {
        Button(action: { game.advance() }) {
            Text(isLast ? "See Results" : "Next")
        }
        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.ink, textColor: .white))
        .padding(.horizontal, Tidbits.Metric.pad)
        .padding(.bottom, 16)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var isLast: Bool {
        (game.mode == .classic || game.mode == .daily || game.mode == .stake || game.mode == .sweep || game.mode == .pictureId || game.mode == .thisOrThat || game.mode == .closestCall || game.mode == .ordering || game.mode == .matching || game.mode == .typeAnswer || game.mode == .oddOneOut || game.mode == .ladder || game.mode == .enumerate) && game.index + 1 >= game.questions.count
    }
}

/// One confidence-chip button in Stake mode. Shows the tier label, its point
/// value, and how many remain; disabled at zero (unless already selected).
private struct StakeChip: View {
    let tier: StakeTier
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let usable = tier.remaining > 0 || selected
        Button(action: action) {
            VStack(spacing: 2) {
                Text(tier.label).font(.system(size: 15, weight: .black, design: .rounded))
                Text("+\(tier.value) · \(tier.remaining) left").font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(selected ? Tidbits.Palette.mint.legibleForeground : Tidbits.Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Tidbits.Palette.mint : Tidbits.Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            .opacity(usable ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!usable)
    }
}
#endif
