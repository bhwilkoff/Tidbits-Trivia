#if os(tvOS)
import SwiftUI
import SwiftData

/// tvOS mirror of the Club Expeditions hub + map (docs/CLUB-FEATURES-BUILD.md
/// "Feature 5", canonical at `iOS/Views/ExpeditionsView.swift`) — ten-foot,
/// dark-first, reachable by EVERYONE: the list and an expedition's map are a
/// real preview. Only actually PLAYING the current stage is Club-gated
/// (never a blank wall — `ClubPaywallView_tvOS` as a `.fullScreenCover`).
struct TVExpeditionsHubView: View {
    /// Set when this view is shown INLINE by the Club hub (which swaps its own content
    /// rather than stacking a nested `.fullScreenCover` — see `ClubHubView_tvOS`). nil means
    /// "I'm a modal, dismiss me."
    var onClose: (() -> Void)? = nil

    /// Bubbles all the way up to `ContentView_tvOS`, which launches
    /// `TVGameContainer` via its own `.fullScreenCover(item:)`.
    let onPlayStage: (Expedition, Int) -> Void

    @Environment(EntitlementStore.self) private var entitlement
    @Environment(\.dismiss) private var dismiss
    @Query private var allProgress: [ExpeditionProgress]
    @Query(sort: \ExpeditionCertificate.completedAt, order: .reverse) private var certificates: [ExpeditionCertificate]
    @State private var detail: Expedition?
    @State private var showClubPaywall = false

    private func progress(for expedition: Expedition) -> ExpeditionProgress? {
        allProgress.first { $0.expeditionID == expedition.id }
    }
    private func hasCertificate(_ expedition: Expedition) -> Bool {
        certificates.contains { $0.expeditionID == expedition.id }
    }

    private func playStage(_ expedition: Expedition, _ stageIndex: Int) {
        if entitlement.isClub { onPlayStage(expedition, stageIndex) }
        else { showClubPaywall = true }
    }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Text("EXPEDITIONS")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(TVTheme.text)
                    Text("Pick an expedition — a guided journey through a subject, one stage at a time, at your own pace.")
                        .font(.system(size: 27, weight: .medium, design: .rounded))
                        .foregroundStyle(TVTheme.textSoft)
                    VStack(spacing: 20) {
                        ForEach(Expedition.all) { expedition in
                            Button { detail = expedition } label: {
                                row(expedition)
                            }
                            .buttonStyle(TVExpeditionRowStyle(accent: TriviaCategory.named(expedition.domain).color))
                        }
                    }
                    .focusSection()
                    if !certificates.isEmpty { completedShelf }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onExitCommand { if let onClose { onClose() } else { dismiss() } }
        .fullScreenCover(item: $detail) { expedition in
            TVExpeditionMapView(expedition: expedition, isClub: entitlement.isClub,
                                progress: progress(for: expedition), hasCertificate: hasCertificate(expedition)) { stageIndex in
                playStage(expedition, stageIndex)
            }
        }
        .fullScreenCover(isPresented: $showClubPaywall) { ClubPaywallView_tvOS() }
        .task {
            // Verification-only hooks (no GUI Simulator window to tap through
            // on this dev box) — no-ops unless the env var is set.
            if let id = DebugHooks.expeditionMapPreview, let exp = Expedition.named(id) { detail = exp }
            if let auto = DebugHooks.expeditionAutoplay, let exp = Expedition.named(auto.expeditionID) {
                playStage(exp, auto.stageIndex)
            }
        }
    }

    private func row(_ expedition: Expedition) -> some View {
        let progress = progress(for: expedition)
        let subtitle: String = {
            if let progress {
                return "Stage \(min(progress.currentStageIndex + 1, expedition.stageCount)) of \(expedition.stageCount) — press to continue"
            }
            if hasCertificate(expedition) { return "Completed — press to play again" }
            return expedition.subtitle
        }()
        return HStack(spacing: 24) {
            Image(systemName: expedition.symbol).font(.system(size: 44, weight: .black))
            VStack(alignment: .leading, spacing: 6) {
                Text(expedition.title.uppercased()).font(.system(size: 33, weight: .black, design: .rounded))
                Text(subtitle).font(.system(size: 24, weight: .medium, design: .rounded)).opacity(0.9).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32).padding(.vertical, 22)
        .frame(maxWidth: .infinity)
    }

    private var completedShelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("COMPLETED").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            VStack(spacing: 16) {
                ForEach(certificates) { cert in
                    HStack(spacing: 20) {
                        Image(systemName: "rosette").font(.system(size: 30, weight: .black)).foregroundStyle(Tidbits.Palette.pink)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cert.title).font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text("\(cert.stagesCompleted) stages · \(cert.totalScore) correct · \(cert.completedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 22, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 28).padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 18).fill(TVTheme.panel))
                }
            }
        }
    }
}

