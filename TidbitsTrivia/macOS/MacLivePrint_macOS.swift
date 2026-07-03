#if os(macOS)
import SwiftUI
import AppKit

/// Printable fallbacks for a live event (macOS-DESIGN §A5.2 — the Wi-Fi-dies
/// contingency the field ignores). Renders a SwiftUI page to a PDF and opens it
/// in Preview, where the host prints or saves. Two documents:
///   • Question pack — the host's copy (questions + answers).
///   • Answer sheet — the teams' blank sheet (numbered lines to write on).
enum LivePrint {
    @MainActor static func questionPack(_ event: LiveEvent) {
        open(makePDF(QuestionPackPage(event: event)), name: "\(event.name) — Question Pack")
    }
    @MainActor static func answerSheet(_ event: LiveEvent) {
        open(makePDF(AnswerSheetPage(event: event)), name: "\(event.name) — Answer Sheet")
    }
    @MainActor static func results(name: String, standings: [LiveTeam]) {
        open(makePDF(ResultsPage(name: name, standings: standings)), name: "\(name) — Results")
    }

    @MainActor private static func makePDF<V: View>(_ page: V) -> URL? {
        let renderer = ImageRenderer(content: page.frame(width: 612).background(.white))
        renderer.isOpaque = true
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidbits-live-\(UUID().uuidString.prefix(8)).pdf")
        var ok = false
        renderer.render { size, context in
            var box = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            guard let consumer = CGDataConsumer(url: url as CFURL),
                  let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok ? url : nil
    }

    private static func open(_ url: URL?, name: String) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Pages (plain, print-friendly — black on white, no chunky chrome)

private struct QuestionPackPage: View {
    let event: LiveEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event.name).font(.system(size: 26, weight: .bold))
            Text("Host question pack · \(event.rounds.count) rounds · \(event.totalQuestions) questions")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(Array(event.rounds.enumerated()), id: \.element.id) { ri, round in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Round \(ri + 1): \(round.title)").font(.system(size: 16, weight: .bold))
                    ForEach(Array(round.questions.enumerated()), id: \.element.id) { qi, q in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(qi + 1). \(q.prompt)").font(.system(size: 13))
                            Text("Answer: \(q.correctAnswer)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .foregroundStyle(.black)
        .padding(36)
    }
}

private struct ResultsPage: View {
    let name: String
    let standings: [LiveTeam]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name).font(.system(size: 26, weight: .bold))
            Text("Final standings").font(.system(size: 16, weight: .bold))
            ForEach(Array(standings.enumerated()), id: \.element.id) { i, team in
                HStack {
                    Text("\(i + 1). \(team.name)").font(.system(size: 14, weight: i == 0 ? .bold : .regular))
                    Spacer()
                    Text("\(team.score)").font(.system(size: 14, weight: .bold))
                }
            }
        }
        .foregroundStyle(.black)
        .padding(36)
    }
}

private struct AnswerSheetPage: View {
    let event: LiveEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event.name).font(.system(size: 26, weight: .bold))
            HStack { Text("Team name:").font(.system(size: 14, weight: .semibold)); Rectangle().frame(height: 1).foregroundStyle(.black) }
            ForEach(Array(event.rounds.enumerated()), id: \.element.id) { ri, round in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Round \(ri + 1): \(round.title)").font(.system(size: 16, weight: .bold))
                    ForEach(0..<round.questions.count, id: \.self) { qi in
                        HStack(spacing: 8) {
                            Text("\(qi + 1).").font(.system(size: 13, weight: .semibold)).frame(width: 24, alignment: .leading)
                            Rectangle().frame(height: 1).foregroundStyle(.black.opacity(0.4))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .foregroundStyle(.black)
        .padding(36)
    }
}
#endif
