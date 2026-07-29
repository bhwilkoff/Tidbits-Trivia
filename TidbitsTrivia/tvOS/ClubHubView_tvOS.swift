#if os(tvOS)
import SwiftUI
import SwiftData

/// The TV's one door to Tidbits Club (rule R-CLUB-1, iOS-DESIGN §5.2a — the rule is
/// cross-platform; only the idiom differs). Mirror of `ClubHubView`, ten-foot and
/// dark-first: `TVTheme`, focusable `TVAtlasCardStyle` rows, no text smaller than the 29pt
/// body floor.
///
/// Members only. Home routes non-members to `ClubPaywallView_tvOS`, so nothing here carries
/// a lock, a "CLUB" badge, or a price.
///
/// **Sub-surfaces swap this view's own content instead of stacking a nested
/// `.fullScreenCover`.** Modal-over-modal is the tvOS trap that produced the App Review
/// 2.1(a) purchase failure (StoreKit had to present third in the stack); the same discipline
/// applies here even where StoreKit isn't involved, so the stack is never more than one deep.
struct ClubHubView_tvOS: View {
    /// Home dismisses the hub, then starts the round / opens the board.
    var onStartWeakSpot: () -> Void
    var onStartMarathon: () -> Void
    var onOpenLinkWall: () -> Void
    var onPlayExpeditionStage: (Expedition, Int) -> Void
    /// The Atlas's per-domain rows are tap-to-play doors.
    var onPlay: (LaunchRequest) -> Void
    var onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var marathonRuns: [MarathonRun]
    @Query(sort: \MarathonScore.date, order: .reverse) private var marathonHistory: [MarathonScore]
    @Query private var expeditionProgress: [ExpeditionProgress]
    @Query(sort: \LinkWallResult.date, order: .reverse) private var linkWallResults: [LinkWallResult]
    @State private var open: Destination?
    @State private var restoreMessage: String?
    @FocusState private var focus: Int?

    private enum Destination: Hashable { case expeditions, storyArchive, atlas, marathonHistory }

    var body: some View {
        switch open {
        case .expeditions:
            TVExpeditionsHubView(onClose: { open = nil },
                                 onPlayStage: { exp, stage in open = nil; onPlayExpeditionStage(exp, stage) })
        case .storyArchive:
            StoryArchiveView_tvOS(onClose: { open = nil })
        case .atlas:
            KnowledgeAtlasView_tvOS(onClose: { open = nil }, onPlay: { req in open = nil; onPlay(req) })
        case .marathonHistory:
            TVMarathonHistoryView(onClose: { open = nil })
        case nil:
            hub
        }
    }

    private var hub: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    Text("TIDBITS CLUB")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(TVTheme.text)
                    memberBanner
                    sectionHeader("Play")
                    clubRow(0, "square.grid.3x3.fill", "Link Wall", linkWallSubtitle, Tidbits.Palette.mint, onOpenLinkWall)
                    clubRow(1, "target", "Weak-Spot Arena", weakSpotSubtitle, Tidbits.Palette.coral, onStartWeakSpot)
                    clubRow(2, "figure.run", "Marathon", marathonSubtitle, Tidbits.Palette.blue, onStartMarathon)
                    clubRow(3, "map.fill", "Expeditions", expeditionSubtitle, Tidbits.Palette.grape) { open = .expeditions }
                    sectionHeader("Your record")
                    clubRow(4, "books.vertical.fill", "Story Archive", storySubtitle, Tidbits.Palette.blue) { open = .storyArchive }
                    clubRow(5, "chart.xyaxis.line", "Knowledge Atlas", atlasSubtitle, Tidbits.Palette.mint) { open = .atlas }
                    clubRow(6, "trophy.fill", "Marathon History", historySubtitle, Tidbits.Palette.yellow) { open = .marathonHistory }
                    membershipFooter
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onExitCommand { onClose() }
        .defaultFocus($focus, 0)
    }

    private var memberBanner: some View {
        TVRecordsCard(dark: true) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44, weight: .black))
                    .foregroundStyle(Tidbits.Palette.mint)
                Text("You're a member").font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(TVTheme.text)
                Text("Everything below is yours. The rest of Tidbits stays free for everyone.")
                    .font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundStyle(TVTheme.textSoft)
    }

    private func clubRow(_ index: Int, _ icon: String, _ title: String, _ subtitle: String,
                         _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 28) {
                Image(systemName: icon).font(.system(size: 40, weight: .black)).foregroundStyle(tint).frame(width: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.text)
                    Text(subtitle).font(.system(size: 26, weight: .medium, design: .rounded))
                        .foregroundStyle(TVTheme.textSoft).fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 26, weight: .bold)).foregroundStyle(TVTheme.textSoft)
            }
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(TVClubRowStyle())
        .focused($focus, equals: index)
    }

    /// Members still need Restore Purchases (a new device, a reinstall) — it lived on the
    /// paywall, which members never see now. This is the only membership control here; the
    /// hub never quotes a price.
    private var membershipFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Membership")
            Button("Restore Purchases") {
                Task {
                    await StoreKitStore.shared.restore()
                    restoreMessage = "Your purchases are up to date."
                }
            }
            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
            .focused($focus, equals: 7)
            if let restoreMessage {
                Text(restoreMessage).font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(TVTheme.textSoft)
            }
        }
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

/// A quiet full-width row that only lights up when focused (tvOS-DESIGN: focus IS the
/// chrome; surrounding rows stay dark). Deliberately NOT `TVAtlasCardStyle` — that fills
/// solid teal, which on a list of eight rows makes every row shout at once and drops the
/// subtitle to unreadable grey-on-cyan.
private struct TVClubRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(focused ? TVTheme.panelFocused : TVTheme.panel))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 5))
                .scaleEffect(focused ? 1.02 : 1.0)
                .shadow(color: .black.opacity(focused ? 0.6 : 0), radius: 26, y: 12)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
    }
}
#endif
