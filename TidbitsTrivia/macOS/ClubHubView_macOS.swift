#if os(macOS)
import SwiftUI
import SwiftData

/// The Mac's one door to Tidbits Club (rule R-CLUB-1, iOS-DESIGN §5.2a — the rule is
/// cross-platform; only the idiom differs). Mirror of `ClubHubView`, in the Mac sheet
/// idiom: a sized sheet with a Done header, `CompactButtonStyle`, and a pointer-friendly
/// row list rather than iOS's touch-sized chunky cards.
///
/// Members only. Home routes non-members to `ClubPaywallView_macOS`, so nothing in here
/// carries a lock, a badge, or a price — inside the door, Club is just features.
///
/// Rounds are launched by Home, not here: the three play rows call back so the hub closes
/// first and the game replaces the window root (macOS-DESIGN — a game in progress REPLACES
/// the window root; it must never run under a sheet).
struct ClubHubView_macOS: View {
    var onStartWeakSpot: () -> Void
    var onStartMarathon: () -> Void
    var onOpenLinkWall: () -> Void
    /// Expedition stage play has to reach the window root too (same rule as a round).
    var onExpedition: (Expedition, Int) -> Void
    /// The Atlas's per-domain rows are tap-to-play doors — they need the root as well.
    var onPlay: (LaunchRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var marathonRuns: [MarathonRun]
    @Query(sort: \MarathonScore.date, order: .reverse) private var marathonHistory: [MarathonScore]
    @Query private var expeditionProgress: [ExpeditionProgress]
    @Query(sort: \LinkWallResult.date, order: .reverse) private var linkWallResults: [LinkWallResult]
    @State private var showExpeditions = false
    @State private var showStoryArchive = false
    @State private var showAtlas = false
    @State private var showMarathonHistory = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tidbits Club").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(CompactButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    memberBanner
                    section("Play") {
                        row("square.grid.3x3.fill", "Link Wall", linkWallSubtitle, Tidbits.Palette.mint) { dismiss(); onOpenLinkWall() }
                        row("target", "Weak-Spot Arena", weakSpotSubtitle, Tidbits.Palette.coral) { dismiss(); onStartWeakSpot() }
                        row("figure.run", "Marathon", marathonSubtitle, Tidbits.Palette.blue) { dismiss(); onStartMarathon() }
                        row("map.fill", "Expeditions", expeditionSubtitle, Tidbits.Palette.grape) { showExpeditions = true }
                    }
                    section("Your record") {
                        row("books.vertical.fill", "Story Archive", storySubtitle, Tidbits.Palette.blue) { showStoryArchive = true }
                        row("chart.xyaxis.line", "Knowledge Atlas", atlasSubtitle, Tidbits.Palette.mint) { showAtlas = true }
                        row("trophy.fill", "Marathon History", historySubtitle, Tidbits.Palette.yellow) { showMarathonHistory = true }
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 520, minHeight: 620)
        .background(Tidbits.Palette.bg)
        .sheet(isPresented: $showExpeditions) {
            ExpeditionsHubView_macOS(onPlayStage: { exp, stage in dismiss(); onExpedition(exp, stage) })
        }
        .sheet(isPresented: $showStoryArchive) { StoryArchiveView_macOS() }
        .sheet(isPresented: $showAtlas) { KnowledgeAtlasView_macOS(onPlay: { req in dismiss(); onPlay(req) }) }
        .sheet(isPresented: $showMarathonHistory) { MarathonHistoryView_macOS() }
        .task {
            if DebugHooks.openExpedition || DebugHooks.expeditionMapPreview != nil || DebugHooks.expeditionAutoplay != nil {
                showExpeditions = true
            }
            if DebugHooks.openStoryArchive { showStoryArchive = true }
            if DebugHooks.openAtlas { showAtlas = true }
        }
    }

    private var memberBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 20)).foregroundStyle(Tidbits.Palette.mint)
            VStack(alignment: .leading, spacing: 1) {
                Text("You're a member").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Text("Everything below is yours. The rest of Tidbits stays free for everyone.")
                    .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .chunkyCard(fill: Tidbits.Palette.surface)
    }

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
            rows()
        }
    }

    private func row(_ icon: String, _ title: String, _ subtitle: String,
                     _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 19, weight: .bold))
                    .foregroundStyle(tint).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Text(subtitle).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .chunkyCard(fill: Tidbits.Palette.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Live subtitles — a member's real state, never a pitch

    private var linkWallSubtitle: String {
        let today = linkWallResults.first { $0.day == QuestionProvider.dayKey() }
        if let today, today.completed { return "Today's board is done. Back tomorrow." }
        if today != nil { return "Today's board is in progress." }
        return "Today's board is waiting — 16 facts, 4 hidden groups."
    }

    private var weakSpotSubtitle: String {
        WeakSpotArena.previewLine(in: modelContext) ?? "A round built entirely from the questions you've missed."
    }

    private var marathonSubtitle: String {
        if let run = marathonRuns.first { return "Question \(run.currentIndex + 1) of \(run.total) — resume where you left off." }
        if let last = marathonHistory.first { return "\(Int(last.accuracy * 100))% on your last run. Start another." }
        return "200 questions, graded by domain. Stop and resume anytime."
    }

    private var expeditionSubtitle: String {
        let active = expeditionProgress.count
        return active > 0 ? "\(active) campaign\(active == 1 ? "" : "s") in progress."
                          : "Multi-week campaigns through one domain."
    }

    private var storySubtitle: String {
        StoryArchive.previewLine(in: modelContext) ?? "Every story behind every answer you've unlocked."
    }

    private var atlasSubtitle: String { "What you actually know, by domain, over time." }

    private var historySubtitle: String {
        marathonHistory.isEmpty ? "Your finished runs, kept forever."
                                : "\(marathonHistory.count) run\(marathonHistory.count == 1 ? "" : "s") on record."
    }
}
#endif
