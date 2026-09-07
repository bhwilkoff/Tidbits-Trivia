#if os(macOS)
import Foundation

// MARK: - Text question formats: Moodle GIFT and Aiken (QUIZ-FORMATS-RESEARCH §1, §4)

/// GIFT and Aiken are the two human-writable formats a quiz-writer already has
/// in a text file. Both are read through the same Import button as CSV — the
/// text says which it is — and GIFT is the archive form Tidbits writes back,
/// because it carries every question type we have except ordering.
enum LiveTextFormats {
    enum Kind { case gift, aiken, csv }

    /// What a text file is, from its own shape. Aiken has `ANSWER:` lines under
    /// lettered options; GIFT has `{…}` answer blocks with `=`, `~`, `#` or T/F
    /// inside; anything else is treated as CSV.
    static func detect(_ text: String) -> Kind {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let answerLines = lines.filter { $0.uppercased().hasPrefix("ANSWER:") }.count
        let optionLines = lines.filter { $0.range(of: "^[A-Z][.)]\\s", options: .regularExpression) != nil }.count
        if answerLines > 0, optionLines >= 2 * answerLines { return .aiken }
        if text.range(of: "\\{[^{}]*[=~#][^{}]*\\}|\\{\\s*(T|F|TRUE|FALSE)\\s*\\}", options: .regularExpression) != nil { return .gift }
        return .csv
    }

    // MARK: Aiken

