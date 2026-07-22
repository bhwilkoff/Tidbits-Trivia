#if os(iOS)
import SwiftUI
import SwiftData

/// The Club Expeditions destination (docs/CLUB-FEATURES-BUILD.md "Feature 5")
/// — reachable by EVERYONE: the list and an expedition's map are a real
/// preview (title, stage path, first-stage description). Only actually
/// PLAYING a stage is Club-gated (MONETIZATION §4a: never a blank wall).
struct ExpeditionsView: View {
    @Environment(EntitlementStore.self) private var entitlement
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allProgress: [ExpeditionProgress]
    @Query(sort: \ExpeditionCertificate.completedAt, order: .reverse) private var certificates: [ExpeditionCertificate]

    @State private var detail: Expedition?
    @State private var showClubPaywall = false
    @State private var stageLaunch: ExpeditionStageLaunch?

    private func progress(for expedition: Expedition) -> ExpeditionProgress? {
        allProgress.first { $0.expeditionID == expedition.id }
    }
    private func hasCertificate(_ expedition: Expedition) -> Bool {
        certificates.contains { $0.expeditionID == expedition.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pick an expedition — a guided journey through a subject, one stage at a time, at your own pace.")
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.inkSoft)
                    ForEach(Expedition.all) { expedition in
                        Button { detail = expedition } label: {
                            ExpeditionRow(expedition: expedition, progress: progress(for: expedition),
                                          hasCertificate: hasCertificate(expedition))
                        }
                        .buttonStyle(.plain)
                    }
                    if !certificates.isEmpty { completedShelf }
                }
                .padding(Tidbits.Metric.pad)
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationTitle("Expeditions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: $detail) { expedition in
                ExpeditionMapView(expedition: expedition, isClub: entitlement.isClub,
                                  progress: progress(for: expedition), hasCertificate: hasCertificate(expedition)) { stageIndex in
                    if entitlement.isClub {
                        stageLaunch = ExpeditionStageLaunch(expedition: expedition, stageIndex: stageIndex)
                    } else {
                        showClubPaywall = true
                    }
                }
            }
            .sheet(isPresented: $showClubPaywall) { ClubPaywallView() }
            .fullScreenCover(item: $stageLaunch) { launch in
                GameContainerView(mode: .classic, category: .named(launch.stage.categoryID),
                                   expedition: launch.expedition, expeditionStageIndex: launch.stageIndex)
            }
        }
        .presentationDetents([.large])
        .task {
            // Verification-only hooks (no GUI Simulator window to tap through
            // on this dev box) — no-ops unless the env var is set.
            if let id = DebugHooks.expeditionMapPreview, let exp = Expedition.named(id) { detail = exp }
            if let auto = DebugHooks.expeditionAutoplay, let exp = Expedition.named(auto.expeditionID) {
                if entitlement.isClub { stageLaunch = ExpeditionStageLaunch(expedition: exp, stageIndex: auto.stageIndex) }
                else { showClubPaywall = true }
            }
        }
    }

    private var completedShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Completed").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            ForEach(certificates) { cert in
                HStack(spacing: 12) {
                    Image(systemName: "rosette").font(.system(size: 22, weight: .black)).foregroundStyle(Tidbits.Palette.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cert.title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Text("\(cert.stagesCompleted) stages · \(cert.totalScore) correct · \(cert.completedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .chunkyCard()
                .padding(.trailing, Tidbits.Metric.shadowOffset)
            }
        }
    }
}

/// Resolved once a member taps "Play" on the current stage — drives the
/// `fullScreenCover` into the shared game engine.
private struct ExpeditionStageLaunch: Identifiable {
    let expedition: Expedition
    let stageIndex: Int
    var id: String { "\(expedition.id)-\(stageIndex)" }
    var stage: ExpeditionStage { expedition.stages.first { $0.index == stageIndex }! }
}

// MARK: - Expedition row (the list)

private struct ExpeditionRow: View {
    let expedition: Expedition
    let progress: ExpeditionProgress?
    let hasCertificate: Bool

    private var domainColor: Color { TriviaCategory.named(expedition.domain).color }
    private var subtitle: String {
        if let progress {
            return "Stage \(min(progress.currentStageIndex + 1, expedition.stageCount)) of \(expedition.stageCount) — tap to continue"
        }
        if hasCertificate { return "Completed — tap to play again" }
        return expedition.subtitle
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: expedition.symbol)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(domainColor.legibleForeground)
            VStack(alignment: .leading, spacing: 3) {
                Text(expedition.title.uppercased())
                    .font(Tidbits.TypeRamp.l2)
                    .foregroundStyle(domainColor.legibleForeground)
                Text(subtitle)
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(domainColor.legibleForeground.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right.circle.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(domainColor.legibleForeground)
        }
        .padding(16)
        .chunkyCard(fill: domainColor)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }
}

