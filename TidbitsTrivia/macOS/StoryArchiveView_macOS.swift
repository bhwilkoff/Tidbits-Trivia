#if os(macOS)
import SwiftUI
import SwiftData

/// Mac mirror of the Club Story Archive (docs/CLUB-FEATURES-BUILD.md "Feature
/// 2", canonical at `iOS/Views/StoryArchiveView.swift`) — the persistent,
/// searchable library of every story the player has unlocked. Reached only
/// through the Club-gated Records entry point; the free in-moment story
/// reveal (`Question.explanation` shown right after answering) is untouched
/// by this surface — additive, never subtractive (R-MON-1). Presented as a
/// sized sheet with a Done header (the `SheetChrome_macOS` idiom from
/// `RecordsView_macOS`), pointer + keyboard native: a plain search field
/// (not `.searchable`, which needs a NavigationStack host to render) and
/// `CompactButtonStyle` filter chips.
struct StoryArchiveView_macOS: View {
    @Query(sort: \SeenStory.lastSeen, order: .reverse) private var stories: [SeenStory]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var filter: StoryFilter = .all
    @State private var domain: String?
    @State private var detail: SeenStory?
    // Lifted to this level (not nested inside the detail sheet): AppKit only
    // presents one sheet per window at a time, so "Re-ask this" dismisses the
    // detail sheet and hands off to a sibling sheet here rather than stacking
    // a 3rd sheet on top of it (which silently no-ops on macOS).
    @State private var reaskQuestion: Question?

    private var filtered: [SeenStory] {
        StoryArchive.search(stories, text: searchText, domain: domain, filter: filter)
    }

    private var presentDomains: [TriviaCategory] {
        let ids = Set(stories.map(\.categoryID))
        return TriviaCategory.all.filter { ids.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Story Archive").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(CompactButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            Group {
                if stories.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            searchField
                            filterRow
                            domainRow
                            if filtered.isEmpty {
                                Text("No stories match.")
                                    .font(Tidbits.TypeRamp.l5)
                                    .foregroundStyle(Tidbits.Palette.inkSoft)
                                    .padding(.top, 20)
                            } else {
                                ForEach(filtered) { story in
                                    Button { detail = story } label: {
                                        StoryCard_macOS(story: story, onFavorite: { toggleFavorite(story) })
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .frame(width: 560, height: 680)
        .background(Tidbits.Palette.bg)
        .sheet(item: $detail) { story in
            StoryDetailSheet_macOS(story: story, onFavorite: { toggleFavorite(story) },
                                   onReask: { q in detail = nil; reaskQuestion = q })
        }
        .sheet(item: $reaskQuestion) { q in
            StoryReaskContainer_macOS(question: q) { reaskQuestion = nil }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No stories yet", systemImage: "books.vertical.fill")
        } description: {
            Text("Play a few rounds — the stories you unlock are kept here forever.")
        }
        .frame(maxHeight: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Tidbits.Palette.inkSoft)
            TextField("Search your stories", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Tidbits.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Tidbits.Palette.border, lineWidth: 2))
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(StoryFilter.allCases) { f in
                Button(f.label) { filter = f }
                    .buttonStyle(CompactButtonStyle(fill: filter == f ? Tidbits.Palette.teal : Tidbits.Palette.surface,
                                                     textColor: filter == f ? Tidbits.Palette.teal.legibleForeground : Tidbits.Palette.ink))
            }
        }
    }

    private var domainRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                domainChip(nil, name: "All domains")
                ForEach(presentDomains) { cat in domainChip(cat.id, name: cat.name) }
            }
        }
    }

    private func domainChip(_ id: String?, name: String) -> some View {
        let on = domain == id
        return Button(name) { domain = id }
            .buttonStyle(CompactButtonStyle(fill: on ? Tidbits.Palette.ink : Tidbits.Palette.surface,
                                             textColor: on ? .white : Tidbits.Palette.ink))
    }

    private func toggleFavorite(_ story: SeenStory) {
        StoryArchive.toggleFavorite(qid: story.questionID, in: modelContext)
    }
}

// MARK: - Story card

private struct StoryCard_macOS: View {
    let story: SeenStory
    let onFavorite: () -> Void

    var body: some View {
        let cat = TriviaCategory.named(story.categoryID)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(cat.name.uppercased())
                    .font(Tidbits.TypeRamp.l6)
                    .foregroundStyle(cat.color.legibleAccent)
                Spacer()
                Image(systemName: story.everCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(story.everCorrect ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                Button(action: onFavorite) {
                    Image(systemName: story.favorite ? "star.fill" : "star")
                        .foregroundStyle(story.favorite ? Tidbits.Palette.yellow : Tidbits.Palette.inkSoft)
                }
                .buttonStyle(.plain)
            }
            Text(story.prompt).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink).lineLimit(2)
            Text("Answer: \(story.correctAnswer)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            Text(story.lastSeen.formatted(.relative(presentation: .named)))
                .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).chunkyCard()
    }
}

// MARK: - Story detail (the full story + "Re-ask this")

private struct StoryDetailSheet_macOS: View {
    let story: SeenStory
    let onFavorite: () -> Void
    /// Handed up to `StoryArchiveView_macOS`, which dismisses this sheet and
    /// presents the re-ask drill as a sibling sheet (AppKit shows one sheet
    /// per window at a time — nesting a 3rd sheet inside this one no-ops).
    let onReask: (Question) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(TriviaCategory.named(story.categoryID).name).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                Spacer()
                Button(action: onFavorite) {
                    Image(systemName: story.favorite ? "star.fill" : "star")
                        .foregroundStyle(story.favorite ? Tidbits.Palette.yellow : Tidbits.Palette.inkSoft)
                }
                .buttonStyle(.plain)
                Button("Done") { dismiss() }
                    .buttonStyle(CompactButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(story.prompt).font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                    Text("Answer: \(story.correctAnswer)").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Text(story.story).font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let q = story.question {
                        Button("Re-ask this") { onReask(q) }
                            .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.blue, textColor: .white, prominent: true))
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 560)
        .background(Tidbits.Palette.bg)
    }
}

// MARK: - "Re-ask this" — a 1-question drill on a throwaway engine

/// A single-question drill that does NOT write a `GameRecord` (a 1-question
/// re-ask isn't a "game" — same judgment call the iOS reference made). Uses a
/// throwaway `GameEngine` instance (not `store.game`) so it never disturbs
/// whatever the shared app engine is doing.
private struct StoryReaskContainer_macOS: View {
    let question: Question
    let onDone: () -> Void
    @State private var game = GameEngine()
    @State private var started = false

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                ProgressView().controlSize(.large)
            case .roundIntro, .playing, .reveal:
                GameView_macOS(game: game, onQuit: close)
            case .finished:
                ResultsView_macOS(summary: game.summary, onPlayAgain: nil, onDone: close)
            }
        }
        .frame(width: 560, height: 640)
        .onAppear {
            guard !started else { return }
            started = true
            game.startCustom(mode: .classic, category: .named(question.categoryID), questions: [question])
        }
    }

    private func close() { game.quit(); onDone() }
}
#endif
