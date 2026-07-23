#if os(tvOS)
import SwiftUI
import SwiftData

/// Apple TV mirror of the Club Link Wall (docs/CLUB-FEATURES-BUILD.md
/// "Feature 6", canonical at `iOS/Views/LinkWallView.swift`) — the same
/// content-clean `Core/Store/LinkWall.swift` generator, ten-foot and
/// dark-first. The 4×4 grid is 16 FOCUSABLE tiles; pressing Select on a
/// focused tile TOGGLES its selected state (up to 4) — focus and selection
/// are deliberately separate visual states (a mint fill + checkmark badge for
/// selected, a white ring + scale for focus), per tvos-platform-patterns.
/// NEVER `.buttonStyle(.plain)` here — every tile is a custom `ButtonStyle`
/// that stays focusable.
struct LinkWallView_tvOS: View {
    let day: String
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    private let puzzle: LinkWall.LinkWallPuzzle?

    @State private var result: LinkWallResult
    @State private var remainingTiles: [String]
    @State private var solvedGroups: [LinkWall.LinkWallGroup] = []
    @State private var selected: [String] = []
    @State private var oneAwayMessage: String?
    @State private var shakeAmount: CGFloat = 0
    @State private var loaded = false
    @State private var hasClaimedInitialFocus = false
    @FocusState private var focus: LWFocus?

    private enum LWFocus: Hashable {
        case tile(String)
        case deselect, shuffle, submit
        case done
    }

    init(day: String, onDone: @escaping () -> Void) {
        self.day = day
        self.onDone = onDone
        let p = LinkWall.puzzle(for: day)
        self.puzzle = p
        _result = State(initialValue: LinkWallResult(day: day))
        _remainingTiles = State(initialValue: p?.tiles ?? [])
    }

