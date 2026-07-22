#if os(macOS)
import SwiftUI
import SwiftData

/// Mac mirror of the Club Knowledge Atlas (docs/CLUB-FEATURES-BUILD.md
/// "Feature 4", canonical at `iOS/Views/KnowledgeAtlasView.swift`) — accuracy
/// by domain over the trailing 12 months, every domain row a tap target into
/// a domain round (never a passive stats wall). Reached only through the
/// Club-gated Records entry point; the free Topic Levels / Pie stay untouched
/// (R-MON-1). A domain tap hands a `LaunchRequest` up through `onPlay` to
/// `ContentView_macOS`, which swaps the whole window root into the game
/// (macOS-DESIGN §B2) — the same `onStart(request); dismiss()` shape
/// `CustomizeSheet_macOS` uses, one sheet deeper.
struct KnowledgeAtlasView_macOS: View {
    let onPlay: (LaunchRequest) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var domains: [KnowledgeAtlas.DomainAtlasEntry] { KnowledgeAtlas.domains(in: modelContext) }
    private var decaying: [KnowledgeAtlas.DecayEntry] { KnowledgeAtlas.decayRadar(in: modelContext) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Knowledge Atlas").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(CompactButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            Group {
                if domains.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Your accuracy by domain over the trailing 12 months. Click any domain to play a round in it.")
                                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(domains) { d in
                                Button { play(d.categoryID) } label: { DomainAtlasRow_macOS(entry: d) }
                                    .buttonStyle(.plain)
                            }
                            if !decaying.isEmpty { decayRadarSection }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .frame(width: 560, height: 680)
        .background(Tidbits.Palette.bg)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Not enough history yet", systemImage: "map.fill")
        } description: {
            Text("Play across a few domains and your Atlas fills in — it needs a few weeks of history to show a trajectory.")
        }
        .frame(maxHeight: .infinity)
    }

    private var decayRadarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Decay radar").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("Domains you were strong in 6+ months ago that have since slipped.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(decaying) { entry in
                DecayRow_macOS(entry: entry) { play(entry.categoryID) }
            }
        }
    }

    private func play(_ categoryID: String) {
        onPlay(LaunchRequest(mode: .classic, category: .named(categoryID)))
        dismiss()
    }
}

// MARK: - Domain row (accuracy, sample size, trajectory arrow — every number a door)

private struct DomainAtlasRow_macOS: View {
    let entry: KnowledgeAtlas.DomainAtlasEntry

    var body: some View {
        let cat = TriviaCategory.named(entry.categoryID)
        HStack(spacing: 12) {
            Image(systemName: cat.symbol).foregroundStyle(cat.color.legibleForeground)
                .frame(width: 34, height: 34).background(Circle().fill(cat.color))
                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(cat.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Spacer()
                    trajectoryBadge
                    Text("\(Int((entry.accuracy * 100).rounded()))%")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(Tidbits.Palette.ink)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tidbits.Palette.bgDeep)
                        Capsule().fill(cat.color).frame(width: max(6, geo.size.width * entry.accuracy))
                    }
                    .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                }
                .frame(height: 12)
                Text("\(entry.correct)/\(entry.sampleSize) answered · last 12 months")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
        }
        .padding(12).chunkyCard()
    }

    @ViewBuilder
    private var trajectoryBadge: some View {
        if let delta = entry.trajectoryDelta {
            let up = delta >= 0
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up" : "arrow.down")
                Text("\(Int((abs(delta) * 100).rounded()))")
            }
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(up ? Tidbits.Palette.mint : Tidbits.Palette.coral))
        }
    }
}

// MARK: - Decay radar row

private struct DecayRow_macOS: View {
    let entry: KnowledgeAtlas.DecayEntry
    let onPlay: () -> Void

    var body: some View {
        let cat = TriviaCategory.named(entry.categoryID)
        HStack(spacing: 12) {
            Image(systemName: cat.symbol).foregroundStyle(cat.color.legibleForeground)
                .frame(width: 34, height: 34).background(Circle().fill(cat.color))
                .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(cat.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Text("\(Int((entry.pastAccuracy * 100).rounded()))% then → \(Int((entry.recentAccuracy * 100).rounded()))% now")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Spacer(minLength: 8)
            Button("Shore it up", action: onPlay)
                .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.coral, textColor: .white, prominent: true))
        }
        .padding(12).chunkyCard(fill: Tidbits.Palette.bgDeep)
    }
}
#endif
