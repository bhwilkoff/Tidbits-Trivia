#if os(iOS)
import SwiftUI
import SwiftData

/// The one door to Tidbits Club (iOS-DESIGN §5.2a, rule R-CLUB-1).
///
/// Every Club feature is reached from here and from nowhere else. Before this existed,
/// Home carried four Club cards and Records carried three Club "see all" rows — seven
/// visible locks in a mostly-FREE app, which read as a freemium funnel and made every
/// screen feel like a pitch. The count of visible locks, not the real free/paid ratio, is
/// what a player perceives as the size of the paywall.
///
/// Members land here; non-members never do — Home routes them to `ClubPaywallView`
/// instead, so this view can assume membership and drop every lock icon, badge and upsell.
/// That is the point: inside the door, Club is just features.
///
/// Rounds are NOT launched from here. Starting a game inside a sheet would leave the hub
/// stacked under the player; instead the three play rows call back to Home, which dismisses
/// the hub and drives its own `fullScreenCover`. The read-only surfaces (Story Archive,
/// Knowledge Atlas, Marathon History, Expeditions) stay self-contained sheets exactly as
/// they were when Records/Home presented them — only the entry point moved.
struct ClubHubView: View {
    /// Home dismisses the hub, then starts the Weak-Spot round.
    var onStartWeakSpot: () -> Void
    /// Home dismisses the hub, then resumes-or-starts a Marathon (it owns the run query
    /// and the Resume / Start Over dialog).
    var onStartMarathon: () -> Void
    /// Home dismisses the hub, then opens today's Link Wall board.
    var onOpenLinkWall: () -> Void

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    memberBanner
                    section("Play") {
                        row("square.grid.3x3.fill", "Link Wall", linkWallSubtitle, Tidbits.Palette.mint, onOpenLinkWall)
                        row("target", "Weak-Spot Arena", weakSpotSubtitle, Tidbits.Palette.coral, onStartWeakSpot)
                        row("figure.run", "Marathon", marathonSubtitle, Tidbits.Palette.blue, onStartMarathon)
                        row("map.fill", "Expeditions", expeditionSubtitle, Tidbits.Palette.grape) { showExpeditions = true }
                    }
                    section("Your record") {
                        row("books.vertical.fill", "Story Archive", storySubtitle, Tidbits.Palette.blue) { showStoryArchive = true }
                        row("chart.xyaxis.line", "Knowledge Atlas", atlasSubtitle, Tidbits.Palette.mint) { showAtlas = true }
                        row("trophy.fill", "Marathon History", historySubtitle, Tidbits.Palette.yellow) { showMarathonHistory = true }
                    }
                }
                .padding(Tidbits.Metric.pad)
                .padding(.bottom, 32)
            }
            .background(Tidbits.Palette.bg)
            .navigationTitle("Tidbits Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(isPresented: $showExpeditions) { ExpeditionsView() }
        .sheet(isPresented: $showStoryArchive) { StoryArchiveView() }
        .sheet(isPresented: $showAtlas) { KnowledgeAtlasView() }
        .sheet(isPresented: $showMarathonHistory) { MarathonHistoryView() }
        .task {
            // The existing per-feature debug hooks still work, now landing inside the hub.
            if DebugHooks.openExpedition || DebugHooks.expeditionMapPreview != nil || DebugHooks.expeditionAutoplay != nil {
                showExpeditions = true
            }
            if DebugHooks.openStoryArchive { showStoryArchive = true }
            if DebugHooks.openAtlas { showAtlas = true }
        }
    }

    private var memberBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(Tidbits.Palette.mint)
            VStack(alignment: .leading, spacing: 1) {
                Text("You're a member").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Text("Everything below is yours. The rest of Tidbits stays free for everyone.")
                    .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .chunkyCard(fill: Tidbits.Palette.surface)
    }

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
            rows()
        }
    }

    private func row(_ icon: String, _ title: String, _ subtitle: String,
                     _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Text(subtitle).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .chunkyCard(fill: Tidbits.Palette.surface)
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

    /// Member copy, NOT `previewLine()`. Those lines are written to SELL ("… — Club turns
    /// misses like this into a round"), which is exactly wrong aimed at someone who already
    /// paid: inside the door, Club is just features.
    private var weakSpotSubtitle: String { "A round built entirely from the questions you've missed." }

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
        let n = StoryArchive.count(in: modelContext)
        return n == 0 ? "Every story you unlock, kept here forever."
                      : "\(n) stor\(n == 1 ? "y" : "ies") collected — searchable, forever."
    }

    private var atlasSubtitle: String { "What you actually know, by domain, over time." }

    private var historySubtitle: String {
        marathonHistory.isEmpty ? "Your finished runs, kept forever."
                                : "\(marathonHistory.count) run\(marathonHistory.count == 1 ? "" : "s") on record."
    }
}
#endif
