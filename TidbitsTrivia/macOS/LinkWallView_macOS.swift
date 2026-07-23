#if os(macOS)
import SwiftUI
import SwiftData

/// Mac mirror of the Club Link Wall (docs/CLUB-FEATURES-BUILD.md "Feature 6",
/// canonical at `iOS/Views/LinkWallView.swift`) — the NYT-Connections-style
/// second daily, built on the SAME content-clean `Core/Store/LinkWall.swift`
/// generator. Presented as a sized sheet with a Done header (the
/// `SheetChrome_macOS` idiom, see `MarathonHistoryView_macOS` /
/// `ExpeditionsHubView_macOS`) — pointer + click, not a window-root swap,
/// since Link Wall never routes through `GameEngine`/`GameContainerView_macOS`.
struct LinkWallView_macOS: View {
    let day: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    private let puzzle: LinkWall.LinkWallPuzzle?

    @State private var result: LinkWallResult
    @State private var remainingTiles: [String]
    @State private var solvedGroups: [LinkWall.LinkWallGroup] = []
    @State private var selected: [String] = []
    @State private var oneAwayMessage: String?
    @State private var shakeAmount: CGFloat = 0
    @State private var loaded = false

    init(day: String) {
        self.day = day
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
        VStack(spacing: 0) {
            HStack {
                Text("Link Wall").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(CompactButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            Group {
                if let puzzle {
                    if result.completed {
                        LinkWallResultView_macOS(day: day, puzzle: puzzle, result: result)
                    } else {
                        board(puzzle)
                    }
                } else {
                    VStack(spacing: 10) {
                        Text("Link Wall isn't ready").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                        Text("Couldn't build today's board from the corpus. Try again tomorrow.")
                            .font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(20)
                }
            }
        }
        .frame(width: 560, height: 720)
        .background(Tidbits.Palette.bg)
        .task { loadIfNeeded() }
        .task { await runAutoplayIfNeeded() }
    }

    /// TIDBITS_LINKWALL_AUTOPLAY observability hook (see `DebugHooks`) — no-op
    /// in production. Same play loop as the iOS reference, driven through
    /// `submit()` exactly like a real click would.
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

    // MARK: - Board

    private func board(_ puzzle: LinkWall.LinkWallPuzzle) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Find the four groups of four.")
                    .font(Tidbits.TypeRamp.l4)
                    .foregroundStyle(Tidbits.Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                mistakesRow
                ForEach(solvedGroups, id: \.label) { g in solvedRow(g) }
                tileGrid
                if let oneAwayMessage {
                    Text(oneAwayMessage)
                        .font(Tidbits.TypeRamp.l3)
                        .foregroundStyle(Tidbits.Palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Tidbits.Palette.yellow))
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                        .transition(.scale.combined(with: .opacity))
                }
                actionButtons
            }
            .padding(20)
        }
        .task(id: oneAwayMessage) {
            guard oneAwayMessage != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { oneAwayMessage = nil }
        }
    }

    private var mistakesRow: some View {
        HStack(spacing: 10) {
            Text("MISTAKES")
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < (4 - result.mistakes) ? Tidbits.Palette.ink : Tidbits.Palette.bgDeep)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 1.5))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func solvedRow(_ g: LinkWall.LinkWallGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(g.label.uppercased())
                .font(Tidbits.TypeRamp.l3)
                .foregroundStyle(LinkWallPalette_macOS.color(for: g.difficulty).legibleForeground)
            Text(g.members.joined(separator: " · "))
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(LinkWallPalette_macOS.color(for: g.difficulty).legibleForeground.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinkWallPalette_macOS.color(for: g.difficulty)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }

    private var gridColumns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: 4) }

    private var tileGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            ForEach(remainingTiles, id: \.self) { tile in
                LinkWallTileButton_macOS(text: tile, isSelected: selected.contains(tile)) { toggle(tile) }
            }
        }
        .modifier(LinkWallShakeEffect_macOS(animatableData: shakeAmount))
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button("Deselect All") { withAnimation { selected = [] } }
                .buttonStyle(CompactButtonStyle())
                .disabled(selected.isEmpty)
            Button("Shuffle") { withAnimation { remainingTiles.shuffle() } }
                .buttonStyle(CompactButtonStyle())
            Spacer(minLength: 0)
            Button("Submit") { submit() }
                .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.coral, textColor: .white, prominent: true))
                .keyboardShortcut(.defaultAction)
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
}