// MARK: - Expedition map (the stage path — a real preview even for non-members)

private struct ExpeditionMapView: View {
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(expedition.stages) { stage in
                            stageRow(stage)
                            if stage.index != expedition.stages.count - 1 {
                                Rectangle().fill(Tidbits.Palette.border).frame(width: 2, height: 14)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    if !isClub { paywallNote }
                }
                .padding(Tidbits.Metric.pad)
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationTitle(expedition.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
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
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .black)).foregroundStyle(.white)
                } else if locked {
                    Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Tidbits.Palette.inkSoft)
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
                        .buttonStyle(.borderedProminent)
                        .tint(Tidbits.Palette.pink)
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

// MARK: - Expedition stage result (the post-play beat — pass unlocks, fail retries)

struct ExpeditionStageResultView: View {
    let expedition: Expedition
    let stage: ExpeditionStage
    let summary: GameSummary
    /// Set once `GameContainerView.finishExpeditionStage` records the true
    /// outcome; nil for the first render (the fallback below reads straight
    /// off `summary`, which is already final by `.finished`).
    let outcome: (passed: Bool, certificate: ExpeditionCertificate?)?
    let onRetry: () -> Void
    let onDone: () -> Void

    private var passed: Bool { outcome?.passed ?? (summary.correct >= stage.passBar) }
    private var certificate: ExpeditionCertificate? { outcome?.certificate }
    private var nextStageNumber: Int { min(stage.index + 2, expedition.stageCount) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headline
                statsRow
                if let certificate { certificateCard(certificate) }
                buttons
            }
            .padding(.horizontal, Tidbits.Metric.pad)
            .padding(.vertical, 24)
        }
        .background(Tidbits.Palette.bg.ignoresSafeArea())
    }

    private var headline: some View {
        VStack(spacing: 8) {
            Image(systemName: certificate != nil ? "rosette" : (passed ? "checkmark.seal.fill" : "arrow.counterclockwise.circle.fill"))
                .font(.system(size: 48))
                .foregroundStyle(passed ? Tidbits.Palette.mint : Tidbits.Palette.coral)
            Text(certificate != nil ? "EXPEDITION COMPLETE" : (passed ? "STAGE \(stage.index + 1) PASSED" : "NOT QUITE"))
                .font(Tidbits.TypeRamp.l1)
                .foregroundStyle(Tidbits.Palette.ink)
            Text(bodyLine)
                .font(Tidbits.TypeRamp.l4)
                .foregroundStyle(Tidbits.Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .chunkyCard(fill: (passed ? Tidbits.Palette.mint : Tidbits.Palette.coral).opacity(0.16))
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var bodyLine: String {
        if certificate != nil { return "You completed \(expedition.title) — every stage, start to finish." }
        if passed { return "\(stage.title) is done. Stage \(nextStageNumber) just unlocked." }
        return "Needed \(stage.passBar) of \(stage.questionCount) to advance — you got \(summary.correct). Give it another go."
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatBox(value: "\(summary.correct)/\(summary.total)", label: "Correct", tint: Tidbits.Palette.blue)
            StatBox(value: "\(stage.passBar)", label: "Pass bar", tint: Tidbits.Palette.pink)
            StatBox(value: "\(min(stage.index + (passed ? 2 : 1), expedition.stageCount))/\(expedition.stageCount)",
                    label: "Stage", tint: Tidbits.Palette.ink)
        }
    }

    private func certificateCard(_ cert: ExpeditionCertificate) -> some View {
        VStack(spacing: 6) {
            Text("CERTIFICATE EARNED").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text(cert.title).font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Text("\(cert.stagesCompleted) stages · \(cert.totalScore) correct total")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .chunkyCard(fill: Tidbits.Palette.pink)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            if passed {
                Button(certificate != nil ? "Done" : "Continue", action: onDone)
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.pink, textColor: .white))
            } else {
                Button("Try Again", action: onRetry)
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
                Button("Back to map", action: onDone)
                    .font(Tidbits.TypeRamp.l3)
                    .foregroundStyle(Tidbits.Palette.inkSoft)
                    .padding(.top, 2)
            }
        }
        .padding(.trailing, Tidbits.Metric.shadowOffset)
        .padding(.top, 4)
    }
}
#endif
