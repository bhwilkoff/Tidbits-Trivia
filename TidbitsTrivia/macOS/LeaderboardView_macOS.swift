#if os(macOS)
import SwiftUI

/// The season / per-venue standings on the Mac.
///
/// macOS had NO leaderboard at all: the sidebar was Play/Records/Create/Tidbits
/// Live and `LeaderboardView` existed only for iOS and tvOS. The Wave E board is
/// the moat feature, and the platform that HOSTS pub nights was the one platform
/// that could not see the standings those nights produce.
///
/// Core does the work (`LeaderboardAPI` reads the static Pages JSON, never RTDB),
/// so this is shell only — the rule that makes a new Apple platform cheap.
struct LeaderboardView_macOS: View {
    /// The empty state names a live night as the way onto the board, so it has to
    /// be able to open one. Naming an action without offering it is the same fault
    /// as a screen that narrates navigation (ledger W5).
    var onHostANight: () -> Void = {}

    @State private var overall: [LeaderboardRow] = []
    @State private var venues: [(venue: String, rows: [LeaderboardRow])] = []
    @State private var myUid = ""
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if loading {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .center).padding(.top, 40)
                } else if overall.isEmpty && venues.isEmpty {
                    empty
                } else {
                    if !overall.isEmpty { board("This season · Overall", overall) }
                    ForEach(venues, id: \.venue) { board($0.venue, $0.rows) }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Tidbits.Palette.bg)
        .navigationTitle("Leaderboard")
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PlayerIdentity.seasonDisplay(PlayerIdentity.currentSeason()))
                .font(.title2.weight(.bold)).foregroundStyle(Tidbits.Palette.ink)
            Text("Resets in " + pluralized(PlayerIdentity.seasonResetDays(), "day") + " · refreshes hourly")
                .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
        }
    }

    /// `ContentUnavailableView` — the same empty state the Story archive and the
    /// Knowledge atlas use. This page used to put one grey sentence in the top-left
    /// corner of an otherwise empty window, and that sentence named two actions it
    /// did not offer.
    private var empty: some View {
        ContentUnavailableView {
            Label("No standings yet", systemImage: "trophy.fill")
        } description: {
            Text("Play a live night while signed in and you'll climb the board here.")
        } actions: {
            Button("Host a night") { onHostANight() }
                .buttonStyle(.borderedProminent).tint(Tidbits.Palette.coral)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func board(_ title: String, _ rows: [LeaderboardRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Tidbits.Palette.ink)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Divider().overlay(Tidbits.Palette.border) }
                    row(i, r)
                }
            }
            .quietCard()
        }
    }

    private func row(_ i: Int, _ r: LeaderboardRow) -> some View {
        let mine = !myUid.isEmpty && r.uid == myUid          // Wave E: defendable titles
        return HStack(spacing: 10) {
            Text("\(i + 1)").font(.body.monospacedDigit())
                .foregroundStyle(i == 0 ? Tidbits.Palette.ink : Tidbits.Palette.inkSoft)
                .frame(width: 26, alignment: .trailing)
            if i == 0 { Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow) }
            Text(r.name).fontWeight(.semibold).foregroundStyle(Tidbits.Palette.ink)
            if mine {
                Text("YOU").font(.caption2.weight(.black)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Tidbits.Palette.blue, in: Capsule())
            }
            Spacer()
            Text("\(r.nights) night\(r.nights == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
            Text("\(r.score)").font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(Tidbits.Palette.ink)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(mine ? Tidbits.Palette.blue.opacity(0.10) : .clear)
    }

    private func load() async {
        myUid = await FirebaseRTDB.shared.uid ?? ""
        let idx = await LeaderboardAPI.index()
        guard let season = idx.keys.sorted().last else { loading = false; return }
        overall = await LeaderboardAPI.overall(season: season)
        var vs: [(venue: String, rows: [LeaderboardRow])] = []
        for venue in (idx[season] ?? []).sorted() {
            let rows = await LeaderboardAPI.venue(season: season, venue: venue)
            if !rows.isEmpty { vs.append((venue, rows)) }
        }
        venues = vs
        loading = false
    }
}
#endif