    static func parseAiken(_ text: String) -> [Question] {
        var out: [Question] = []
        for block in blocks(text) {
            var prompt: [String] = [], options: [String] = [], answer: String? = nil
            for raw in block {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.uppercased().hasPrefix("ANSWER:") {
                    answer = String(line.dropFirst("ANSWER:".count)).trimmingCharacters(in: .whitespaces).uppercased()
                } else if let r = line.range(of: "^[A-Z][.)]\\s+", options: .regularExpression) {
                    options.append(String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces))
                } else if options.isEmpty, !line.isEmpty {
                    prompt.append(line)
                }
            }
            let p = prompt.joined(separator: " ")
            guard !p.isEmpty, options.count >= 2, let a = answer, let letter = a.first,
                  let idx = "ABCDEFGHIJ".firstIndex(of: letter) else { continue }
            let ci = "ABCDEFGHIJ".distance(from: "ABCDEFGHIJ".startIndex, to: idx)
            guard options.indices.contains(ci) else { continue }
            out.append(make(prompt: p, options: options, correctIndex: ci, templateID: "aiken"))
        }
        return out
    }

    // MARK: GIFT

    static func parseGIFT(_ text: String) -> [Question] {
        var out: [Question] = []
        for block in blocks(text) {
            let joined = block.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            if let q = giftQuestion(joined) { out.append(q) }
        }
        return out
    }

    private static func giftQuestion(_ raw: String) -> Question? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var title: String? = nil
        if s.hasPrefix("::"), let end = s.range(of: "::", range: s.index(s.startIndex, offsetBy: 2)..<s.endIndex) {
            title = String(s[s.index(s.startIndex, offsetBy: 2)..<end.lowerBound])
            s = String(s[end.upperBound...])
        }
        s = s.replacingOccurrences(of: "^\\s*\\[(html|markdown|plain|moodle)\\]", with: "", options: .regularExpression)
        guard let open = unescapedIndex(of: "{", in: s), let close = unescapedIndex(of: "}", in: s, from: s.index(after: open)) else {
            return nil   // an essay/description block has no answers to play
        }
        let before = unescape(String(s[..<open])).trimmingCharacters(in: .whitespacesAndNewlines)
        let after = unescape(String(s[s.index(after: close)...])).trimmingCharacters(in: .whitespacesAndNewlines)
        var inner = String(s[s.index(after: open)..<close])
        var explanation = ""
        if let g = inner.range(of: "####") {
            explanation = unescape(String(inner[g.upperBound...])).trimmingCharacters(in: .whitespacesAndNewlines)
            inner = String(inner[..<g.lowerBound])
        }
        inner = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = before
        if !after.isEmpty { prompt = before + " ___ " + after }   // missing word
        if prompt.isEmpty { prompt = title ?? "" }
        guard !prompt.isEmpty else { return nil }
        let id = "gift-" + UUID().uuidString.prefix(8)

        // True/False
        let tf = inner.uppercased()
        if ["T", "TRUE", "F", "FALSE"].contains(tf) {
            let isTrue = tf.hasPrefix("T")
            return make(id: id, prompt: prompt, options: ["True", "False"], correctIndex: isTrue ? 0 : 1,
                        explanation: explanation, templateID: "gift")
        }
        // Numerical: {#42:2} or {#40..44} or {#=42:2 =...}
        if inner.hasPrefix("#") {
            let body = inner.dropFirst().trimmingCharacters(in: .whitespaces)
            let first = body.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }.first(where: { !$0.isEmpty }) ?? body
            let spec = first.split(separator: "#").first.map(String.init) ?? first   // strip per-answer feedback
            var answer = 0.0, tol = 0.0
            if let r = spec.range(of: "..") {
                let lo = Double(spec[..<r.lowerBound].trimmingCharacters(in: .whitespaces)) ?? 0
                let hi = Double(spec[r.upperBound...].trimmingCharacters(in: .whitespaces)) ?? lo
                answer = (lo + hi) / 2; tol = (hi - lo) / 2
            } else {
                let parts = spec.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                answer = Double(parts.first ?? "") ?? 0
                tol = parts.count > 1 ? (Double(parts[1]) ?? 0) : 0
            }
            let tolerance = max(tol, abs(answer) * 0.05, 1)
            let span = max(tolerance * 10, abs(answer) * 0.5, 10)
            let closest = ClosestSpec(answer: answer, min: (answer - span).rounded(.down), max: (answer + span).rounded(.up),
                                      step: max(1, (span / 50).rounded()), tolerance: tolerance, unit: "")
            return Question(id: id, prompt: prompt, options: [closest.formattedAnswer], correctIndex: 0, categoryID: "mixed",
                            difficulty: 3, explanation: explanation, sourceTitle: "", sourceURL: nil, templateID: "gift",
                            closest: closest)
        }
        // Answers: split on unescaped = and ~ at the top level.
        var answers: [(correct: Bool, text: String, weight: Int)] = []
        var cur = "", isCorrect = false, started = false
        var i = inner.startIndex
        while i < inner.endIndex {
            let ch = inner[i]
            if ch == "\\", inner.index(after: i) < inner.endIndex {
                cur.append(ch); cur.append(inner[inner.index(after: i)]); i = inner.index(i, offsetBy: 2); continue
            }
            if ch == "=" || ch == "~" {
                if started { answers.append((isCorrect, cur, 100)) }
                cur = ""; isCorrect = ch == "="; started = true
            } else if started { cur.append(ch) }
            i = inner.index(after: i)
        }
        if started { answers.append((isCorrect, cur, 100)) }
        var cleaned: [(correct: Bool, text: String, weight: Int)] = []
        for a in answers {
            var t = a.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var w = 100
            if let m = t.range(of: "^%-?\\d+%", options: .regularExpression) {
                w = Int(t[m].dropFirst().dropLast()) ?? 100; t = String(t[m.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            if let f = unescapedIndex(of: "#", in: t) { t = String(t[..<f]).trimmingCharacters(in: .whitespaces) }   // per-answer feedback
            t = unescape(t)
            if !t.isEmpty { cleaned.append((a.correct || w >= 100 && a.correct, t, w)) }
        }
        guard !cleaned.isEmpty else { return nil }
        // Matching: every answer is "key -> value".
        if cleaned.allSatisfy({ $0.text.contains("->") }), cleaned.count >= 2 {
            let pairs = cleaned.map { $0.text.components(separatedBy: "->").map { $0.trimmingCharacters(in: .whitespaces) } }
            let keys = pairs.map { $0.first ?? "" }, values = pairs.map { $0.count > 1 ? $0[1] : "" }
            return Question(id: id, prompt: prompt, options: keys, correctIndex: 0, categoryID: "mixed", difficulty: 3,
                            explanation: explanation, sourceTitle: "", sourceURL: nil, templateID: "gift",
                            matching: MatchSpec(keys: keys, values: values))
        }
        let corrects = cleaned.filter(\.correct)
        // Short answer: only correct answers listed → type-in with every one accepted.
        if cleaned.allSatisfy(\.correct), let first = corrects.first {
            return Question(id: id, prompt: prompt, options: [first.text], correctIndex: 0, categoryID: "mixed", difficulty: 3,
                            explanation: explanation, sourceTitle: "", sourceURL: nil, templateID: "gift",
                            accepted: corrects.map(\.text))
        }
        guard let best = corrects.max(by: { $0.weight < $1.weight }) else { return nil }
        let options = cleaned.map(\.text)
        return make(id: id, prompt: prompt, options: options, correctIndex: options.firstIndex(of: best.text) ?? 0,
                    explanation: explanation, templateID: "gift")
    }

    // MARK: GIFT export

    /// Every Tidbits type except ordering has a GIFT form; ordering is written as
    /// a short answer of the correct sequence so nothing is silently dropped.
    static func exportGIFT(_ questions: [Question]) -> String {
        var out = "// Tidbits Trivia — GIFT export\n\n"
        for q in questions {
            let feedback = q.explanation.isEmpty ? "" : "\n####" + esc(q.explanation)
            let body: String
            if let c = q.closest {
                body = "#\(c.formattedAnswer.split(separator: " ").first.map(String.init) ?? "\(c.answer)"):\(c.tolerance)"
            } else if let m = q.matching {
                body = zip(m.keys, m.values).map { "=\(esc($0)) -> \(esc($1))" }.joined(separator: " ")
            } else if let acc = q.accepted {
                body = acc.map { "=" + esc($0) }.joined(separator: " ")
            } else if let order = q.ordering {
                body = "=" + esc(order.joined(separator: ", "))
            } else if q.options.map({ $0.lowercased() }) == ["true", "false"] {
                body = q.correctIndex == 0 ? "T" : "F"
            } else {
                body = q.options.enumerated().map { i, o in (i == q.correctIndex ? "=" : "~") + esc(o) }.joined(separator: " ")
            }
            out += "::\(esc(q.id)):: \(esc(q.prompt)) {\(body)\(feedback)}\n\n"
        }
        return out
    }

    // MARK: Bits

    private static func blocks(_ text: String) -> [[String]] {
        var out: [[String]] = [], cur: [String] = []
        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !cur.isEmpty { out.append(cur); cur = [] }
            } else { cur.append(line) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    private static func unescapedIndex(of ch: Character, in s: String, from: String.Index? = nil) -> String.Index? {
        var i = from ?? s.startIndex
        while i < s.endIndex {
            if s[i] == "\\" { i = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex; continue }
            if s[i] == ch { return i }
            i = s.index(after: i)
        }
        return nil
    }

    private static func unescape(_ s: String) -> String {
        var out = "", i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\\", s.index(after: i) < s.endIndex { out.append(s[s.index(after: i)]); i = s.index(i, offsetBy: 2) }
            else { out.append(s[i]); i = s.index(after: i) }
        }
        return out.replacingOccurrences(of: "\\n", with: " ")
    }

    private static func esc(_ s: String) -> String {
        var t = s
        for c in ["\\", "{", "}", "=", "~", "#", ":"] { t = t.replacingOccurrences(of: c, with: "\\" + c) }
        return t.replacingOccurrences(of: "\n", with: " ")
    }

    private static func make(id: String = "text-" + UUID().uuidString.prefix(8), prompt: String, options: [String],
                             correctIndex: Int, explanation: String = "", templateID: String) -> Question {
        Question(id: String(id), prompt: prompt, options: options, correctIndex: correctIndex, categoryID: "mixed",
                 difficulty: 3, explanation: explanation, sourceTitle: "", sourceURL: nil, templateID: templateID)
    }
}

// MARK: - SpeedQuizzing "Quick Questions" folders (QUIZ-FORMATS-RESEARCH §1)

/// A SpeedQuizzing quizpack is a FOLDER of files whose NAMES are the questions
/// and whose CONTENTS are the media: `QQ_Who sang this^^_Dolly Parton.mp3` is a
/// name-that-tune question with the clip attached. This is the one importer
/// where the media IS the question, which is exactly what the `.tidbits`
/// package was built to carry.
///
/// The public documentation gives the separator (underscore), the `^^` → `?`
/// substitution, the leading order number (`05 QQ_…`) and the supported
/// extensions; the full help file ships inside the SpeedQuizzing app and is not
/// public. So this reads what is DOCUMENTED and refuses to guess the rest: an
/// unknown prefix is treated as a plain quick question, and no field is ever
/// promoted to a right answer it might not be.
enum LiveQuickQuestions {
    static let mediaExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "mp3", "wav", "m4a", "mp4", "mov"]

    struct Parsed {
        var prompt: String
        var answers: [String]      // the first is the one to beat; the rest are ALTERNATIVES
        var isPoll: Bool           // QQV — a vote, with no right answer
        var order: Int?            // a leading "05 " so a folder keeps its running order
    }

    /// Read one filename. Returns nil when it carries no question at all.
    static func parse(filename: String) -> Parsed? {
        var stem = (filename as NSString).deletingPathExtension
        var order: Int? = nil
        // A leading order number: "05 QQ_What is…"
        if let m = stem.range(of: "^\\s*(\\d{1,3})[\\s._-]+", options: .regularExpression) {
            order = Int(stem[m].trimmingCharacters(in: CharacterSet(charactersIn: " ._-")))
            stem = String(stem[m.upperBound...])
        }
        var fields = stem.components(separatedBy: "_").map {
            $0.replacingOccurrences(of: "^^", with: "?")
              .trimmingCharacters(in: .whitespaces)
        }
        var isPoll = false
        // A leading QQ… code names the KIND. QQV is a vote; the rest play as questions.
        if let first = fields.first, first.range(of: "^QQ[A-Z]{0,3}$", options: [.regularExpression, .caseInsensitive]) != nil {
            isPoll = first.uppercased().hasPrefix("QQV")
            fields.removeFirst()
        }
        fields.removeAll { $0.isEmpty }
        guard let prompt = fields.first, !prompt.isEmpty else { return nil }
        return Parsed(prompt: prompt, answers: Array(fields.dropFirst()), isPoll: isPoll, order: order)
    }

    /// Turn a picked folder's files into questions. `store` puts a media file in
    /// the media store and returns its id; the caller owns the sandbox scope.
    ///
    /// Every question is a TYPE-IN with each filename answer accepted. The
    /// documented format does not say whether the fields after the first are
    /// alternative spellings or distractors, and importing a distractor as a
    /// choice would be fine while importing one as ACCEPTED would mark a wrong
    /// player right — so they are accepted only as answers to a name-it, which is
    /// how a quizpack is hosted anyway. Notes say what was skipped.
    static func questions(from files: [URL], store: (URL) throws -> String?) -> (questions: [Question], notes: [String]) {
        var rows: [(order: Int, q: Question)] = []
        var notes: [String] = []
        var n = 0
        for url in files.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let name = url.lastPathComponent
            if name.hasPrefix(".") { continue }
            let ext = url.pathExtension.lowercased()
            guard ext == "txt" || mediaExtensions.contains(ext) else {
                notes.append("\(name): not a Quick Question file (.txt, picture, audio or video)")
                continue
            }
            guard let p = parse(filename: name) else {
                notes.append("\(name): no question in the filename")
                continue
            }
            if p.isPoll {
                notes.append("\(name): a voting question has no right answer — skipped")
                continue
            }
            guard let answer = p.answers.first else {
                notes.append("\(name): no answer after the question — skipped")
                continue
            }
            var mediaID: String? = nil
            if ext != "txt" {
                do { mediaID = try store(url) }
                catch { notes.append("\(name): could not read the media (\(error.localizedDescription))") }
            }
            n += 1
            var q = Question(id: "sq-\(UUID().uuidString.prefix(8))", prompt: p.prompt, options: [answer],
                             correctIndex: 0, categoryID: "mixed", difficulty: 3, explanation: "",
                             sourceTitle: "", sourceURL: nil, templateID: "speedquizzing",
                             accepted: p.answers)
            if let id = mediaID, ["jpg", "jpeg", "png", "gif"].contains(ext) {
                q.imageURL = LiveMediaStore.reference(id)
            }
            rows.append((p.order ?? n, q))
        }
        // A folder's own numbering wins; files without one keep their sorted place.
        return (rows.sorted { $0.order < $1.order }.map(\.q), notes)
    }

    /// The clip ids, index-parallel with `questions(from:store:)`'s output, for the
    /// audio/video files among them (LIVE-PACKAGE-FORMAT §3.2).
    static func clipIDs(from files: [URL], store: (URL) throws -> String?) -> [String?] {
        var out: [String?] = []
        for url in files.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let ext = url.pathExtension.lowercased()
            guard ext == "txt" || mediaExtensions.contains(ext), !url.lastPathComponent.hasPrefix("."),
                  let p = parse(filename: url.lastPathComponent), !p.isPoll, !p.answers.isEmpty else { continue }
            if ["mp3", "wav", "m4a", "mp4", "mov"].contains(ext) { out.append(try? store(url)) } else { out.append(nil) }
        }
        return out
    }
}
#endif