// MARK: - Result screen (win or loss — reveal + shareable colored-square grid)

private struct LinkWallResultView_macOS: View {
    let day: String
    let puzzle: LinkWall.LinkWallPuzzle
    let result: LinkWallResult

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if !result.guessHistory.isEmpty { shareGrid }
                groupsReveal
                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.blue, textColor: .white, prominent: true))
            }
            .padding(20)
        }
        .background(Tidbits.Palette.bg)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: result.won ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(result.won ? Tidbits.Palette.mint : Tidbits.Palette.coral)
            Text(result.won ? "SOLVED" : "NEXT TIME")
                .font(Tidbits.TypeRamp.l1)
                .foregroundStyle(Tidbits.Palette.ink)
            Text(result.won
                 ? "\(result.mistakes) mistake\(result.mistakes == 1 ? "" : "s") — nice work."
                 : "Here's today's four groups. New wall tomorrow.")
                .font(Tidbits.TypeRamp.l4)
                .foregroundStyle(Tidbits.Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .chunkyCard(fill: (result.won ? Tidbits.Palette.mint : Tidbits.Palette.coral).opacity(0.16))
    }

    private var shareGrid: some View {
        VStack(spacing: 4) {
            ForEach(Array(result.guessHistory.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, difficulty in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinkWallPalette_macOS.color(for: difficulty))
                            .frame(width: 26, height: 26)
                    }
                }
            }
        }
    }

    private var groupsReveal: some View {
        VStack(spacing: 10) {
            ForEach(puzzle.groups, id: \.label) { g in
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.label.uppercased())
                        .font(Tidbits.TypeRamp.l3)
                        .foregroundStyle(LinkWallPalette_macOS.color(for: g.difficulty).legibleForeground)
                    Text(g.why)
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(LinkWallPalette_macOS.color(for: g.difficulty).legibleForeground.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinkWallPalette_macOS.color(for: g.difficulty)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            }
        }
    }

    private var shareText: String {
        var lines = ["Tidbits Link Wall — \(Self.dateLabel(day))"]
        lines.append(contentsOf: result.guessHistory.map { row in row.map(LinkWallPalette_macOS.emoji(for:)).joined() })
        lines.append(result.won
            ? "Solved in \(result.guessHistory.count) guess\(result.guessHistory.count == 1 ? "" : "es")."
            : "Didn't solve it today.")
        return lines.joined(separator: "\n")
    }

    private static func dateLabel(_ day: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: day) else { return day }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Shared difficulty → color/emoji (yellow → green → blue → purple, the Connections convention)

private enum LinkWallPalette_macOS {
    static func color(for difficulty: Int) -> Color {
        switch difficulty {
        case 1: return Tidbits.Palette.yellow
        case 2: return Tidbits.Palette.mint
        case 3: return Tidbits.Palette.blue
        default: return Tidbits.Palette.grape
        }
    }

    static func emoji(for difficulty: Int) -> String {
        switch difficulty {
        case 1: return "🟨"
        case 2: return "🟩"
        case 3: return "🟦"
        default: return "🟪"
        }
    }
}

// MARK: - Tile button (click, not tap — a hover highlight is the pointer affordance)

private struct LinkWallTileButton_macOS: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Tidbits.TypeRamp.l4.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isSelected ? Color.white : Tidbits.Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 76)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Tidbits.Palette.ink : (hovering ? Tidbits.Palette.bgDeep : Tidbits.Palette.surface)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.12), value: isSelected)
    }
}

// MARK: - Wrong-guess shake

private struct LinkWallShakeEffect_macOS: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * shakesPerUnit), y: 0))
    }
}
#endif
