#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The question editor (macOS-DESIGN §A2.4)

/// A mutable working copy of a `Question`. `Question`'s stored properties are
/// `let` (it is a value produced by the template engine and handed to the game
/// loop), so hand-authoring needs a draft type that can round-trip to and from
/// it. Everything the host can legitimately change lives here; `id`,
/// `sourceTitle`/`sourceURL` and `templateID` are carried through untouched so
/// an edited corpus question still points at its provenance.
struct QuestionDraft {
    var id: String
    var prompt: String
    var options: [String]        // always exactly 4 slots in the editor
    var correctIndex: Int
    var categoryID: String
    var difficulty: Int
    var explanation: String
    var acceptedText: String     // newline-separated free-text answers
    var imageURLText: String
    var orderingText: String     // newline-separated, in CORRECT order
    var matchKeysText: String    // newline-separated; paired line-by-line with values
    var matchValuesText: String
    var enumGroupsText: String   // one group per line, aliases comma-separated
    var closestEnabled: Bool
    var closestAnswer: Double
    var closestMin: Double
    var closestMax: Double
    var closestStep: Double
    var closestTolerance: Double
    var closestUnit: String
    // Carried through, never edited here.
    let sourceTitle: String
    let sourceURL: URL?
    let templateID: String
    var tags: [String]
    var roundIndex: Int?

    init(_ q: Question) {
        id = q.id
        prompt = q.prompt
        var o = q.options
        while o.count < 4 { o.append("") }
        options = Array(o.prefix(4))
        correctIndex = min(max(0, q.correctIndex), 3)
        categoryID = q.categoryID
        difficulty = min(5, max(1, q.difficulty))
        explanation = q.explanation
        acceptedText = (q.accepted ?? []).joined(separator: "\n")
        imageURLText = q.imageURL?.absoluteString ?? ""
        orderingText = (q.ordering ?? []).joined(separator: "\n")
        matchKeysText = (q.matching?.keys ?? []).joined(separator: "\n")
        matchValuesText = (q.matching?.values ?? []).joined(separator: "\n")
        enumGroupsText = (q.enumerate?.groups ?? []).map { $0.joined(separator: ", ") }.joined(separator: "\n")
        closestEnabled = q.closest != nil
        closestAnswer = q.closest?.answer ?? 0
        closestMin = q.closest?.min ?? 0
        closestMax = q.closest?.max ?? 100
        closestStep = q.closest?.step ?? 1
        closestTolerance = q.closest?.tolerance ?? 10
        closestUnit = q.closest?.unit ?? ""
        sourceTitle = q.sourceTitle
        sourceURL = q.sourceURL
        templateID = q.templateID
        tags = q.tags
        roundIndex = q.roundIndex
    }

    /// A blank hand-authored question for a round of `format` in `categoryID`.
    static func blank(format: GameMode, categoryID: String) -> QuestionDraft {
        var d = QuestionDraft(Question(id: UUID().uuidString, prompt: "", options: ["", "", "", ""],
                                       correctIndex: 0, categoryID: categoryID, difficulty: 3,
                                       explanation: "", sourceTitle: "", sourceURL: nil,
                                       templateID: "hand"))
        if format == .closestCall { d.closestEnabled = true }
        return d
    }

