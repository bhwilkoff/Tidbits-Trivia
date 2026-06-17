#if os(tvOS)
import SwiftUI

/// tvOS placeholder so the universal target compiles for Apple TV from
/// day one (the door left open — Decision 013). The ten-foot living-room
/// experience is a Phase 2 milestone; read `tvos-platform-patterns`
/// before building it (focus engine, shelf/hero recipes, writable-dir
/// trap). NEVER buttonStyle(.plain) here — it destroys focusability.
struct ContentView_tvOS: View {
    @State private var hasClaimedInitialFocus = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text("TIDBITS")
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("Living-room trivia is coming to Apple TV.")
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Button("Got it") { }
                .buttonStyle(.borderedProminent)
                .focused($focused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tidbits.Palette.ink)
        .onAppear {
            guard !hasClaimedInitialFocus else { return }
            hasClaimedInitialFocus = true
            focused = true
        }
    }
}
#endif
