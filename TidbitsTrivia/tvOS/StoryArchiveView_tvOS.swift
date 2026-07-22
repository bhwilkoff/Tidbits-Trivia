#if os(tvOS)
import SwiftUI
import SwiftData

/// tvOS mirror of the Club Story Archive (docs/CLUB-FEATURES-BUILD.md
/// "Feature 2", canonical at `iOS/Views/StoryArchiveView.swift`) — the
/// persistent library of every story the player has unlocked, ten-foot and
/// dark-first. Reached only through the Club-gated Records entry point; the
/// free in-moment story reveal is untouched (R-MON-1).
///
/// Deliberate platform deviation (tvos-platform-patterns): free-text search
/// is a keyboard wall at ten feet, so unlike iOS/macOS this surface drops
/// `.searchable` entirely and relies on FILTER CHIPS (All/Favorites/Missed/
/// Got it) + domain chips over the focusable list — the same idiom the
/// type-answer round uses to avoid text entry (recall, not typing).
struct StoryArchiveView_tvOS: View {
    @Query(sort: \SeenStory.lastSeen, order: .reverse) private var stories: [SeenStory]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var filter: StoryFilter = .all
    @State private var domain: String?
    @State private var detail: SeenStory?
    // Lifted to this level (mirrors the macOS fix): stacking a 3rd
    // fullScreenCover inside the detail screen risks the same one-modal-at-
    // a-time ceiling AppKit enforces for .sheet, so "Re-ask this" dismisses
    // the detail cover and hands off to a sibling cover here instead.
    @State private var reaskQuestion: Question?

    private var filtered: [SeenStory] {
        StoryArchive.search(stories, text: "", domain: domain, filter: filter)
    }

    private var presentDomains: [TriviaCategory] {
        let ids = Set(stories.map(\.categoryID))
        return TriviaCategory.all.filter { ids.contains($0.id) }
    }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Text("STORY ARCHIVE")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(TVTheme.text)
                    if stories.isEmpty {
                        emptyState
                    } else {
                        filterRow
                        domainRow
                        if filtered.isEmpty {
                            Text("No stories match.")
                                .font(.system(size: 29, weight: .medium, design: .rounded))
                                .foregroundStyle(TVTheme.textSoft)
                        } else {
                            VStack(spacing: 20) {
                                ForEach(filtered) { story in
                                    Button { detail = story } label: { StoryRow_tvOS(story: story) }
                                        .buttonStyle(TVStoryRowStyle())
                                }
                            }
                            .focusSection()
                        }
                    }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onExitCommand { dismiss() }
        .fullScreenCover(item: $detail) { story in
            StoryDetailView_tvOS(story: story, onFavorite: { toggleFavorite(story) },
                                  onReask: { q in detail = nil; reaskQuestion = q })
        }
        .fullScreenCover(item: $reaskQuestion) { q in
            StoryReaskContainer_tvOS(question: q) { reaskQuestion = nil }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No stories yet")
                .font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("Play a few rounds — the stories you unlock are kept here forever.")
                .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 20) {
            ForEach(StoryFilter.allCases) { f in
                Button(f.label) { filter = f }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.teal, selected: filter == f))
            }
        }
        .focusSection()
    }

    private var domainRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                domainChip(nil, name: "All domains")
                ForEach(presentDomains) { cat in domainChip(cat.id, name: cat.name) }
            }
        }
        .scrollClipDisabled()
        .focusSection()
    }

    private func domainChip(_ id: String?, name: String) -> some View {
        Button(name) { domain = id }
            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: domain == id))
    }

    private func toggleFavorite(_ story: SeenStory) {
        StoryArchive.toggleFavorite(qid: story.questionID, in: modelContext)
    }
}

// MARK: - Story row (view-only favorite mark — the toggle lives in the detail screen)

private struct StoryRow_tvOS: View {
    let story: SeenStory
    var body: some View {
        let cat = TriviaCategory.named(story.categoryID)
        HStack(spacing: 24) {
            Image(systemName: cat.symbol).font(.system(size: 30, weight: .black)).foregroundStyle(cat.color.legibleForeground)
                .frame(width: 60, height: 60)
                .background(Circle().fill(cat.color))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(cat.name.uppercased()).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    if story.favorite {
                        Image(systemName: "star.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(Tidbits.Palette.yellow)
                    }
                    Spacer()
                    Image(systemName: story.everCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(story.everCorrect ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                }
                Text(story.prompt).font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                Text(story.lastSeen.formatted(.relative(presentation: .named)))
                    .font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TVStoryRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(focused ? TVTheme.panel : TVTheme.panel.opacity(0.72)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 4))
                .scaleEffect(focused ? 1.012 : 1.0)
                .animation(.easeOut(duration: 0.16), value: focused)
        }
    }
}

// MARK: - Story detail (the full story + favorite toggle + "Re-ask this")

private struct StoryDetailView_tvOS: View {
    let story: SeenStory
    let onFavorite: () -> Void
    /// Handed up to `StoryArchiveView_tvOS`, which dismisses this cover and
    /// presents the re-ask drill as a sibling cover.
    let onReask: (Question) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        Text(TriviaCategory.named(story.categoryID).name.uppercased())
                            .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        Spacer()
                        Button(story.favorite ? "Favorited" : "Add to Favorites", action: onFavorite)
                            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.yellow, selected: story.favorite))
                    }
                    Text(story.prompt)
                        .font(.system(size: 48, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Answer: \(story.correctAnswer)")
                        .font(.system(size: 33, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.mint)
                    Text(story.story)
                        .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if let q = story.question {
                        Button("Re-ask this") { onReask(q) }
                            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                    }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
                .frame(maxWidth: 1400, alignment: .leading)
            }
        }
        .onExitCommand { dismiss() }
    }
}

// MARK: - "Re-ask this" — a 1-question drill on the shared engine

/// Mirrors how `VersusContainer_macOS`/`TVGameContainer` reuse the shared
/// `store.game` for a match that shouldn't persist a `GameRecord` (a
/// single-question re-ask isn't a "game," same call the iOS reference made —
/// "versus matches don't write records" is the established precedent here,
/// since `TVGamePlayView` reads `store.game` via environment rather than
/// taking an injected engine).
private struct StoryReaskContainer_tvOS: View {
    let question: Question
    let onDone: () -> Void
    @Environment(AppStore.self) private var store
    @State private var started = false

    private var game: GameEngine { store.game }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                ProgressView().controlSize(.extraLarge).tint(.white)
            case .roundIntro, .playing, .reveal:
                TVGamePlayView(onQuit: close)
            case .finished:
                TVResultsView(summary: game.summary, onPlayAgain: nil, onDone: close)
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            game.startCustom(mode: .classic, category: .named(question.categoryID), questions: [question])
        }
        .onExitCommand(perform: close)
    }

    private func close() { game.quit(); onDone() }
}
#endif
