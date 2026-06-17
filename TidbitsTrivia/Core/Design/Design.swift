import SwiftUI

/// Tidbits design system — one intentional, playful, 90s-Memphis-inspired
/// language shared by every Apple surface. Web/Android keep token-parity
/// copies (see DESIGN tokens table in CLAUDE.md). Density comes from
/// removing chrome; pops of color come from a FIXED palette, never ad hoc.
enum Tidbits {

    // MARK: - Palette
    //
    // Warm-paper background + bold ink + a fixed set of "pop" colors.
    // Category accents are drawn ONLY from `pops` so the app never
    // invents a seventh hue. Hex chosen for AA contrast of ink-on-pop.

    enum Palette {
        static let bg       = Color(hex: 0xFBF3E4) // warm cream "paper"
        static let bgDeep   = Color(hex: 0xF3E7CE) // recessed cream
        static let surface  = Color.white
        static let ink      = Color(hex: 0x1A1714) // near-black text
        static let inkSoft  = Color(hex: 0x6B6157) // secondary text
        static let border   = Color(hex: 0x1A1714) // chunky outlines = ink

        // The six "pops" — playful primaries + Memphis accents.
        static let coral    = Color(hex: 0xFF5C5C) // primary CTA
        static let blue     = Color(hex: 0x2D5BFF) // interactive / links
        static let yellow   = Color(hex: 0xFFC93C) // highlight / streak
        static let mint      = Color(hex: 0x2FCB8A) // correct / go
        static let grape    = Color(hex: 0x8B5CF6) // category accent
        static let pink     = Color(hex: 0xFF5DA2) // category accent

        static let correct  = mint
        static let wrong    = coral

        /// The rotation used to color categories deterministically.
        static let pops: [Color] = [coral, blue, yellow, mint, grape, pink]
    }

    // MARK: - Typography
    //
    // Six levels, SF Rounded (native, playful, ten-foot legible on tvOS).
    // Refuse a seventh — refactor instead (mobile-first-density-design).

    enum TypeRamp {
        static func title(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .black, design: .rounded) }
        static let l1 = Font.system(size: 34, weight: .black,    design: .rounded) // page title
        static let l2 = Font.system(size: 22, weight: .heavy,    design: .rounded) // section
        static let l3 = Font.system(size: 18, weight: .bold,     design: .rounded) // emphasized body
        static let l4 = Font.system(size: 17, weight: .medium,   design: .rounded) // body
        static let l5 = Font.system(size: 13, weight: .semibold, design: .rounded) // caption
        static let l6 = Font.system(size: 15, weight: .bold,      design: .rounded).monospacedDigit() // tabular
    }

    // MARK: - Metrics
    enum Metric {
        static let radius: CGFloat = 18
        static let borderWidth: CGFloat = 3
        static let shadowOffset: CGFloat = 5   // hard "sticker" offset
        static let pad: CGFloat = 16
    }
}

// MARK: - Hex init

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Chunky card (hard offset shadow + thick ink border)
//
// The signature sticker-book surface. Custom by necessity — no native
// modifier produces the hard-offset 90s look — but it's one reusable
// modifier, not scattered styling (native-platform-first: exhaust then
// encapsulate).

struct ChunkyCard: ViewModifier {
    var fill: Color = Tidbits.Palette.surface
    var radius: CGFloat = Tidbits.Metric.radius
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Tidbits.Palette.border, lineWidth: Tidbits.Metric.borderWidth)
            )
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Tidbits.Palette.border)
                    .offset(x: Tidbits.Metric.shadowOffset, y: Tidbits.Metric.shadowOffset)
            )
    }
}

extension View {
    func chunkyCard(fill: Color = Tidbits.Palette.surface, radius: CGFloat = Tidbits.Metric.radius) -> some View {
        modifier(ChunkyCard(fill: fill, radius: radius))
    }
}

// MARK: - Primary button style (big, tactile, presses into its shadow)

struct ChunkyButtonStyle: ButtonStyle {
    var fill: Color = Tidbits.Palette.coral
    var textColor: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(Tidbits.TypeRamp.l3)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Tidbits.Metric.radius, style: .continuous).fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tidbits.Metric.radius, style: .continuous)
                    .strokeBorder(Tidbits.Palette.border, lineWidth: Tidbits.Metric.borderWidth)
            )
            .background(
                RoundedRectangle(cornerRadius: Tidbits.Metric.radius, style: .continuous)
                    .fill(Tidbits.Palette.border)
                    .offset(x: pressed ? 0 : Tidbits.Metric.shadowOffset,
                            y: pressed ? 0 : Tidbits.Metric.shadowOffset)
            )
            .offset(x: pressed ? Tidbits.Metric.shadowOffset : 0,
                    y: pressed ? Tidbits.Metric.shadowOffset : 0)
            .animation(.snappy(duration: 0.08), value: pressed)
    }
}
