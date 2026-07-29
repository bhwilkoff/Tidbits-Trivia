#if os(tvOS)
import SwiftUI
import SwiftData

/// tvOS mirror of the Club Marathon history (docs/CLUB-FEATURES-BUILD.md
/// "Feature 3", canonical at `iOS/Views/MarathonResultsView.swift`'s
/// `MarathonHistoryView`) — the permanent record of every completed
/// 200-question run, ten-foot and dark-first. Reached from Records
/// (`RecordsView_tvOS`) and from the scorecard's own "See Marathon history"
/// link (`TVMarathonResultsView`).
struct TVMarathonHistoryView: View {
    /// Set when this view is shown INLINE by the Club hub (which swaps its own content
    /// rather than stacking a nested `.fullScreenCover` — see `ClubHubView_tvOS`). nil means
    /// "I'm a modal, dismiss me."
    var onClose: (() -> Void)? = nil

    @Query(sort: \MarathonScore.date, order: .reverse) private var scores: [MarathonScore]
    @Environment(\.dismiss) private var dismiss
    @State private var detail: MarathonScore?

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Text("MARATHON HISTORY")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(TVTheme.text)
                    if scores.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 20) {
                            ForEach(scores) { s in
                                Button { detail = s } label: { row(s) }
                                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.teal, selected: false))
                            }
                        }
                        .focusSection()
                    }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onExitCommand { if let onClose { onClose() } else { dismiss() } }
        .fullScreenCover(item: $detail) { s in
            TVMarathonResultsView(score: s, onDone: { detail = nil }, isHistorical: true)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No Marathons yet")
                .font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("A 200-question test of everything. Play it across as many sittings as you like — we'll keep your place.")
                .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ s: MarathonScore) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(s.correct)/\(s.total) correct · \(Int(s.accuracy * 100))%")
                    .font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(s.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
            Spacer()
            Text("\(s.score)")
                .font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.teal)
        }
        .padding(.horizontal, 30).padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }
}
#endif
