import Foundation
import SwiftData

/// Generates and tracks Club Expeditions — multi-week structured campaigns
/// through a single domain (docs/CLUB-FEATURES-BUILD.md "Feature 5"). NOT a
/// new game engine: every stage routes into the EXISTING `.classic` launch
/// path via a category + difficulty-band filtered question set drawn fresh
/// from the bundled corpus. Unlike Marathon's at-most-one run, several
/// expeditions may be in progress at once — each tracked by its own
/// `ExpeditionProgress` row, keyed by `expeditionID`.
@MainActor
enum Expeditions {

    /// Every catalog expedition, paired with its progress row if one exists.
    static func available(in context: ModelContext) -> [(expedition: Expedition, progress: ExpeditionProgress?)] {
        let rows = (try? context.fetch(FetchDescriptor<ExpeditionProgress>())) ?? []
        return Expedition.all.map { exp in (exp, rows.first { $0.expeditionID == exp.id }) }
    }

    static func progress(for expeditionID: String, in context: ModelContext) -> ExpeditionProgress? {
        let rows = (try? context.fetch(FetchDescriptor<ExpeditionProgress>())) ?? []
        return rows.first { $0.expeditionID == expeditionID }
    }

    /// Begin (or fetch the existing) progress row for an expedition — called
    /// lazily the first time a stage is recorded, so merely PREVIEWING the
    /// map (non-members included) never creates a row.
    @discardableResult
    static func startExpedition(_ expedition: Expedition, in context: ModelContext) -> ExpeditionProgress {
        if let existing = progress(for: expedition.id, in: context) { return existing }
        let p = ExpeditionProgress(expeditionID: expedition.id)
        context.insert(p)
        try? context.save()
        return p
    }

    /// The question set for one stage — a fresh, difficulty-banded pull from
    /// the bundled corpus each attempt (a stage is replayable on a miss, so
    /// there's no "seen" exclusion the way a normal round has). Never-empty:
    /// relaxes to the whole category pool if the difficulty band comes up thin.
    static func startStage(_ expedition: Expedition, stageIndex: Int) -> [Question] {
        guard let stage = expedition.stages.first(where: { $0.index == stageIndex }) else { return [] }
        let overfetch = max(stage.questionCount * 8, 80)
        let pool = CorpusDatabase.shared.questions(categoryID: stage.categoryID, excluding: [], limit: overfetch)
        var banded = pool.filter { stage.difficultyRange.contains($0.difficulty) }
        if banded.count < stage.questionCount { banded = pool }
        return Array(banded.shuffled().prefix(stage.questionCount))
    }

    /// A stage just finished — pass advances (and unlocks the next stage);
    /// the LAST stage passing writes the permanent certificate and clears the
    /// in-progress row (mirrors Marathon's finish). Fail leaves progress
    /// exactly where it was — the player stays on the same stage, "try again."
    @discardableResult
    static func recordStageResult(expedition: Expedition, stageIndex: Int, correct: Int, total: Int,
                                   in context: ModelContext) -> (passed: Bool, certificate: ExpeditionCertificate?) {
        guard let stage = expedition.stages.first(where: { $0.index == stageIndex }) else { return (false, nil) }
        let progress = startExpedition(expedition, in: context)
        let passed = correct >= stage.passBar
        progress.recordStage(ExpeditionStageResult(stageIndex: stageIndex, passed: passed, correct: correct, total: total))
        guard passed else { try? context.save(); return (false, nil) }
        guard stageIndex >= expedition.stages.count - 1 else { try? context.save(); return (true, nil) }
        // Final stage passed — write the certificate, retire the progress row.
        let totalScore = progress.perStageResults.reduce(0) { $0 + $1.correct }
        let cert = ExpeditionCertificate(expeditionID: expedition.id, domain: expedition.domain, title: expedition.title,
                                         totalScore: totalScore, stagesCompleted: expedition.stages.count)
        context.insert(cert)
        context.delete(progress)
        try? context.save()
        return (true, cert)
    }

    /// Every completed Expedition, most recent first — the permanent history
    /// (the Completed/certificates shelf).
    static func certificates(in context: ModelContext) -> [ExpeditionCertificate] {
        (try? context.fetch(FetchDescriptor<ExpeditionCertificate>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)]))) ?? []
    }
}