    /// Every tile's true group — the answer key behind "one away", the
    /// collapse-on-correct, and the share grid's colors.
    private var tileGroup: [String: LinkWall.LinkWallGroup] {
        guard let puzzle else { return [:] }
        var map: [String: LinkWall.LinkWallGroup] = [:]
        for g in puzzle.groups { for m in g.members { map[m] = g } }
        return map
    }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            if let puzzle {
                if result.completed {
                    resultView(puzzle)
                } else {
                    board(puzzle)
                }
            } else {
                emptyState
            }
        }
        .onExitCommand { onDone() }
        .task {
            loadIfNeeded()
            if !hasClaimedInitialFocus, let first = remainingTiles.first {
                hasClaimedInitialFocus = true
                focus = .tile(first)
            }
        }
        .task { await runAutoplayIfNeeded() }
    }

    /// TIDBITS_LINKWALL_AUTOPLAY observability hook (see `DebugHooks`) — no-op
    /// in production. This dev box has no GUI Simulator window to press
    /// through a 4×4 grid with the Siri Remote, so this drives the exact same
    /// `submit()` path a real Select press would.
    private func runAutoplayIfNeeded() async {
        guard let mode = DebugHooks.linkWallAutoplay, let puzzle else { return }
        try? await Task.sleep(for: .seconds(0.4))
        if mode == "lose" {
            while !result.completed {
                guard let guess = wrongGuess(puzzle) else { break }
                selected = guess
                submit()
                try? await Task.sleep(for: .seconds(0.3))
            }
        } else {
            for g in puzzle.groups where !result.completed {
                selected = g.members
                submit()
                try? await Task.sleep(for: .seconds(0.3))
            }
        }
    }

    /// 3 members of one unsolved group + 1 outsider from another — guarantees
    /// a "one away" the first time, then just a plain miss thereafter.
    private func wrongGuess(_ puzzle: LinkWall.LinkWallPuzzle) -> [String]? {
        let unsolved = puzzle.groups.filter { g in !solvedGroups.contains(where: { $0.label == g.label }) }
        guard unsolved.count >= 2 else { return nil }
        var guess = Array(unsolved[0].members.prefix(3))
        guess.append(unsolved[1].members[0])
        return guess
    }

    /// Resumes a mid-progress or completed day from the persisted row rather
    /// than always starting a fresh board — `ModelContext` isn't available
    /// at `init`, so the real fetch happens here instead.
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let stored = LinkWallLog.resultOrCreate(for: day, in: modelContext)
        result = stored
        guard let puzzle else { return }
        let byLabel = Dictionary(uniqueKeysWithValues: puzzle.groups.map { ($0.label, $0) })
        solvedGroups = stored.solvedLabels.compactMap { byLabel[$0] }
        let solvedMembers = Set(solvedGroups.flatMap(\.members))
        remainingTiles = puzzle.tiles.filter { !solvedMembers.contains($0) }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link Wall isn't ready")
                .font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("Couldn't build today's board from the corpus. Try again tomorrow.")
                .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 90)
    }

    // MARK: - Board

    private func board(_ puzzle: LinkWall.LinkWallPuzzle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                Text("LINK WALL")
                    .font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(TVTheme.text)
                Text("Find the four groups of four.")
                    .font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                mistakesRow
                if !solvedGroups.isEmpty {
                    VStack(spacing: 14) { ForEach(solvedGroups, id: \.label) { g in solvedRow(g) } }
                }
                tileGrid
                    .focusSection()
                if let oneAwayMessage {
                    Text(oneAwayMessage)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(Tidbits.Palette.ink)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Capsule().fill(Tidbits.Palette.yellow))
                        .transition(.scale.combined(with: .opacity))
                }
                actionButtons
                    .focusSection()
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 60)
        }
        .task(id: oneAwayMessage) {
            guard oneAwayMessage != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { oneAwayMessage = nil }
        }
    }

    private var mistakesRow: some View {
        HStack(spacing: 16) {
            Text("MISTAKES")
                .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < (4 - result.mistakes) ? TVTheme.text : TVTheme.panel)
                        .frame(width: 20, height: 20)
                }
            }
        }
    }

    private func solvedRow(_ g: LinkWall.LinkWallGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(g.label.uppercased())
                .font(.system(size: 29, weight: .heavy, design: .rounded))
                .foregroundStyle(LinkWallPalette_tvOS.color(for: g.difficulty).legibleForeground)
            Text(g.members.joined(separator: " · "))
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundStyle(LinkWallPalette_tvOS.color(for: g.difficulty).legibleForeground.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinkWallPalette_tvOS.color(for: g.difficulty)))
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }

    private var gridColumns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 24), count: 4) }

    private var tileGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 24) {
            ForEach(remainingTiles, id: \.self) { tile in
                tileButton(tile)
            }
        }
        .modifier(LinkWallShakeEffect_tvOS(animatableData: shakeAmount))
    }

    private func tileButton(_ tile: String) -> some View {
        Button { toggle(tile) } label: {
            Text(tile)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, minHeight: 160)
        }
        .buttonStyle(TVLinkWallTileStyle(selected: selected.contains(tile)))
        .focused($focus, equals: .tile(tile))
    }

    private var actionButtons: some View {
        HStack(spacing: 24) {
            Button("Deselect All") { withAnimation { selected = [] } }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                .focused($focus, equals: .deselect)
                .disabled(selected.isEmpty)
            Button("Shuffle") { withAnimation { remainingTiles.shuffle() } }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                .focused($focus, equals: .shuffle)
            Button("Submit") { submit() }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                .focused($focus, equals: .submit)
                .disabled(selected.count != 4)
        }
    }

    // MARK: - Interaction

    private func toggle(_ tile: String) {
        if let idx = selected.firstIndex(of: tile) {
            selected.remove(at: idx)
        } else if selected.count < 4 {
            selected.append(tile)
        }
    }

    private func submit() {
        guard let puzzle, selected.count == 4 else { return }
        let selectedSet = Set(selected)
        let difficulties = selected.map { tileGroup[$0]?.difficulty ?? 0 }
        result.recordGuess(difficulties: difficulties)

        if let matched = puzzle.groups.first(where: { Set($0.members) == selectedSet }) {
            result.recordSolvedGroup(matched.label)
            withAnimation(.snappy) {
                solvedGroups.append(matched)
                remainingTiles.removeAll { selectedSet.contains($0) }
                selected = []
            }
            if solvedGroups.count == puzzle.groups.count { finish(won: true) }
        } else {
            result.mistakes += 1
            let closest = puzzle.groups.first { g in
                !solvedGroups.contains(where: { $0.label == g.label }) &&
                selected.filter({ g.members.contains($0) }).count == 3
            }
            withAnimation { oneAwayMessage = closest != nil ? "One away…" : nil }
            withAnimation(.linear(duration: 0.4)) { shakeAmount += 1 }
            if result.mistakes >= 4 { finish(won: false) }
        }
        try? modelContext.save()
    }

    /// Loss reveals every remaining group; win just locks the day. Either
    /// way `result.completed` flips, which swaps `body` to the result screen.
    private func finish(won: Bool) {
        guard let puzzle else { return }
        if !won {
            let remaining = puzzle.groups.filter { g in !solvedGroups.contains(where: { $0.label == g.label }) }
            withAnimation { solvedGroups.append(contentsOf: remaining) }
            selected = []
        }
        result.completed = true
        result.won = won
        try? modelContext.save()
    }

    // MARK: - Result screen (win or loss — reveal + the colored-square grid;
    // Share is skipped here per tvOS-platform-patterns — there's no share
    // sheet at ten feet, so the grid itself IS the on-screen shareable recap).

    private func resultView(_ puzzle: LinkWall.LinkWallPuzzle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                if !result.guessHistory.isEmpty { shareGrid }
                groupsReveal(puzzle)
                Button("Done") { onDone() }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                    .focused($focus, equals: .done)
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 60)
        }
        .defaultFocus($focus, .done)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: result.won ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.system(size: 56, weight: .black))
                .foregroundStyle(result.won ? Tidbits.Palette.mint : Tidbits.Palette.coral)
            Text(result.won ? "SOLVED" : "NEXT TIME")
                .font(.system(size: 52, weight: .black, design: .rounded)).foregroundStyle(TVTheme.text)
            Text(result.won
                 ? "\(result.mistakes) mistake\(result.mistakes == 1 ? "" : "s") — nice work."
                 : "Here's today's four groups. New wall tomorrow.")
                .font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
    }

    private var shareGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(result.guessHistory.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, difficulty in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinkWallPalette_tvOS.color(for: difficulty))
                            .frame(width: 40, height: 40)
                    }
                }
            }
        }
    }

    private func groupsReveal(_ puzzle: LinkWall.LinkWallPuzzle) -> some View {
        VStack(spacing: 14) {
            ForEach(puzzle.groups, id: \.label) { g in
                VStack(alignment: .leading, spacing: 4) {
                    Text(g.label.uppercased())
                        .font(.system(size: 29, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinkWallPalette_tvOS.color(for: g.difficulty).legibleForeground)
                    Text(g.why)
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundStyle(LinkWallPalette_tvOS.color(for: g.difficulty).legibleForeground.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinkWallPalette_tvOS.color(for: g.difficulty)))
            }
        }
    }
}

