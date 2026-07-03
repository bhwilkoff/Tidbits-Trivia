#if os(macOS)
import SwiftUI

/// Mac Create (macOS-DESIGN Part B). "Make a quiz on the fly" — type any
/// Wikipedia topic; the shared template/corpus engine turns it into a playable
/// round. Same generation path as iOS (corpus MCQ + a couple of topic-matched
/// shapes, live Wikipedia only when the corpus is thin); only the presentation
/// is Mac-native.
struct CreateView_macOS: View {
    let onPlayCustom: (String, [Question]) -> Void

    @State private var topic = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var stageIndex = 0
    @FocusState private var topicFocused: Bool

    private let suggestions = ["Space exploration", "Ancient Rome", "Jazz", "Volcanoes", "The Olympics", "Marie Curie"]
    private let stages = ["Searching Wikipedia…", "Pulling out the facts…",
                          "Writing your questions…", "Double-checking the answers…"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pick any subject. We'll pull it straight from Wikipedia and build you a quiz.")
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                inputCard
                if let error { errorBanner(error) }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Need a spark?").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(suggestions, id: \.self) { s in
                            Button { topic = s; generate() } label: {
                                Text(s).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Capsule().fill(Tidbits.Palette.surface))
                                    .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Tidbits.Palette.bg)
        .navigationTitle("Create")
        .task {
            if let t = DebugHooks.autoCreate, topic.isEmpty { topic = t; generate() }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("e.g. The Renaissance", text: $topic)
                .textFieldStyle(.plain).font(Tidbits.TypeRamp.l3)
                .focused($topicFocused).onSubmit(generate)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Tidbits.Palette.bg))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            if isWorking {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView().progressViewStyle(.linear).tint(Tidbits.Palette.grape)
                    Text(stages[stageIndex]).font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.inkSoft).contentTransition(.opacity)
                }
            } else {
                Button("Generate Quiz", action: generate)
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.grape, textColor: .white))
                    .disabled(topic.trimmingCharacters(in: .whitespaces).count < 2)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).chunkyCard()
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).chunkyCard(fill: Tidbits.Palette.coral.opacity(0.25))
    }

    private func generate() {
        let q = topic.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, !isWorking else { return }
        topic = q; error = nil; topicFocused = false; stageIndex = 0; isWorking = true
        Task {
            var i = 0
            while isWorking {
                try? await Task.sleep(for: .seconds(0.9))
                i += 1
                withAnimation { stageIndex = min(i, stages.count - 1) }
            }
        }
        Task {
            var shaped: [Question] = []
            for src in [JSONQuestionSource.picture, .thisOrThat, .closestCall] {
                shaped.append(contentsOf: src.searchMatch(topic: q, limit: 1))
            }
            var mcq = CorpusDatabase.shared.search(topic: q, limit: max(4, 8 - shaped.count))
            if mcq.count < 3 {
                let gen = await QuestionProvider.shared.liveQuestions(topic: q, category: .named("mixed"), count: 8)
                if gen.count >= 3 { mcq = gen; shaped = [] }
            }
            let result = Array((mcq + shaped).shuffled().prefix(8))
            isWorking = false
            if result.count >= 3 {
                onPlayCustom(q, result)
            } else {
                error = "Couldn't build a good quiz for \u{201C}\(q)\u{201D}. Try a broader or more famous subject."
            }
        }
    }
}
#endif
