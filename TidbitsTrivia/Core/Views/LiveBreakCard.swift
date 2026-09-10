import SwiftUI

/// A3.14 — the room is on a break, said on the player's own phone (and the TV).
/// A table that stepped outside should not come back to a stale question and answer
/// it late; the countdown is the same `LiveBreak` text the big screen shows.
struct LiveBreakCard: View {
    var until: Int?
    /// Tick 33: this device's clock, corrected into the HOST's frame.
    var offsetMS: Double = 0
    // tvOS is dark-first and iOS is the cream sticker — the SAME default foreground is
    // invisible on one of them (legibility-check-compositing). Say the color out loud.
    #if os(tvOS)
    private var headSize: CGFloat { 46 }
    private var subSize: CGFloat { 27 }
    private var ink: Color { .white }
    #else
    private var headSize: CGFloat { 30 }
    private var subSize: CGFloat { 17 }
    private var ink: Color { Tidbits.Palette.ink }
    #endif

    var body: some View {
        // The same 0.5s timeline the projector uses, so a minute rolling over is
        // visible on the phone rather than waiting for the host's next publish.
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            VStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: headSize * 0.7, weight: .black))
                    .foregroundStyle(Tidbits.Palette.coral)
                Text(LiveBreak.headline(until: until, now: LiveClock.hostNow(offsetMS: offsetMS, now: ctx.date)))
                    .font(.system(size: headSize, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("live.breakHeadline")
                let clock = LiveBreak.clockLine(until: until, now: LiveClock.hostNow(offsetMS: offsetMS, now: ctx.date))
                Text(clock.isEmpty ? "Grab a drink — the next round is coming up." : "Grab a drink — \(clock).")
                    .font(.system(size: subSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .opacity(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        }
    }
}
