#if os(macOS)
import SwiftUI

// MARK: - Customize a game (multi-select Mix + category + presets) — parity

/// Mac Customize sheet: pick one mode (plays straight) or several (a Custom Mix,
/// shuffled together), a category, save/load presets. Mirrors the iOS
/// CustomizeSheet; reuses GamePreset + the AppStore preset store.
struct CustomizeSheet_macOS: View {
    let initial: LaunchRequest
    let presets: [GamePreset]
    let onStart: (LaunchRequest) -> Void
    let onSave: (GamePreset) -> Void
    let onDelete: (GamePreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var modes: Set<GameMode>
    @State private var category: TriviaCategory
    @State private var showAllModes: Bool
    @State private var saving = false
    @State private var presetName = ""

    private let coreModes: [GameMode] = [.classic, .timeAttack, .survival, .stake]
    private var playableModes: [GameMode] { GameMode.allCases.filter { $0 != .daily && $0 != .barTrivia && $0 != .mix } }
    private let grid = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    init(initial: LaunchRequest, presets: [GamePreset],
         onStart: @escaping (LaunchRequest) -> Void,
         onSave: @escaping (GamePreset) -> Void,
         onDelete: @escaping (GamePreset) -> Void) {
        self.initial = initial; self.presets = presets
        self.onStart = onStart; self.onSave = onSave; self.onDelete = onDelete
        let initialModes: Set<GameMode> = initial.mode == .mix ? Set(initial.mixModes ?? [.classic]) : [initial.mode]
        _modes = State(initialValue: initialModes)
        _category = State(initialValue: initial.category)
        _showAllModes = State(initialValue: !initialModes.isSubset(of: [.classic, .timeAttack, .survival, .stake]))
    }

    private var request: LaunchRequest {
        if modes.count == 1, let only = modes.first { return LaunchRequest(mode: only, category: category) }
        let ordered = playableModes.filter { modes.contains($0) }
        return LaunchRequest(mode: .mix, category: category, mixModes: ordered)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Customize a game").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Save preset") { presetName = suggestedName; saving = true }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Mode") {
                        LazyVGrid(columns: grid, alignment: .leading, spacing: 10) {
                            ForEach(showAllModes ? playableModes : coreModes) { m in
                                chip(m.title, m.symbol, on: modes.contains(m), accent: m.accent) {
                                    if modes.contains(m) { if modes.count > 1 { modes.remove(m) } } else { modes.insert(m) }
                                }
                            }
                        }
                        Text(modeBlurb).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        Button(showAllModes ? "Show fewer modes" : "Show all modes") { withAnimation { showAllModes.toggle() } }
                            .buttonStyle(.plain).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.blue)
                    }
                    section("Category") {
                        LazyVGrid(columns: grid, alignment: .leading, spacing: 10) {
                            ForEach(TriviaCategory.all) { c in
                                chip(c.name, c.symbol, on: category.id == c.id, accent: c.color) { category = c }
                            }
                        }
                    }
                    if !presets.isEmpty {
                        section("My presets") {
                            LazyVGrid(columns: grid, alignment: .leading, spacing: 10) {
                                ForEach(presets) { p in
                                    Button {
                                        if p.mode == .mix, let ids = p.modeIDs {
                                            modes = Set(ids.compactMap(GameMode.init(rawValue:))); if modes.isEmpty { modes = [.classic] }
                                            showAllModes = true
                                        } else { modes = [p.mode] }
                                        category = .named(p.primaryCategoryID)
                                    } label: {
                                        Text(p.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                                            .lineLimit(1).frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 11)
                                            .background(Capsule().fill(Tidbits.Palette.surface))
                                            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu { Button("Delete", role: .destructive) { onDelete(p) } }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            Divider().overlay(Tidbits.Palette.border)
            Button { onStart(request); dismiss() } label: {
                Label(modes.count > 1 ? "Start the Mix (\(modes.count) modes)" : "Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
            .keyboardShortcut(.defaultAction)
            .padding()
        }
        .frame(width: 520, height: 620)
        .background(Tidbits.Palette.bg)
        .alert("Save this combination", isPresented: $saving) {
            TextField("Name", text: $presetName)
            Button("Save") {
                let name = presetName.trimmingCharacters(in: .whitespaces)
                let m = modes.count == 1 ? (modes.first ?? .classic) : .mix
                if !name.isEmpty {
                    onSave(GamePreset(name: name, mode: m, categoryIDs: [category.id],
                                      modeIDs: playableModes.filter { modes.contains($0) }.map(\.rawValue)))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var suggestedName: String {
        modes.count == 1 ? "\(category.name) \(modes.first?.title ?? "")" : "\(category.name) Mix"
    }
    private var modeBlurb: String {
        if modes.count == 1, let m = modes.first { return "\(m.title): \(m.blurb)" }
        return "Custom Mix: questions drawn from all \(modes.count) selected modes, shuffled together."
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            content()
        }
    }
    private func chip(_ title: String, _ symbol: String, on: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                Text(title).font(Tidbits.TypeRamp.l3).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? accent.legibleForeground : Tidbits.Palette.ink)
            .frame(maxWidth: .infinity).padding(.horizontal, 14).padding(.vertical, 11)
            .background(Capsule().fill(on ? accent : Tidbits.Palette.surface))
            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previous Tidbits (Daily archive) — parity R-DAILY-1

struct DailyArchiveSheet_macOS: View {
    let onPlay: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Previous Tidbits").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            List {
                Section {
                    ForEach(DailyLog.recentDays(), id: \.day) { entry in
                        let today = QuestionProvider.dayKey()
                        HStack {
                            Text(Self.label(for: entry.day, today: today)).foregroundStyle(Tidbits.Palette.ink)
                            Spacer()
                            if let score = entry.score {
                                Text("Scored \(score)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                            } else {
                                Button("Play") { dismiss(); onPlay(entry.day) }.buttonStyle(.borderedProminent).tint(Tidbits.Palette.coral)
                            }
                        }
                    }
                } footer: {
                    Text("Every day has its own set of 7 — the same for everyone. Catching up on a missed day doesn't change your streak.")
                }
            }
        }
        .frame(width: 460, height: 520)
        .background(Tidbits.Palette.bg)
    }

    static func label(for day: String, today: String) -> String {
        if day == today { return "Today" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: day) else { return day }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

// MARK: - First-run onboarding (compact) — parity

struct OnboardingSheet_macOS: View {
    let onDone: () -> Void
    private let points: [(String, String, String)] = [
        ("globe.americas.fill", "All of Wikipedia, as trivia", "Thousands of questions built from real Wikipedia facts — and you can spin up a quiz on any topic."),
        ("square.grid.2x2.fill", "Play your way", "Classic, Time Attack, Survival, Stake, and more — pick a mode and category, or hit Quick Play."),
        ("chart.bar.fill", "Compete with your past self", "Records tracks your streak, accuracy, and the domains you've mastered. Every miss comes back to help it stick."),
    ]
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Tidbits").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: p.0).font(.system(size: 24, weight: .black)).foregroundStyle(Tidbits.Palette.coral).frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.1).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Text(p.2).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            Button("Get started", action: onDone)
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 520)
        .background(Tidbits.Palette.bg)
    }
}
#endif
