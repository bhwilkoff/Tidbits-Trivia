import SwiftUI

/// The wrap's learning payoff, shared by the iPhone, Apple TV and Mac joiners:
/// "Tough ones you nailed" (with the share line) and "Tidbits to remember"
/// (the answer, the story, the Wikipedia source). Nothing here is decorative —
/// a night should leave every table knowing something it did not.
struct LiveRecapView: View {
    let book: LiveRecapBook
    var tenFoot = false   // tvOS: bigger type, no share sheet

    var body: some View {
        let tough = book.tough, remember = book.toRemember
        if !tough.isEmpty || !remember.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                if !tough.isEmpty {
                    Label("Tough ones you nailed", systemImage: "sparkles")
                        .font(tenFoot ? .system(size: 34, weight: .heavy, design: .rounded) : Tidbits.TypeRamp.l2)
                        .foregroundStyle(tenFoot ? .white : Tidbits.Palette.ink)
                    ForEach(tough) { e in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(e.prompt).font(tenFoot ? .system(size: 27, weight: .bold, design: .rounded) : Tidbits.TypeRamp.l3)
                                .foregroundStyle(tenFoot ? .white : Tidbits.Palette.ink)
                            Text("You got it: \(e.answer ?? "")").font(tenFoot ? .system(size: 23) : Tidbits.TypeRamp.l5)
                                .foregroundStyle(tenFoot ? Color.white.opacity(0.78) : Tidbits.Palette.inkSoft)
                            #if !os(tvOS)
                            ShareLink(item: LiveRecapBook.howDidYouKnowText(e)) {
                                Label("How did you know that? · Share", systemImage: "square.and.arrow.up")
                                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.blue)
                            }
                            .buttonStyle(.plain)
                            #endif
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(tenFoot ? Color.white.opacity(0.08) : Tidbits.Palette.surface))
                    }
                }
                if !remember.isEmpty {
                    Label("Tidbits to remember", systemImage: "brain.head.profile")
                        .font(tenFoot ? .system(size: 34, weight: .heavy, design: .rounded) : Tidbits.TypeRamp.l2)
                        .foregroundStyle(tenFoot ? .white : Tidbits.Palette.ink)
                    ForEach(remember) { e in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(e.prompt).font(tenFoot ? .system(size: 27, weight: .bold, design: .rounded) : Tidbits.TypeRamp.l3)
                                .foregroundStyle(tenFoot ? .white : Tidbits.Palette.ink)
                            Text("Answer: \(e.answer ?? "")").font(tenFoot ? .system(size: 23) : Tidbits.TypeRamp.l5)
                                .foregroundStyle(tenFoot ? Color.white.opacity(0.78) : Tidbits.Palette.inkSoft)
                            if let story = e.story, !story.isEmpty {
                                Text(story).font(tenFoot ? .system(size: 21) : Tidbits.TypeRamp.l5).foregroundStyle(tenFoot ? Color.white.opacity(0.78) : Tidbits.Palette.inkSoft)
                            }
                            if let t = e.sourceTitle, !t.isEmpty {
                                #if os(tvOS)
                                // A TV opens no browser: name the article, do not offer a focusable
                                // button (it drew as a capsule floating over the card).
                                Label("From Wikipedia · \(t)", systemImage: "book").font(.system(size: 21)).foregroundStyle(tenFoot ? Color.white.opacity(0.78) : Tidbits.Palette.inkSoft)
                                #else
                                LiveSourceLine(source: LiveRoom.Source(title: t, url: e.sourceURL))
                                #endif
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(tenFoot ? Color.white.opacity(0.08) : Tidbits.Palette.surface))
                    }
                }
            }
            .accessibilityIdentifier("live.recap")
        }
    }
}
