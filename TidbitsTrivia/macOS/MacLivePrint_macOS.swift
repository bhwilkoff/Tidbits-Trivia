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
        render(QuestionPackPage(event: event), name: "\(event.name) — Question Pack")
    }
    @MainActor static func answerSheet(_ event: LiveEvent) {
        render(AnswerSheetPage(event: event), name: "\(event.name) — Answer Sheet")
    }
    @MainActor static func results(name: String, standings: [LiveTeam]) {
        render(ResultsPage(name: name, standings: standings), name: "\(name) — Results")
    }

    /// US Letter at 72dpi — the page a pub actually prints on.
    private static let pageSize = CGSize(width: 612, height: 792)

    /// Render a page view into a PAGINATED PDF.
    ///
    /// The first version called `beginPDFPage` exactly once with a media box the
    /// size of the whole rendered content, so a five-round question pack became a
    /// single 612 x 3000pt page: Preview showed one endless strip and printing it
    /// scaled the whole night down to fit one sheet. A host's printable fallback
    /// that cannot be printed is not a fallback.
    @MainActor static func makePDF<V: View>(_ page: V, to url: URL) throws -> Int {
        let renderer = ImageRenderer(content: page.frame(width: pageSize.width).background(.white))
        renderer.isOpaque = true
        var pages = 0
        var thrown: Error?
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: pageSize)
            guard let consumer = CGDataConsumer(url: url as CFURL),
                  let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else {
                thrown = PrintError.couldNotCreatePDF
                return
            }
            // Ceil, and always at least one page: a one-line event still prints.
            let count = max(1, Int((size.height / pageSize.height).rounded(.up)))
            for i in 0..<count {
                pdf.beginPDFPage(nil)
                pdf.saveGState()
                // Slide the content up by a page each time, so page i shows the
                // i-th slice instead of the whole thing squeezed onto one sheet.
                pdf.translateBy(x: 0, y: CGFloat(i + 1) * pageSize.height - size.height)
                draw(pdf)
                pdf.restoreGState()
                pdf.endPDFPage()
            }
            pdf.closePDF()
            pages = count
        }
        if let thrown { throw thrown }
        guard pages > 0 else { throw PrintError.nothingRendered }
        return pages
    }

    enum PrintError: LocalizedError {
        case couldNotCreatePDF
        case nothingRendered

        var errorDescription: String? {
            switch self {
            case .couldNotCreatePDF: return "Tidbits could not create the PDF."
            case .nothingRendered:   return "There was nothing to print."
            }
        }
    }

    /// Write to a file NAMED for the document, then open it. The name matters:
    /// the host is looking at this in Preview beside three other tabs, and
    /// "tidbits-live-a1b2c3d4.pdf" tells them nothing about which one it is.
    @MainActor private static func render(_ page: some View, name: String) {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe).pdf")
        do {
            _ = try makePDF(page, to: url)
            NSWorkspace.shared.open(url)
        } catch {
            // The old code was `guard let url else { return }` — a print button
            // that did nothing at all when rendering failed.
            let alert = NSAlert()
            alert.messageText = "Could not prepare “\(name)”"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

// MARK: - Pages (plain, print-friendly — black on white, no chunky chrome)

struct QuestionPackPage: View {
    let event: LiveEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event.name).font(.system(size: 26, weight: .bold))
            if !event.venue.isEmpty { Text(event.venue).font(.system(size: 14, weight: .semibold)) }
            Text("Host question pack · " + LiveBuilderView_macOS.summary(rounds: event.rounds.count, questions: event.totalQuestions))
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

struct ResultsPage: View {
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

struct AnswerSheetPage: View {
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
