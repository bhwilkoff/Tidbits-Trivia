#if os(macOS)
import SwiftUI
import SwiftData

/// Mac mirror of the Club Marathon history (docs/CLUB-FEATURES-BUILD.md
/// "Feature 3", canonical at `iOS/Views/MarathonResultsView.swift`'s
/// `MarathonHistoryView`) — the permanent record of every completed
/// 200-question run. Reached from Records (`RecordsView_macOS`) and from the
/// scorecard's own "See Marathon history" link. Presented as a sized sheet
/// with a Done header (the `SheetChrome_macOS` idiom from `RecordsView_macOS`).
struct MarathonHistoryView_macOS: View {
    @Query(sort: \MarathonScore.date, order: .reverse) private var scores: [MarathonScore]
    @Environment(\.dismiss) private var dismiss
    @State private var detail: MarathonScore?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Marathon History").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(CompactButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            Group {
                if scores.isEmpty {
                    ContentUnavailableView {
                        Label("No Marathons yet", systemImage: "flag.checkered")
                    } description: {
                        Text("A 200-question test of everything. Play it across as many sittings as you like — we'll keep your place.")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(scores) { s in
                                Button { detail = s } label: { row(s) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .frame(width: 480, height: 560)
        .background(Tidbits.Palette.bg)
        .sheet(item: $detail) { s in
            MarathonResultsView_macOS(score: s, onDone: { detail = nil }, isHistorical: true)
                .frame(minWidth: 560, minHeight: 640)
        }
    }

    private func row(_ s: MarathonScore) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(s.correct)/\(s.total) correct · \(Int(s.accuracy * 100))%")
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Text(s.date.formatted(date: .abbreviated, time: .omitted))
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Spacer()
            Text("\(s.score)")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.teal)
        }
        .padding(14).chunkyCard()
    }
}
#endif
