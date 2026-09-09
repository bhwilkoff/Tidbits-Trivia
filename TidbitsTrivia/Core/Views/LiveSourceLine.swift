import SwiftUI

/// The charter, on a joiner: where the fact came from. A Wikipedia link when
/// there is one, the article's name when there is not. Reveal only — the
/// source would give the answer away before it.
struct LiveSourceLine: View {
    let source: LiveRoom.Source
    var body: some View {
        if let u = source.url, let url = URL(string: u) {
            Link(destination: url) {
                Label("Learn more on Wikipedia · \(source.title)", systemImage: "book.closed")
                    .font(Tidbits.TypeRamp.l4.weight(.bold)).foregroundStyle(Tidbits.Palette.blue)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Label("From Wikipedia · \(source.title)", systemImage: "book.closed")
                .font(Tidbits.TypeRamp.l4.weight(.bold)).foregroundStyle(Tidbits.Palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
