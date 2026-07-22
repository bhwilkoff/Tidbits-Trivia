#if os(iOS)
import SwiftUI
import SwiftData

/// The Club Story Archive — the persistent, searchable library of every
/// story the player has unlocked (docs/CLUB-FEATURES-BUILD.md "Feature 2").
/// Reached only through the Club-gated Records entry point; the free
/// in-moment story reveal (`Question.explanation` shown right after
/// answering) is untouched by this surface — additive, never subtractive
/// (R-MON-1).
struct StoryArchiveView: View {
    @Query(sort: \SeenStory.lastSeen, order: .reverse) private var stories: [SeenStory]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var filter: StoryFilter = .all
    @State private var domain: String?
    @State private var detail: SeenStory?

    private var filtered: [SeenStory] {
        StoryArchive.search(stories, text: searchText, domain: domain, filter: filter)
    }

    private var presentDomains: [TriviaCategory] {
        let ids = Set(stories.map(\.categoryID))
        return TriviaCategory.all.filter { ids.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if stories.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
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
                                        StoryCard(story: story, onFavorite: { toggleFavorite(story) })
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(Tidbits.Metric.pad)
                    }
                }
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationTitle("Story Archive")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search your stories")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: $detail) { story in
                StoryDetailSheet(story: story, onFavorite: { toggleFavorite(story) })
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No stories yet", systemImage: "books.vertical.fill")
        } description: {
            Text("Play a few rounds — the stories you unlock are kept here forever.")
        }
        .padding(.top, 60)
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(StoryFilter.allCases) { f in
                Button { filter = f } label: {
                    Text(f.label)
                        .font(Tidbits.TypeRamp.l5)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(filter == f ? Tidbits.Palette.teal : Tidbits.Palette.surface))
                        .foregroundStyle(filter == f ? Tidbits.Palette.teal.legibleForeground : Tidbits.Palette.ink)
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                }
                .buttonStyle(.plain)
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
        return Button { domain = id } label: {
            Text(name)
                .font(Tidbits.TypeRamp.l5)
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(on ? Tidbits.Palette.ink : Tidbits.Palette.surface))
                .foregroundStyle(on ? Color.white : Tidbits.Palette.ink)
                .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func toggleFavorite(_ story: SeenStory) {
        StoryArchive.toggleFavorite(qid: story.questionID, in: modelContext)
    }
}

// MARK: - Story card

private struct StoryCard: View {
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
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(story.everCorrect ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                Button(action: onFavorite) {
                    Image(systemName: story.favorite ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(story.favorite ? Tidbits.Palette.yellow : Tidbits.Palette.inkSoft)
                }
                .buttonStyle(.plain)
            }
            Text(story.prompt)
                .font(Tidbits.TypeRamp.l3)
                .foregroundStyle(Tidbits.Palette.ink)
                .lineLimit(2)
            Text("Answer: \(story.correctAnswer)")
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
            Text(story.lastSeen.formatted(.relative(presentation: .named)))
                .font(Tidbits.TypeRamp.l6)
                .foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .chunkyCard()
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }
}

// MARK: - Story detail (the full story + "Re-ask this")

private struct StoryDetailSheet: View {
    let story: SeenStory
    let onFavorite: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reask: Question?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(TriviaCategory.named(story.categoryID).name)
                            .font(Tidbits.TypeRamp.l5)
                            .foregroundStyle(Tidbits.Palette.inkSoft)
                        Spacer()
                        Button(action: onFavorite) {
                            Image(systemName: story.favorite ? "star.fill" : "star")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(story.favorite ? Tidbits.Palette.yellow : Tidbits.Palette.inkSoft)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(story.prompt).font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                    Text("Answer: \(story.correctAnswer)").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Text(story.story).font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let q = story.question {
                        Button {
                            reask = q
                        } label: {
                            Label("Re-ask this", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.blue, textColor: .white))
                    }
                }
                .padding(Tidbits.Metric.pad)
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .fullScreenCover(item: $reask) { q in
            StoryReaskContainer(question: q) { reask = nil }
        }
    }
}

// MARK: - "Re-ask this" — a 1-question drill on the shared engine (mirrors DuelGameContainer)

private struct StoryReaskContainer: View {
    let question: Question
    let onDone: () -> Void
    @State private var game = GameEngine()
    @State private var started = false

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                ProgressView().controlSize(.large).tint(Tidbits.Palette.ink)
            case .roundIntro, .playing, .reveal:
                GamePlayView(game: game, onQuit: close)
            case .finished:
                ResultsView(summary: game.summary, onPlayAgain: nil, onDone: close)
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            game.startCustom(mode: .classic, category: .named(question.categoryID), questions: [question])
        }
    }

    private func close() { game.quit(); onDone() }
}
#endif
