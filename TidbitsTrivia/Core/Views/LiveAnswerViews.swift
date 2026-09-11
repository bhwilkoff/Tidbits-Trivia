#if os(iOS) || os(macOS)
import SwiftUI

// Shared by the iOS and Mac joiners. Until 2026-09-10 these lived inside the iOS
// view as private types, and the Mac joiner could answer nothing but multiple
// choice — a Name It question showed "Click your answer." over an empty space.
// A joiner that cannot answer a whole question type is not a joiner.

// MARK: - Per-type answer surfaces (host auto-scores each on reveal)

struct LiveNumericAnswer: View {
    let spec: LiveRoom.Numeric
    let locked: Bool
    var onSubmit: (Double) -> Void
    @State private var value: Double
    @State private var sent = false
    init(spec: LiveRoom.Numeric, locked: Bool, onSubmit: @escaping (Double) -> Void) {
        self.spec = spec; self.locked = locked; self.onSubmit = onSubmit
        _value = State(initialValue: ((spec.min + spec.max) / 2).rounded())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(value == value.rounded() ? "\(Int(value))\(unit)" : String(format: "%.1f%@", value, unit))
                .font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Slider(value: $value, in: spec.min...spec.max, step: spec.step > 0 ? spec.step : 1)
                .tint(Tidbits.Palette.blue).disabled(locked || sent)
            if !sent { liveSubmitButton(disabled: locked) { sent = true; onSubmit(value) } }
        }
    }
    private var unit: String { spec.unit.isEmpty ? "" : " \(spec.unit)" }
}

struct LiveTextAnswer: View {
    let locked: Bool
    var onSubmit: (String) -> Void
    @State private var text = ""
    @State private var sent = false
    var body: some View {
        VStack(spacing: 10) {
            TextField("Type your answer", text: $text).textFieldStyle(.roundedBorder).autocorrectionDisabled().disabled(locked || sent)
            if !sent {
                liveSubmitButton(disabled: locked || text.trimmingCharacters(in: .whitespaces).isEmpty) {
                    sent = true; onSubmit(text.trimmingCharacters(in: .whitespaces))
                }
            }
        }
    }
}

struct LiveEnumerateAnswer: View {
    let target: Int
    let locked: Bool
    var onSubmit: ([String]) -> Void
    @State private var entry = ""
    @State private var items: [String] = []
    @State private var sent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Name as many as you can \(target > 0 ? "(\(items.count)/\(target))" : "(\(items.count))")")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            if !items.isEmpty {
                Text(items.joined(separator: " · ")).font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            if !sent {
                HStack {
                    TextField("Add one…", text: $entry).textFieldStyle(.roundedBorder).autocorrectionDisabled().disabled(locked)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(locked || entry.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                liveSubmitButton(title: "Done", disabled: locked || items.isEmpty) { sent = true; onSubmit(items) }
            }
        }
    }
    private func add() {
        let t = entry.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !items.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        items.append(t); entry = ""
    }
}

struct LiveOrderingAnswer: View {
    let items: [String]
    let locked: Bool
    var onSubmit: ([Int]) -> Void
    @State private var order: [Int]
    @State private var sent = false
    init(items: [String], locked: Bool, onSubmit: @escaping ([Int]) -> Void) {
        self.items = items; self.locked = locked; self.onSubmit = onSubmit
        _order = State(initialValue: Array(items.indices))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Put them in order (top = first).").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(Array(order.enumerated()), id: \.element) { pos, idx in
                HStack(spacing: 10) {
                    Text("\(pos + 1).").font(.system(size: 15, weight: .black)).foregroundStyle(Tidbits.Palette.inkSoft)
                    Text(items[idx]).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Spacer(minLength: 0)
                    if !locked && !sent {
                        Button { move(pos, -1) } label: { Image(systemName: "chevron.up") }.disabled(pos == 0).buttonStyle(.plain)
                        Button { move(pos, 1) } label: { Image(systemName: "chevron.down") }.disabled(pos == order.count - 1).buttonStyle(.plain)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).chunkyCard(fill: .white)
            }
            if !sent { liveSubmitButton(disabled: locked) { sent = true; onSubmit(order) } }
        }
    }
    private func move(_ pos: Int, _ d: Int) { let n = pos + d; guard order.indices.contains(n) else { return }; order.swapAt(pos, n) }
}

struct LiveMatchingAnswer: View {
    let keys: [String]
    let values: [String]
    let locked: Bool
    var onSubmit: ([Int]) -> Void
    @State private var pairs: [Int]
    @State private var sent = false
    init(keys: [String], values: [String], locked: Bool, onSubmit: @escaping ([Int]) -> Void) {
        self.keys = keys; self.values = values; self.locked = locked; self.onSubmit = onSubmit
        _pairs = State(initialValue: Array(repeating: -1, count: keys.count))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Match each to its pair.").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                HStack {
                    Text(key).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                    Spacer(minLength: 8)
                    Menu {
                        ForEach(Array(values.enumerated()), id: \.offset) { vi, v in Button(v) { pairs[i] = vi } }
                    } label: {
                        Text(pairs[i] >= 0 ? values[pairs[i]] : "Choose…")
                            .font(Tidbits.TypeRamp.l4).foregroundStyle(pairs[i] >= 0 ? Tidbits.Palette.blue : Tidbits.Palette.inkSoft)
                    }.disabled(locked || sent)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).chunkyCard(fill: .white)
            }
            if !sent { liveSubmitButton(disabled: locked || pairs.contains(-1)) { sent = true; onSubmit(pairs) } }
        }
    }
}

/// Shared submit button for the answer surfaces.
@ViewBuilder func liveSubmitButton(title: String = "Submit", disabled: Bool, _ action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
        .disabled(disabled).frame(maxWidth: .infinity)
}

#endif
