import AVFoundation
import AVKit
import SwiftUI

/// Decision 060 / macOS-DESIGN A8.8: the clip the host offered, on the joiner.
///
/// It is an OFFER. Nothing downloads until this player taps or the host presses
/// Play, and nothing plays until the player taps — phones are in pockets and a
/// bar is loud, and forty phones starting a song a beat apart is not a feature.
/// The host's cue readies the clip so the tap is instant, and positions it
/// where the room is, so a late tap joins the song mid-way instead of starting
/// it over. Shared by the iOS, tvOS and Mac joiners; the web twin is
/// `mountMedia` in js/live.js, Android's is `LiveClip` in LiveRoom.kt.
struct LiveClipView: View {
    let media: LiveRoom.Media
    let code: String

    @State private var player: AVPlayer?
    @State private var loading = false
    @State private var errorText: String?
    @State private var playing = false
    @State private var durationSeconds: Double = 0

    private var isVideo: Bool { media.kind == "video" }
    #if os(tvOS)
    private let titleFont = Font.system(size: 34, weight: .heavy, design: .rounded)
    private let captionFont = Font.system(size: 25, weight: .semibold, design: .rounded)
    private let glyphSize: CGFloat = 56
    private let rowPad: CGFloat = 22   // room for the focus scale — a focused tvOS button grows past its glyph
    #else
    private let titleFont = Tidbits.TypeRamp.l3
    private let captionFont = Tidbits.TypeRamp.l5
    private let glyphSize: CGFloat = 34
    private let rowPad: CGFloat = 10
    #endif
    private var sizeText: String {
        guard let b = media.bytes else { return "" }
        return b >= 1_000_000 ? String(format: " · %.1f MB", Double(b) / 1_000_000) : " · \(max(1, b / 1000)) KB"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let player, isVideo {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if let player {
                audioRow(player)
            } else {
                offerButton
            }
            if let errorText {
                Text(errorText).font(captionFont).foregroundStyle(Tidbits.Palette.coral)
            }
        }
        // The host's cue: fetch now so the tap is instant. Never plays on its own.
        .task(id: media.startedAt) {
            if media.startedAt != nil, player == nil, !loading { await load(thenPlay: false) }
        }
        // Hook for the device harness: take up the offer without a finger on the
        // glass. No-op in production.
        .task {
            guard ProcessInfo.processInfo.environment["TIDBITS_LIVE_TAPCLIP"] == "1" else { return }
            try? await Task.sleep(for: .seconds(2))
            await load(thenPlay: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem, item == player?.currentItem else { return }
            playing = false
            player?.seek(to: .zero)
        }
        .onDisappear { player?.pause() }
    }

    private var offerButton: some View {
        Button { Task { await load(thenPlay: true) } } label: {
            HStack(spacing: 12) {
                Image(systemName: loading ? "arrow.down.circle" : (isVideo ? "play.rectangle.fill" : "music.note"))
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loading ? "Loading the clip…" : (isVideo ? "Watch the clip" : "Listen to the clip"))
                        .font(titleFont)
                    Text(subtitle).font(captionFont).opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(Tidbits.Palette.blue))
        }
        .disabled(loading)
        #if !os(tvOS)
        .buttonStyle(.plain)
        #endif
    }

    private var subtitle: String {
        if media.startedAt != nil { return "Playing in the room now — tap to hear it here" }
        return (media.name ?? (isVideo ? "Video" : "Audio")) + sizeText
    }

    private func audioRow(_ player: AVPlayer) -> some View {
        HStack(spacing: rowPad + 6) {
            Button {
                if playing { player.pause(); playing = false } else { player.play(); playing = true }
            } label: {
                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: glyphSize))
                    .foregroundStyle(Tidbits.Palette.blue)
                    .frame(width: glyphSize * 1.5, height: glyphSize * 1.5)
            }
            #if os(tvOS)
            .buttonStyle(.borderless)   // never .plain on tvOS — it kills focus; borderless keeps the glyph, not a platter
            #else
            .buttonStyle(.plain)
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Text(media.name ?? "Audio clip").font(titleFont).foregroundStyle(Tidbits.Palette.ink)
                Text(playing ? "Playing" : (durationSeconds > 0 ? "\(Int(durationSeconds.rounded())) s" : "Ready"))
                    .font(captionFont).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14 + rowPad / 2).padding(.vertical, rowPad)
        .background(RoundedRectangle(cornerRadius: 14).fill(Tidbits.Palette.surface))
    }

    private func load(thenPlay: Bool) async {
        if let player {
            if thenPlay { await seekToRoom(player); player.play(); playing = true }
            return
        }
        loading = true; errorText = nil
        defer { loading = false }
        do {
            let url = try await LiveMediaCache.shared.localURL(for: media, code: code)
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
            let p = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            durationSeconds = duration.isFinite ? duration : 0
            player = p
            await seekToRoom(p)
            if thenPlay { p.play(); playing = true }
        } catch {
            errorText = "Clip unavailable — the room hears it from the host. (\(error.localizedDescription))"
        }
    }

    /// Where the room is in the clip, if the host has started it.
    private func seekToRoom(_ p: AVPlayer) async {
        guard let started = media.startedAt else { return }
        let offset = Double(LivePlayerClient.nowMS() - started) / 1000
        guard offset > 1, durationSeconds > 0, offset < durationSeconds - 0.5 else { return }
        await p.seek(to: CMTime(seconds: offset, preferredTimescale: 600))
    }
}
