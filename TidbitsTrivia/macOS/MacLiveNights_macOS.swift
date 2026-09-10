#if os(macOS)
import SwiftUI
import AppKit

/// macOS-DESIGN A2.12 — "Nights you've run". A night used to exist only while it
/// was happening: close the wrap and the standings, the answer sheet and the
/// A3.11 report were gone. A pub host runs the same room every week and is asked
/// "who won last time?", so every finished night is kept on this Mac (no backend,
/// nothing leaves the machine) and can be reopened, re-read and re-exported.
struct LiveNightsSheet_macOS: View {
    var onClose: () -> Void
    @State private var archive = LiveNightArchive.shared
    @State private var selected: String?
    @State private var confirmDelete: ArchivedNight?

    private var nights: [ArchivedNight] { archive.nights }
    private var current: ArchivedNight? { nights.first { $0.id == selected } ?? nights.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Nights you've run").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Done", action: onClose).buttonStyle(.borderedProminent).tint(Tidbits.Palette.coral).keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider().overlay(Tidbits.Palette.border)
            if nights.isEmpty { empty } else { content }
        }
        .frame(width: 860, height: 620)
        .background(Tidbits.Palette.bg)
        .alert("Delete this night?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), presenting: confirmDelete) { night in
            Button("Delete", role: .destructive) { archive.delete(night.id); selected = nil; confirmDelete = nil }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: { night in
            Text("“\(night.name)” and its answer sheet are removed from this Mac. The night itself is over; this only forgets it.")
        }
    }

    // universal-feature-states: a host who has never finished a night gets told what
    // fills this, not an empty panel.
    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 34)).foregroundStyle(Tidbits.Palette.inkSoft)
            Text("No nights yet").font(.title3.weight(.bold)).foregroundStyle(Tidbits.Palette.ink)
            Text("Run a night from the cockpit. When it ends, it is kept here with the final standings, how the night went, and the answer sheet.")
                .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        HStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(nights) { n in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(n.endedAt.formatted(.dateTime.weekday(.abbreviated).month().day()))
                            .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.coral)
                        Text(n.name).font(.headline).foregroundStyle(Tidbits.Palette.ink).lineLimit(2)
                        Text(n.headline).font(.caption).foregroundStyle(Tidbits.Palette.inkSoft).lineLimit(2)
                        if !n.venue.isEmpty {
                            Text(n.venue).font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(n.id)
                    .contextMenu { Button("Delete", role: .destructive) { confirmDelete = n } }
                }
            }
            .frame(width: 260)
            Divider().overlay(Tidbits.Palette.border)
            if let n = current { detail(n) } else { empty }
        }
    }

    @ViewBuilder private func detail(_ n: ArchivedNight) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.name).font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                    Text(n.endedAt.formatted(.dateTime.weekday().month().day().year().hour().minute())
                         + (n.venue.isEmpty ? "" : " · \(n.venue)"))
                        .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                if n.standings.isEmpty {
                    Text("No teams were scored this night.").font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Final standings").font(.headline).foregroundStyle(Tidbits.Palette.ink)
                        ForEach(Array(n.standings.enumerated()), id: \.offset) { i, row in
                            HStack(spacing: 10) {
                                Text("\(i + 1)").font(.system(size: 17, weight: .black, design: .rounded))
                                    .foregroundStyle(Tidbits.Palette.inkSoft).frame(width: 22)
                                if i == 0, row.score > 0 { Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow) }
                                Text(row.name).font(.body.weight(.semibold)).foregroundStyle(Tidbits.Palette.ink)
                                if row.paper { Text("paper").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft) }
                                Spacer()
                                Text("\(row.score)").font(.system(size: 19, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                            }
                            .padding(10)
                            .quietCard(fill: i == 0 && row.score > 0 ? Tidbits.Palette.yellow.opacity(0.3) : Tidbits.Palette.surface)
                        }
                    }
                }
                reportBlock(n.report)
                HStack(spacing: 12) {
                    Button("Print results") {
                        LivePrint.results(name: n.name,
                                          standings: n.standings.map { LiveTeam(name: $0.name, score: $0.score) },
                                          report: n.report)
                    }
                    .buttonStyle(.bordered)
                    Button("Export answer sheet…") { exportCSV(n) }
                        .buttonStyle(.bordered)
                        .disabled(n.log.isEmpty)
                        .accessibilityIdentifier("nights.exportAnswers")
                    Spacer()
                    Button("Delete", role: .destructive) { confirmDelete = n }.buttonStyle(.bordered)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The A3.11 report, recomputed from the archived sheet — an archived night and a
    /// live one can never disagree, because neither stores the numbers.
    @ViewBuilder private func reportBlock(_ r: LiveNightReport) -> some View {
        if !r.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("How the night went").font(.headline).foregroundStyle(Tidbits.Palette.ink)
                HStack(spacing: 10) {
                    stat(LiveNightReport.percent(r.overallAccuracy), "answers right", Tidbits.Palette.mint)
                    stat(LiveNightReport.percent(r.participation), "tables answering", Tidbits.Palette.blue)
                    stat("\(r.questions.count)", "questions", Tidbits.Palette.coral)
                }
                if let h = r.hardest { line("Hardest", h, Tidbits.Palette.coral) }
                if let e = r.easiest { line("Easiest", e, Tidbits.Palette.mint) }
            }
            .accessibilityIdentifier("nights.report")
        }
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(tint)
            Text(label).font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .padding(10).frame(maxWidth: .infinity).quietCard(fill: Tidbits.Palette.surface)
    }

    private func line(_ label: String, _ q: LiveNightReport.QuestionStat, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label.uppercased()) · \(LiveNightReport.percent(q.accuracy)) of \(q.answered) got it")
                .font(Tidbits.TypeRamp.l6).foregroundStyle(tint)
            Text(q.prompt).font(.callout).foregroundStyle(Tidbits.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(q.answer).font(.callout.weight(.semibold)).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).quietCard(fill: Tidbits.Palette.surface)
    }

    private func exportCSV(_ n: ArchivedNight) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(n.name) — answers.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(LiveAnswerLog.csv(n.log).utf8).write(to: url, options: .atomic) } catch {
            let alert = NSAlert()
            alert.messageText = "Could not save the answer sheet"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
#endif
