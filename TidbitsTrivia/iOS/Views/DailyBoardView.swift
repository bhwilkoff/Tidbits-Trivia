#if os(iOS)
import SwiftUI

/// iOS presentation of the Daily's global board (docs/DAILY-BOARD-CONTRACT.md) — the
/// shared `DailyBoardContent` in a NavigationStack with a Done button. Reached from the
/// Daily results screen as a sheet; a LAYER on the Daily, never a separate mode.
struct DailyBoardView: View {
    let day: String
    let myScore: Int
    let myMarks: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DailyBoardContent(day: day, myScore: myScore, myMarks: myMarks)
                .navigationTitle("Daily · the world")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

#endif
