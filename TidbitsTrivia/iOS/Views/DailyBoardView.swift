import SwiftUI

/// The Daily's global board (docs/DAILY-BOARD-CONTRACT.md) — reads the static JSON the
/// hourly cron publishes (free/cacheable, never RTDB). Shows your standing, per-question
/// global accuracy against your own hits, and today's top. Honest about the hourly cadence.
/// A LAYER on the Daily, reached from its results screen — never a separate mode.
struct DailyBoardView: View {
    let day: String
    let myScore: Int
    let myMarks: String        // 7-char "0/1", pickDaily-aligned

    @Environment(\.dismiss) private var dismiss
    @State private var board: DailyBoard.Board?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    scoreCard
                    if !loaded {
                        ProgressView().padding(.top, 40)
                    } else if let board, board.n > 0 {
                        standing(board)
                        perQuestion(board)
                        topBoard(board)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, Tidbits.Metric.pad)
                .padding(.vertical, 24)
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationTitle("Daily · the world")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            board = await DailyBoard.results(day: day)
            loaded = true
        }
    }

    private var scoreCard: some View {
        VStack(spacing: 8) {
            Text("DAILY · \(day)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            Text("\(myScore)").font(Tidbits.TypeRamp.title(56)).foregroundStyle(Tidbits.Palette.ink)
            Text("everyone played the same set today")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .chunkyCard(fill: Tidbits.Palette.blue.opacity(0.12))
    }

    @ViewBuilder private func standing(_ board: DailyBoard.Board) -> some View {
        if let pct = DailyBoard.percentile(hist: board.hist, myScore: myScore) {
            VStack(spacing: 2) {
                Text("\(pct)%").font(Tidbits.TypeRamp.title(44)).foregroundStyle(Tidbits.Palette.ink)
                Text("you beat \(pct)% of \(board.n.formatted()) players today")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func perQuestion(_ board: DailyBoard.Board) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How the world did").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            ForEach(Array(board.perQ.enumerated()), id: \.offset) { i, rate in
                HStack(spacing: 10) {
                    Circle().fill(mark(i) == "1" ? Tidbits.Palette.mint : mark(i) == "0" ? Tidbits.Palette.coral : Tidbits.Palette.inkSoft)
                        .frame(width: 14, height: 14)
                    Text("Question \(i + 1)").font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.ink)
                    Spacer()
                    Text("\(Int((rate * 100).rounded()))% got it")
                        .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).chunkyCard()
    }

    private func topBoard(_ board: DailyBoard.Board) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's top").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            ForEach(Array(board.top.prefix(20).enumerated()), id: \.offset) { i, r in
                HStack(spacing: 10) {
                    Text("\(i + 1)").font(Tidbits.TypeRamp.l6)
                        .foregroundStyle(i == 0 ? Tidbits.Palette.ink : Tidbits.Palette.inkSoft)
                        .frame(width: 26, alignment: .leading)
                    Text(r.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
                    if i == 0 {
                        Text("TOP").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.coral)
                    }
                    Spacer()
                    Text("\(r.score)").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.ink)
                }
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Tidbits.Palette.bgDeep))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("You're among the first today.").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
            Text("The global board refreshes every hour — check back to see where you landed.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(16).chunkyCard()
    }

    private func mark(_ i: Int) -> Character {
        i < myMarks.count ? Array(myMarks)[i] : "?"
    }
}