// MARK: - Shared difficulty → color (yellow → green → blue → purple, the Connections convention)

private enum LinkWallPalette_tvOS {
    static func color(for difficulty: Int) -> Color {
        switch difficulty {
        case 1: return Tidbits.Palette.yellow
        case 2: return Tidbits.Palette.mint
        case 3: return Tidbits.Palette.blue
        default: return Tidbits.Palette.grape
        }
    }
}

// MARK: - Tile button style — focus and selection are SEPARATE visual states:
// a mint fill + checkmark badge means selected (true regardless of focus); a
// white ring + scale means focused (true regardless of selection). Never
// `.buttonStyle(.plain)` — this custom style stays focusable.

private struct TVLinkWallTileStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration, selected: selected) }
    struct Inner: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .foregroundStyle(selected ? Tidbits.Palette.mint.legibleForeground : TVTheme.text)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(selected ? Tidbits.Palette.mint : TVTheme.panel))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 5))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26, weight: .black))
                            .foregroundStyle(Tidbits.Palette.mint.legibleForeground)
                            .padding(12)
                    }
                }
                .scaleEffect(focused ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.16), value: focused)
                .animation(.easeOut(duration: 0.16), value: selected)
        }
    }
}

// MARK: - Wrong-guess shake

private struct LinkWallShakeEffect_tvOS: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * shakesPerUnit), y: 0))
    }
}
#endif