    private static func lines(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The problems that would make this question unplayable, in the host's words.
    /// Shown live in the editor; Save is blocked while any remain.
    func problems(for format: GameMode) -> [String] {
        var out: [String] = []
        if prompt.trimmingCharacters(in: .whitespaces).isEmpty { out.append("The question needs a prompt.") }
        switch format {
        case .typeAnswer:
            if Self.lines(acceptedText).isEmpty && options[correctIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                out.append("A type-the-answer question needs at least one accepted answer.")
            }
        case .closestCall:
            if !closestEnabled { out.append("A Closest Call question needs a numeric answer.") }
            else if closestMin >= closestMax { out.append("The range low must be below the range high.") }
            else if closestAnswer < closestMin || closestAnswer > closestMax { out.append("The answer sits outside the range.") }
            else if closestTolerance <= 0 { out.append("Tolerance must be above zero.") }
        case .ordering:
            if Self.lines(orderingText).count < 3 { out.append("An ordering question needs at least 3 items.") }
        case .matching:
            let k = Self.lines(matchKeysText), v = Self.lines(matchValuesText)
            if k.count < 2 { out.append("A matching question needs at least 2 pairs.") }
            else if k.count != v.count { out.append("Matching has \(k.count) keys but \(v.count) values — they must pair up.") }
        case .enumerate:
            if Self.lines(enumGroupsText).count < 2 { out.append("An enumeration question needs at least 2 answers.") }
        default:
            let filled = options.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if filled.count < 2 { out.append("Give the question at least two answer choices.") }
            if options[correctIndex].trimmingCharacters(in: .whitespaces).isEmpty { out.append("Pick which choice is correct.") }
            if Set(filled.map { $0.lowercased() }).count != filled.count { out.append("Two choices are identical — a player could be right and marked wrong.") }
        }
        if !imageURLText.isEmpty && URL(string: imageURLText) == nil { out.append("That image URL is not a valid URL.") }
        return out
    }

    func build() -> Question {
        var opts = options.map { $0.trimmingCharacters(in: .whitespaces) }
        // A blank slot would render as an empty tappable choice; collapse them,
        // keeping the correct answer's index pointing at the same string.
        let correct = opts.indices.contains(correctIndex) ? opts[correctIndex] : ""
        opts = opts.filter { !$0.isEmpty }
        if opts.isEmpty { opts = [correct.isEmpty ? "—" : correct] }
        let ci = opts.firstIndex(of: correct) ?? 0
        let accepted = Self.lines(acceptedText)
        let ordering = Self.lines(orderingText)
        let mk = Self.lines(matchKeysText), mv = Self.lines(matchValuesText)
        let groups = Self.lines(enumGroupsText).map { line in
            line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }.filter { !$0.isEmpty }
        var q = Question(id: id, prompt: prompt.trimmingCharacters(in: .whitespaces), options: opts,
                         correctIndex: ci, categoryID: categoryID, difficulty: difficulty,
                         explanation: explanation.trimmingCharacters(in: .whitespaces),
                         sourceTitle: sourceTitle, sourceURL: sourceURL, templateID: templateID,
                         tags: tags,
                         imageURL: imageURLText.isEmpty ? nil : URL(string: imageURLText),
                         closest: closestEnabled ? ClosestSpec(answer: closestAnswer, min: closestMin,
                                                               max: closestMax, step: closestStep,
                                                               tolerance: closestTolerance, unit: closestUnit) : nil,
                         ordering: ordering.isEmpty ? nil : ordering,
                         matching: (mk.count >= 2 && mk.count == mv.count) ? MatchSpec(keys: mk, values: mv) : nil,
                         accepted: accepted.isEmpty ? nil : accepted,
                         enumerate: groups.count >= 2 ? EnumSpec(groups: groups) : nil)
        q.roundIndex = roundIndex
        return q
    }
}

/// The editor sheet. Native Mac work surface (§5.6): a grouped `Form`, stock
/// controls, Cancel/Save in the footer with Return bound to Save.
struct LiveQuestionEditor_macOS: View {
    let format: GameMode
    let onSave: (Question) -> Void
    let onCancel: () -> Void

    @State private var draft: QuestionDraft
    @FocusState private var promptFocused: Bool