/// A full-width focusable row for one expedition (a custom style, never
/// `.buttonStyle(.plain)` — tvos-platform-patterns).
struct TVExpeditionRowStyle: ButtonStyle {
    let accent: Color
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration, accent: accent) }
    struct Inner: View {
        let configuration: Configuration; let accent: Color
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 24).fill(accent.gradient))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 5))
                .scaleEffect(focused ? 1.02 : 1.0)
                .shadow(color: accent.opacity(focused ? 0.5 : 0), radius: 24, y: 10)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
    }
}

// MARK: - Expedition map (the stage path — a real preview even for non-members)

private struct TVExpeditionMapView: View {
    let expedition: Expedition
    let isClub: Bool
    let progress: ExpeditionProgress?
    let hasCertificate: Bool
    let onPlayStage: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var playFocused: Bool

    /// Which stage is next up. Defaults to 0 both for a never-started
    /// expedition AND right after a full completion (progress is cleared on
    /// certificate write) — either way stage 0 is the honest "start here."
    private var currentStageIndex: Int { progress?.currentStageIndex ?? 0 }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text(expedition.title.uppercased())
                        .font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(TVTheme.text)
                    header
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(expedition.stages) { stage in
                            stageRow(stage)
                            if stage.index != expedition.stages.count - 1 {
                                Rectangle().fill(TVTheme.panel).frame(width: 4, height: 22).padding(.leading, 27)
                            }
                        }
                    }
                    .focusSection()
                    if !isClub { paywallNote }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .defaultFocus($playFocused, true)
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(expedition.subtitle)
                .font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            if hasCertificate && progress == nil {
                Label("Completed — play again for another certificate", systemImage: "rosette")
                    .font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Tidbits.Palette.mint)
            } else {
                Text("\(expedition.stageCount) stages · pick up where you left off, any time")
                    .font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
        }
    }

    @ViewBuilder
    private func stageRow(_ stage: ExpeditionStage) -> some View {
        let done = stage.index < currentStageIndex
        let isCurrent = stage.index == currentStageIndex
        let locked = !done && !isCurrent

        HStack(alignment: .top, spacing: 24) {
            ZStack {
                Circle()
                    .fill(done ? Tidbits.Palette.mint : (isCurrent ? Tidbits.Palette.pink : TVTheme.panel))
                    .frame(width: 56, height: 56)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                } else if locked {
                    Image(systemName: "lock.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(TVTheme.textSoft)
                } else {
                    Text("\(stage.index + 1)").font(.system(size: 25, weight: .black, design: .rounded)).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(stage.title)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(locked ? TVTheme.textSoft : .white)
                Text(stage.blurb)
                    .font(.system(size: 23, weight: .medium, design: .rounded))
                    .foregroundStyle(TVTheme.textSoft)
                    .lineLimit(2)
                if isCurrent {
                    Button("Play") { onPlayStage(stage.index) }
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.pink, selected: false))
                        .focused($playFocused)
                        .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(locked ? 0.5 : 1)
        .padding(.vertical, 6)
    }

    private var paywallNote: some View {
        Text("Join Tidbits Club to play this expedition. Everything above is a preview — no charge to look around.")
            .font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
    }
}
#endif
