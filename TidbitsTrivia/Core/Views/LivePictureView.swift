import SwiftUI

/// Decision 060 (pictures): the question's picture on a joiner. Shows the small
/// fallback in `imageURL` at once (a data URL or an https link) and, when the
/// host published the full picture as a room node, fetches that node ONCE and
/// swaps it in. Shared by the iOS, tvOS and Mac joiners.
struct LivePictureView: View {
    let picture: LiveRoom.Media?
    let fallback: String?
    let code: String
    var maxHeight: CGFloat = 240
    var cornerRadius: CGFloat = 14

    @State private var fullURL: URL?

    var body: some View {
        Group {
            if let fullURL {
                AsyncImage(url: fullURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() }
                    else { fallbackImage }
                }
            } else {
                fallbackImage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: picture?.url) {
            fullURL = nil
            guard let picture else { return }
            fullURL = try? await LiveMediaCache.shared.localURL(for: picture, code: code)
        }
    }

    @ViewBuilder private var fallbackImage: some View {
        if let fallback, let url = URL(string: fallback) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFit() }
                else if phase.error != nil { EmptyView() }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
            }
        } else {
            EmptyView()
        }
    }
}