    init(question: Question, format: GameMode, onSave: @escaping (Question) -> Void, onCancel: @escaping () -> Void) {
        self.format = format
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: QuestionDraft(question))
    }
    init(draft: QuestionDraft, format: GameMode, onSave: @escaping (Question) -> Void, onCancel: @escaping () -> Void) {
        self.format = format
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: draft)
    }

    private var problems: [String] { draft.problems(for: format) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Question") {
                    TextField("What is the question?", text: $draft.prompt, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($promptFocused)
                    HStack {
                        Picker("Category", selection: $draft.categoryID) {
                            ForEach(TriviaCategory.all) { Text($0.name).tag($0.id) }
                        }
                        Picker("Difficulty", selection: $draft.difficulty) {
                            Text("1 · Easy").tag(1)
                            Text("2").tag(2)
                            Text("3 · Medium").tag(3)
                            Text("4").tag(4)
                            Text("5 · Hard").tag(5)
                        }
                    }
                }

                payloadSection

                Section("Reveal") {
                    TextField("Explanation read out after the answer (optional)",
                              text: $draft.explanation, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("Picture URL (optional)", text: $draft.imageURLText)
                    if !draft.sourceTitle.isEmpty {
                        LabeledContent("Source", value: draft.sourceTitle)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack(spacing: 10) {
                if let first = problems.first {
                    Label(first, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                        .lineLimit(2)
                }
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft.build()) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!problems.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 620, height: 560)
        .onAppear { promptFocused = draft.prompt.isEmpty }
    }

    /// The format-specific answer payload. One question shape per format — the
    /// host never sees fields that cannot apply to the round they are editing.
    @ViewBuilder private var payloadSection: some View {
        switch format {
        case .closestCall:
            Section("Closest Call") {
                TextField("Answer", value: $draft.closestAnswer, format: .number)
                TextField("Unit (optional — “km”, “years”)", text: $draft.closestUnit)
                HStack {
                    TextField("Range low", value: $draft.closestMin, format: .number)
                    TextField("Range high", value: $draft.closestMax, format: .number)
                }
                HStack {
                    TextField("Slider step", value: $draft.closestStep, format: .number)
                    TextField("Tolerance", value: $draft.closestTolerance, format: .number)
                }
                Text("A guess inside the tolerance scores; dead-on scores full marks. Half the tolerance counts as “close enough” for streaks.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .onAppear { draft.closestEnabled = true }
        case .ordering:
            Section("Items, in the CORRECT order") {
                TextEditor(text: $draft.orderingText).frame(minHeight: 130).font(.body)
                Text("One item per line. The room sees them shuffled.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .matching:
            Section("Pairs") {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading) {
                        Text("Keys").font(.callout).foregroundStyle(.secondary)
                        TextEditor(text: $draft.matchKeysText).frame(minHeight: 120).font(.body)
                    }
                    VStack(alignment: .leading) {
                        Text("Matches").font(.callout).foregroundStyle(.secondary)
                        TextEditor(text: $draft.matchValuesText).frame(minHeight: 120).font(.body)
                    }
                }
                Text("Line 1 pairs with line 1, line 2 with line 2, and so on.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .enumerate:
            Section("Accepted answers") {
                TextEditor(text: $draft.enumGroupsText).frame(minHeight: 140).font(.body)
                Text("One answer per line. Put aliases on the same line, comma-separated — “Missouri, MO” fills one slot either way.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .typeAnswer:
            Section("Accepted answers") {
                TextEditor(text: $draft.acceptedText).frame(minHeight: 110).font(.body)
                Text("One per line. Spelling leniency is applied on top; the host can still mark any answer correct live.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        default:
            Section("Choices") {
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 10) {
                        Toggle(isOn: Binding(get: { draft.correctIndex == i },
                                             set: { if $0 { draft.correctIndex = i } })) {
                            Text("Correct").labelsHidden()
                        }
                        .toggleStyle(.radioGroupItemFallback)
                        .help("Mark this as the correct answer")
                        TextField("Choice \(i + 1)", text: $draft.options[i])
                    }
                }
                Text("Leave a choice blank to drop it — a True/False question is just two.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// SwiftUI has no single-radio toggle style on macOS; a checkbox in a group where
/// only one can be on reads correctly and keeps the native control.
extension ToggleStyle where Self == CheckboxToggleStyle {
    static var radioGroupItemFallback: CheckboxToggleStyle { .checkbox }
}

extension Question {
    /// A copy with a fresh id, so duplicating a question inside a round does not
    /// produce two rows SwiftUI cannot tell apart (`ForEach(id: \.element.id)`).
    func duplicatedForEditing() -> Question {
        var d = QuestionDraft(self)
        d.id = UUID().uuidString
        return d.build()
    }
}
#endif
