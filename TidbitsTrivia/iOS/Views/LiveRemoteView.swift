#if os(iOS)
import SwiftUI

/// G6, native: the host's phone as a remote for the laptop cockpit. Pair with the
/// room code AND the six-digit PIN the laptop shows (the code is on the projector,
/// so it authorises nothing), then Reveal / Next / Skip / Scores while walking the
/// room. Commands carry a monotonic id resumed from the HOST's counter; the host
/// refuses a wrong PIN, an unknown verb and an id it has already run. Mirror of the
/// web's `remoteHTML` (js/live.js).
struct LiveRemoteView: View {
    var initialCode: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var pin = ""
    @State private var paired = false
    @State private var pub: LiveRoom.Pub?
    @State private var remoteID = 0
    @State private var note: String?
    @State private var error: String?
    @State private var streamTask: Task<Void, Never>?
    private let db = FirebaseRTDB.shared

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            if paired { remote } else { pairForm }
        }
        .task {
            code = initialCode
            if let h = DebugHooks.liveRemote {   // harness: pair, then send one verb the way a tap does
                code = h.code; pin = h.pin
                await pair()
                if let verb = DebugHooks.liveRemoteVerb, LiveRemote.verbs.contains(verb) {
                    try? await Task.sleep(for: .seconds(DebugHooks.liveRemoteAt))
                    await send(verb)
                }
            }
        }
        .onDisappear { streamTask?.cancel() }
    }

    private var pairForm: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("HOST REMOTE").font(Tidbits.TypeRamp.l5).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Tidbits.Palette.blue))
                .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            Text("Drive the night").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Text("Enter your room code and the PIN from your laptop.").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).multilineTextAlignment(.center)
            TextField("CODE", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .multilineTextAlignment(.center).font(.system(size: 30, weight: .black, design: .monospaced)).kerning(8).padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                .onChange(of: code) { _, v in let c = v.uppercased().filter { $0.isLetter || $0.isNumber }; if c != v || c.count > 4 { code = String(c.prefix(4)) } }
                .accessibilityIdentifier("remote.code")
            TextField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center).font(.system(size: 30, weight: .black, design: .monospaced)).kerning(6).padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                .onChange(of: pin) { _, v in let d = v.filter(\.isNumber); if d != v || d.count > 6 { pin = String(d.prefix(6)) } }
                .accessibilityIdentifier("remote.pin")
            if let error { Text(error).font(Tidbits.TypeRamp.l5).foregroundStyle(.red) }
            Button { Task { await pair() } } label: { Text("Pair").frame(maxWidth: .infinity) }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.blue, textColor: .white))
                .disabled(code.count < 4 || pin.count < 6)
            Text("The PIN is on the host screen, not the projector — the room code alone cannot drive the show.")
                .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft).multilineTextAlignment(.center)
            Button("Cancel") { dismiss() }.font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            Spacer()
        }
        .padding(24)
    }

    private var remote: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("REMOTE · \(code)" + (pub.map { " · ROUND \($0.round)" } ?? ""))
                    .font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                Spacer()
                Button("Done") { dismiss() }.font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Text(pub?.prompt.isEmpty == false ? pub!.prompt : "Waiting for the host…")
                .font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("remote.prompt")
            if let p = pub, p.phase == "reveal", let opts = p.options, let i = p.answerIndex, i < opts.count {
                Text("Answer: \(opts[i])").font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.mint)
            } else if let a = pub?.answer, pub?.phase == "reveal" {
                Text("Answer: \(a)").font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.mint)
            }
            Spacer()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                remoteButton("Reveal", "eye.fill", verb: "reveal", fill: Tidbits.Palette.coral)
                remoteButton("Next", "forward.fill", verb: "next", fill: Tidbits.Palette.ink)
                remoteButton("Skip", "forward.end.fill", verb: "skip", fill: Tidbits.Palette.surface, text: Tidbits.Palette.ink)
                remoteButton("Scores", "list.number", verb: "scores", fill: Tidbits.Palette.surface, text: Tidbits.Palette.ink)
            }
            if let note { Text(note).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft) }
        }
        .padding(24)
    }

    private func remoteButton(_ title: String, _ icon: String, verb: String, fill: Color, text: Color = .white) -> some View {
        Button { Task { await send(verb) } } label: {
            Label(title, systemImage: icon).font(.system(size: 20, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity).padding(.vertical, 26)
        }
        .buttonStyle(ChunkyButtonStyle(fill: fill, textColor: text))
        .accessibilityIdentifier("remote.\(verb)")
    }

    /// Resume from the HOST's counter: a fresh remote that started at 1 would be
    /// refused forever once the host had run anything.
    private func pair() async {
        guard code.count == 4, pin.count == 6 else { error = pin.count < 6 ? "Enter the 6-digit PIN from your laptop." : "Enter the 4-letter room code."; return }
        error = nil
        _ = try? await db.ensureAuth()
        // ONLY the id: `control` also carries the PIN, and the rules hand that node to the
        // host alone — a readable control node was the keys to the show.
        remoteID = ((try? await db.get("\(LiveRoom.path(code))/control/id", as: Int.self)) ?? nil) ?? 0
        paired = true
        streamTask?.cancel()
        streamTask = Task { [db, code] in
            while !Task.isCancelled {
                if let stream = try? await db.stream("\(LiveRoom.path(code))/pub") {
                    do {
                        for try await ev in stream {
                            guard ev.path == "/", let d = ev.dataJSON, let p = try? JSONDecoder().decode(LiveRoom.Pub.self, from: d) else { continue }
                            await MainActor.run { pub = p }
                        }
                    } catch {}
                }
                if !Task.isCancelled { try? await Task.sleep(for: .seconds(1.5)) }
            }
        }
    }

    private func send(_ verb: String) async {
        remoteID += 1
        do {
            try await db.put("\(LiveRoom.path(code))/control", RemoteCommand(id: remoteID, verb: verb, pin: pin))
            note = nil
        } catch {
            // The command did not land, so do NOT keep the id: reusing it next press is
            // correct, and advancing it would leave a gap the host silently skips past.
            remoteID -= 1
            note = "That did not send — try again."
        }
    }
}

#endif
