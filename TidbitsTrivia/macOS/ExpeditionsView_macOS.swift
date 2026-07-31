#if os(macOS)
import SwiftUI
import SwiftData

/// Mac mirror of the Club Expeditions hub + map (docs/CLUB-FEATURES-BUILD.md
/// "Feature 5", canonical at `iOS/Views/ExpeditionsView.swift`) — reachable by
/// EVERYONE: the list and an expedition's map are a real preview (title,
/// stage path, first-stage description). Only actually PLAYING a stage is
/// Club-gated (MONETIZATION §4a: never a blank wall). Presented as a sized
/// sheet with a Done header (the `SheetChrome_macOS` idiom, see
/// `MarathonHistoryView_macOS`).
struct ExpeditionsHubView_macOS: View {
    /// Bubbles all the way up to `ContentView_macOS`, which swaps the window
    /// root into `GameContainerView_macOS` (Rule 4 — never an overlay).
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
        VStack(spacing: 0) {
            HStack {
                Text("Expeditions").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(CompactButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pick an expedition — a guided journey through a subject, one stage at a time, at your own pace.")
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.inkSoft)
                    ForEach(Expedition.all) { expedition in
                        Button { detail = expedition } label: {
                            ExpeditionRow_macOS(expedition: expedition, progress: progress(for: expedition),
                                                hasCertificate: hasCertificate(expedition))
                        }
                        .buttonStyle(.plain)
                    }
                    if !certificates.isEmpty { completedShelf }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 620)
        .background(Tidbits.Palette.bg)
        .sheet(item: $detail) { expedition in
            ExpeditionMapView_macOS(expedition: expedition, isClub: entitlement.isClub,
                                    progress: progress(for: expedition), hasCertificate: hasCertificate(expedition)) { stageIndex in
                playStage(expedition, stageIndex)
            }
            .frame(minWidth: 520, minHeight: 620)
        }
        .sheet(isPresented: $showClubPaywall) { ClubPaywallView_macOS() }
        .task {
            // Verification-only hooks (no GUI Simulator window to tap through
            // on this dev box) — no-ops unless the env var is set.
            if let id = DebugHooks.expeditionMapPreview, let exp = Expedition.named(id) { detail = exp }
            if let auto = DebugHooks.expeditionAutoplay, let exp = Expedition.named(auto.expeditionID) {
                playStage(exp, auto.stageIndex)
            }
        }
    }

    private var completedShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Completed").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            ForEach(certificates) { cert in
                HStack(spacing: 12) {
                    Image(systemName: "rosette").font(.system(size: 20, weight: .black)).foregroundStyle(Tidbits.Palette.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cert.title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Text("\(cert.stagesCompleted) stages · \(cert.totalScore) correct · \(cert.completedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14).chunkyCard()
            }
        }
    }
}

// MARK: - Expedition row (the list)

private struct ExpeditionRow_macOS: View {
    let expedition: Expedition
    let progress: ExpeditionProgress?
    let hasCertificate: Bool

    private var domainColor: Color { TriviaCategory.named(expedition.domain).color }
    private var subtitle: String {
        if let progress {
            return "Stage \(min(progress.currentStageIndex + 1, expedition.stageCount)) of \(expedition.stageCount) — click to continue"
        }
        if hasCertificate { return "Completed — click to play again" }
        return expedition.subtitle
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: expedition.symbol)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(domainColor.legibleForeground)
            VStack(alignment: .leading, spacing: 3) {
                Text(expedition.title.uppercased())
                    .font(Tidbits.TypeRamp.l3)
                    .foregroundStyle(domainColor.legibleForeground)
                Text(subtitle)
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(domainColor.legibleForeground.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right.circle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(domainColor.legibleForeground)
        }
        .padding(14)
        .chunkyCard(fill: domainColor)
    }
}

// MARK: - Expedition map (the stage path — a real preview even for non-members)

private struct ExpeditionMapView_macOS: View {
    let expedition: Expedition
    let isClub: Bool
    let progress: ExpeditionProgress?
    let hasCertificate: Bool
    let onPlayStage: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Which stage is next up. Defaults to 0 both for a never-started
    /// expedition AND right after a full completion (progress is cleared on
    /// certificate write) — either way stage 0 is the honest "start here."
    private var currentStageIndex: Int { progress?.currentStageIndex ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(expedition.title).font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(CompactButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(expedition.stages) { stage in
                            stageRow(stage)
                            if stage.index != expedition.stages.count - 1 {
                                Rectangle().fill(Tidbits.Palette.border).frame(width: 2, height: 14)
                                    .padding(.leading, 15)
                            }
                        }
                    }
                    if !isClub { paywallNote }
                }
                .padding(20)
            }
        }
        .background(Tidbits.Palette.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(expedition.subtitle)
                .font(Tidbits.TypeRamp.l4)
                .foregroundStyle(Tidbits.Palette.inkSoft)
            if hasCertificate && progress == nil {
                Label("Completed — play again for another certificate", systemImage: "rosette")
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(Tidbits.Palette.mint)
            } else {
                Text("\(expedition.stageCount) stages · pick up where you left off, any time")
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(Tidbits.Palette.inkSoft)
            }
        }
    }

    @ViewBuilder
    private func stageRow(_ stage: ExpeditionStage) -> some View {
        let done = stage.index < currentStageIndex
        let isCurrent = stage.index == currentStageIndex
        let locked = !done && !isCurrent

        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Tidbits.Palette.mint : (isCurrent ? Tidbits.Palette.pink : Tidbits.Palette.surface))
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .black)).foregroundStyle(.white)
                } else if locked {
                    Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Tidbits.Palette.inkSoft)
                } else {
                    Text("\(stage.index + 1)").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.pink.legibleForeground)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(stage.title)
                    .font(Tidbits.TypeRamp.l3)
                    .foregroundStyle(locked ? Tidbits.Palette.inkSoft : Tidbits.Palette.ink)
                Text(stage.blurb)
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(Tidbits.Palette.inkSoft)
                    .lineLimit(2)
                if isCurrent {
                    Button("Play") { onPlayStage(stage.index) }
                        .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.pink, textColor: .white, prominent: true))
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(locked ? 0.55 : 1)
        .padding(.vertical, 2)
    }

    private var paywallNote: some View {
        Text("Join Tidbits Club to play this expedition. Everything above is a preview — no charge to look around.")
            .font(Tidbits.TypeRamp.l5)
            .foregroundStyle(Tidbits.Palette.inkSoft)
    }
}
#endif
