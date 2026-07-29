#if os(tvOS)
import SwiftUI
import SwiftData

/// tvOS mirror of the Club Knowledge Atlas (docs/CLUB-FEATURES-BUILD.md
/// "Feature 4", canonical at `iOS/Views/KnowledgeAtlasView.swift`) — accuracy
/// by domain over the trailing 12 months at ten feet, every domain row
/// focusable into a domain round (never a passive stats wall). Reached only
/// through the Club-gated Records entry point; the free Topic Levels / Pie
/// stay untouched (R-MON-1). A domain tap hands a `LaunchRequest` up through
/// `onPlay`, which `RecordsView_tvOS` forwards to `ContentView_tvOS` —
/// dismissing this cover and the Records cover in the same tick before
/// presenting the game, the same dismiss-then-relaunch shape as
/// `TVDailyArchive`/`TVMarathonChoiceView`.
struct KnowledgeAtlasView_tvOS: View {
    /// Set when this view is shown INLINE by the Club hub (which swaps its own content
    /// rather than stacking a nested `.fullScreenCover` — see `ClubHubView_tvOS`). nil means
    /// "I'm a modal, dismiss me."
    var onClose: (() -> Void)? = nil

    let onPlay: (LaunchRequest) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var domains: [KnowledgeAtlas.DomainAtlasEntry] { KnowledgeAtlas.domains(in: modelContext) }
    private var decaying: [KnowledgeAtlas.DecayEntry] { KnowledgeAtlas.decayRadar(in: modelContext) }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Text("KNOWLEDGE ATLAS")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(TVTheme.text)
                    if domains.isEmpty {
                        emptyState
                    } else {
                        Text("Your accuracy by domain over the trailing 12 months. Press any domain to play a round in it.")
                            .font(.system(size: 29, weight: .medium, design: .rounded))
                            .foregroundStyle(TVTheme.textSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 20) {
                            ForEach(domains) { d in
                                Button { play(d.categoryID) } label: { DomainAtlasRow_tvOS(entry: d) }
                                    .buttonStyle(TVStoryRowStyle())
                            }
                        }
                        .focusSection()
                        if !decaying.isEmpty { decayRadarSection }
                    }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onExitCommand { if let onClose { onClose() } else { dismiss() } }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Not enough history yet")
                .font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("Play across a few domains and your Atlas fills in — it needs a few weeks of history to show a trajectory.")
                .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var decayRadarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Decay radar").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.text)
            Text("Domains you were strong in 6+ months ago that have since slipped.")
                .font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 20) {
                ForEach(decaying) { entry in
                    DecayRow_tvOS(entry: entry) { play(entry.categoryID) }
                }
            }
            .focusSection()
        }
    }

    /// The Records cover this Atlas lives inside is dismissed by the caller
    /// (`RecordsView_tvOS`'s own `onPlay` wrapper) — this view only forwards
    /// the request, it never dismisses itself.
    private func play(_ categoryID: String) {
        onPlay(LaunchRequest(mode: .classic, category: .named(categoryID)))
    }
}

// MARK: - Domain row (accuracy, sample size, trajectory arrow — every number a door)

private struct DomainAtlasRow_tvOS: View {
    let entry: KnowledgeAtlas.DomainAtlasEntry

    var body: some View {
        let cat = TriviaCategory.named(entry.categoryID)
        HStack(spacing: 24) {
            Image(systemName: cat.symbol).font(.system(size: 30, weight: .black)).foregroundStyle(cat.color.legibleForeground)
                .frame(width: 60, height: 60)
                .background(Circle().fill(cat.color))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Text(cat.name).font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Spacer()
                    trajectoryBadge
                    Text("\(Int((entry.accuracy * 100).rounded()))%")
                        .font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(.white)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(cat.color).frame(width: max(10, geo.size.width * entry.accuracy))
                    }
                }
                .frame(height: 18)
                Text("\(entry.correct)/\(entry.sampleSize) answered · last 12 months")
                    .font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var trajectoryBadge: some View {
        if let delta = entry.trajectoryDelta {
            let up = delta >= 0
            HStack(spacing: 4) {
                Image(systemName: up ? "arrow.up" : "arrow.down")
                Text("\(Int((abs(delta) * 100).rounded()))")
            }
            .font(.system(size: 22, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(up ? Tidbits.Palette.mint : Tidbits.Palette.coral))
        }
    }
}

// MARK: - Decay radar row

private struct DecayRow_tvOS: View {
    let entry: KnowledgeAtlas.DecayEntry
    let onPlay: () -> Void

    var body: some View {
        let cat = TriviaCategory.named(entry.categoryID)
        HStack(spacing: 24) {
            Image(systemName: cat.symbol).font(.system(size: 30, weight: .black)).foregroundStyle(cat.color.legibleForeground)
                .frame(width: 60, height: 60)
                .background(Circle().fill(cat.color))
            VStack(alignment: .leading, spacing: 8) {
                Text(cat.name).font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("\(Int((entry.pastAccuracy * 100).rounded()))% then → \(Int((entry.recentAccuracy * 100).rounded()))% now")
                    .font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
            Spacer()
            Button("Shore it up", action: onPlay)
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(TVTheme.panel))
    }
}
#endif
