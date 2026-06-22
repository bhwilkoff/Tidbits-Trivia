import Foundation
#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

/// On-device delightful question generation via Apple Intelligence's Foundation
/// Models framework. Grounded STRICTLY in each Wikipedia summary so the compact
/// on-device model can't invent facts — the same safeguard the build-time
/// corpus uses. Free, private, offline once the summary is fetched.
///
/// Compiles only where the framework exists (iOS/iPadOS 26 today; tvOS when a
/// future Apple TV ships Apple Intelligence — `canImport` picks it up
/// automatically) and runs only when the device actually supports it. Every
/// caller falls back to the bundled corpus + `TemplateEngine`, so the Create
/// feature works on every platform right now.
// NOTE: gated `&& !os(tvOS)` because the @Generable macros are currently
// unavailable in the tvOS SDK (no Apple Intelligence on Apple TV hardware yet).
// When a future Apple TV ships Apple Intelligence, delete `&& !os(tvOS)` from the
// guards below — no other change needed; the fallback runs on tvOS until then.
enum DelightfulQuizGenerator {

    /// Apple Intelligence present, enabled, and the model ready on this device.
    static var isAvailable: Bool {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Up to `count` delightful, grounded MCQs from Wikipedia summaries.
    /// Returns `[]` when unavailable so callers fall back to templates.
    static func generate(topic: String,
                         summaries: [WikipediaClient.Summary],
                         categoryID: String,
                         count: Int) async -> [Question] {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 26.0, macOS 26.0, *),
           case .available = SystemLanguageModel.default.availability {
            let usable = summaries.filter {
                ($0.extract?.count ?? 0) > 80 && $0.type != "disambiguation"
            }
            var out: [Question] = []
            let instructions = Instructions("""
            You are a witty trivia writer for a fun, learning-oriented game. Given a \
            Wikipedia summary, write ONE delightful, hooky multiple-choice question whose \
            answer is that article's subject. Lead with a surprising or charming detail. \
            Use ONLY facts stated in the summary — never invent anything. Never put the \
            subject's name (or any part of it) in the question. Give the correct answer \
            and three plausible wrong answers of the SAME kind as the answer.
            """)
            for s in usable {
                guard let extract = s.extract else { continue }
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let response = try await session.respond(
                        to: "Subject: \(s.title)\nSummary: \(extract)\n\nWrite the question now.",
                        generating: GeneratedQuestion.self)
                    if let q = question(from: response.content, summary: s, categoryID: categoryID) {
                        out.append(q)
                    }
                } catch {
                    continue   // skip this one; another summary or the fallback covers it
                }
                if out.count >= count { break }
            }
            return out
        }
        #endif
        return []
    }

    #if canImport(FoundationModels) && !os(tvOS)
    @available(iOS 26.0, macOS 26.0, *)
    private static func question(from g: GeneratedQuestion,
                                 summary s: WikipediaClient.Summary,
                                 categoryID: String) -> Question? {
        let ans = g.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = g.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ans.isEmpty, prompt.count > 12, !leaks(answer: ans, in: prompt) else { return nil }
        var opts = g.distractors.prefix(3).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        opts.append(ans)
        opts = Array(NSOrderedSet(array: opts.filter { !$0.isEmpty }).array as? [String] ?? [])
        guard opts.count == 4 else { return nil }
        opts.shuffle()
        let extract = s.extract ?? ""
        return Question(
            id: "ai:\(s.title.replacingOccurrences(of: " ", with: "_"))",
            prompt: prompt,
            options: opts,
            correctIndex: opts.firstIndex(of: ans) ?? 0,
            categoryID: categoryID,
            difficulty: 3,
            explanation: "\(ans): \(extract.prefix(180))",
            sourceTitle: s.title,
            sourceURL: URL(string: s.content_urls?.desktop?.page ?? ""),
            templateID: "ai")
    }
    #endif

    /// Reject a rewrite that names the answer (a significant word of it appears).
    private static func leaks(answer: String, in question: String) -> Bool {
        let q = question.lowercased()
        for w in answer.lowercased().split(whereSeparator: { !$0.isLetter }) where w.count >= 4 {
            if q.contains(w) { return true }
        }
        return false
    }
}

#if canImport(FoundationModels) && !os(tvOS)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedQuestion {
    @Guide(description: "A delightful, hooky trivia question that does NOT contain the answer or any part of its name")
    var question: String
    @Guide(description: "The correct answer — the article's subject")
    var answer: String
    @Guide(description: "Exactly three plausible wrong answers, each the same kind of thing as the answer")
    var distractors: [String]
}
#endif
