#if os(macOS)
import Foundation
import Testing

/// DEEP_LINKS.md — one parser for every URL shape an entry point can hand the app.
///
/// The router used to switch on `url.host`, which routes `tidbits://item/x` and
/// silently drops `https://tidbitstrivia.com/item/x`: every Universal Link,
/// including the projector's scan-to-join QR, launched the app and did nothing.
/// These pin both shapes for every route so that cannot regress quietly.
@Suite("Deep links — custom scheme and https resolve to the same route")
struct DeepLinkParseTests {
    private func parse(_ s: String) -> DeepLink? { DeepLink.parse(URL(string: s)!) }

    @Test func projectorQRJoinsByCode() {
        #expect(parse("https://tidbitstrivia.com/live/MINV") == .live("MINV"))
        #expect(parse("https://tidbitstrivia.com/live/minv") == .live("MINV"))
        #expect(parse("https://www.tidbitstrivia.com/live/MINV/") == .live("MINV"))
        #expect(parse("tidbits://live/MINV") == .live("MINV"))
        #expect(parse("tidbitstrivia://live/minv") == .live("MINV"))
    }

    @Test func hashRoutedWebLinkStillResolves() {
        #expect(parse("https://tidbitstrivia.com/#/live/MINV") == .live("MINV"))
    }

    @Test func everyRouteResolvesFromBothShapes() {
        #expect(parse("https://tidbitstrivia.com/item/abc") == .item("abc"))
        #expect(parse("tidbits://item/abc") == .item("abc"))
        #expect(parse("https://tidbitstrivia.com/quiz/q1") == .quiz("q1"))
        #expect(parse("tidbitstrivia://quiz/q1") == .quiz("q1"))
        #expect(parse("https://tidbitstrivia.com/daily") == .daily)
        #expect(parse("tidbits://daily") == .daily)
        #expect(parse("tidbits://topic/Volcano") == .topic("Volcano"))
        #expect(parse("tidbits://category/history") == .category("history"))
    }

    @Test func unknownAndEmptyRoutesAreNil() {
        #expect(parse("https://tidbitstrivia.com/support") == nil)
        #expect(parse("https://tidbitstrivia.com/") == nil)
        #expect(parse("https://tidbitstrivia.com/live/") == nil)
        #expect(parse("tidbits://item") == nil)
    }
}
#endif
