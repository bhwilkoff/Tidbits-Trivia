#if os(iOS)
import SwiftUI
import StoreKit

/// The Tidbits Club join surface (docs/CLUB-MONETIZATION-BUILD.md, MONETIZATION §4a). Sells
/// the tier without ever gating the free game — reachable from Profile, never an
/// interstitial. Doubles as the marketing/explanation of what Club is.
///
/// R-MON-2: purchase is via StoreKit only; the "already bought on the web?" path is
/// **sign in**, never a code/QR field.
struct ClubPaywallView: View {
    @Environment(EntitlementStore.self) private var entitlement
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreKitStore.shared
    @State private var busy: String? = nil        // productID mid-purchase
    @State private var message: String? = nil

    // The pitch (§4a "The pitch, in one sentence") — play + keep.
    private let pillars: [(String, String, String)] = [
        ("trophy.fill",        "Ranked Seasons",  "A calendar-driven climb — and it counts your live pub nights too."),
        ("map.fill",           "Knowledge Atlas", "A map of what you actually know, by domain, over time."),
        ("books.vertical.fill","Story Archive",   "Every fact you've learned, kept forever and searchable."),
        ("figure.run",         "Expeditions",     "Multi-week campaigns that turn a session game into a pursuit."),
        ("square.grid.3x3.fill","Link Wall",      "A second daily — 16 facts, 4 hidden groups, one shareable puzzle."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    if entitlement.isClub { memberBanner } else { pillarList; plans; restoreRow; webNote; legalFooter }
                    if let message { Text(message).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).multilineTextAlignment(.center) }
                }
                .padding(Tidbits.Metric.pad)
                .padding(.vertical, 20)
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationTitle("Tidbits Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await store.loadProducts() }
        }
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.circle.fill").font(.system(size: 52)).foregroundStyle(Tidbits.Palette.blue)
            Text("Get better, not just play more").font(Tidbits.TypeRamp.l1).multilineTextAlignment(.center).foregroundStyle(Tidbits.Palette.ink)
            Text("Ranked seasons, a map of everything you know, and a library of every fact you've learned.")
                .font(Tidbits.TypeRamp.l4).multilineTextAlignment(.center).foregroundStyle(Tidbits.Palette.inkSoft)
            Text("The whole game stays free. Club is the layer on top.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(20).chunkyCard(fill: Tidbits.Palette.blue.opacity(0.12))
    }

    private var memberBanner: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(Tidbits.Palette.mint)
            Text("You're a Club member").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("Thanks for backing Tidbits.").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(20).chunkyCard(fill: Tidbits.Palette.surface)
    }

    private var pillarList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(pillars, id: \.1) { icon, title, blurb in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Tidbits.Palette.blue).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Text(blurb).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).chunkyCard(fill: Tidbits.Palette.surface)
    }

    private var plans: some View {
        VStack(spacing: 12) {
            if store.loadFailed {
                Text("Couldn't load plans. Check your connection and try again.")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).multilineTextAlignment(.center).padding()
            } else if store.products.isEmpty {
                ProgressView().padding()
            } else {
                ForEach(store.products, id: \.id) { product in planButton(product) }
            }
        }
    }

    private func planButton(_ product: StoreKit.Product) -> some View {
        let isLifetime = product.id == StoreKitStore.Product.lifetime.rawValue
        let isAnnual = product.id == StoreKitStore.Product.annual.rawValue
        let tag = isLifetime ? "Founding Member · limited time" : (isAnnual ? "Best value" : nil)
        return Button {
            Task { await buy(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(Tidbits.TypeRamp.l3).foregroundStyle(.white)
                    if let tag { Text(tag).font(Tidbits.TypeRamp.l5).foregroundStyle(.white.opacity(0.85)) }
                }
                Spacer()
                if busy == product.id { ProgressView().tint(.white) }
                else { Text(Self.priceLabel(product)).font(Tidbits.TypeRamp.l2).foregroundStyle(.white) }
            }
            .padding(16).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Tidbits.Metric.radius).fill(isLifetime ? Tidbits.Palette.coral : Tidbits.Palette.blue))
            .overlay(RoundedRectangle(cornerRadius: Tidbits.Metric.radius).strokeBorder(Tidbits.Palette.border, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .disabled(busy != nil)
    }

    private var restoreRow: some View {
        Button("Restore Purchases") { Task { await store.restore(); message = entitlement.isClub ? nil : "No purchase found to restore." } }
            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.blue)
    }

    /// R-MON-2 — an existing membership unlocks by SIGNING IN, never a code field. Worded
    /// neutrally (no external-purchase steering) for App Store 3.1.3(b).
    private var webNote: some View {
        Text("Already have Tidbits Club? Sign in with the same account and it unlocks here.")
            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).multilineTextAlignment(.center)
    }

    /// App Store 3.1.2 — auto-renew disclosure + functional Terms of Use (EULA) and Privacy
    /// Policy links must appear in the binary next to the purchase controls.
    private var legalFooter: some View {
        VStack(spacing: 10) {
            Text("Monthly and Yearly are auto-renewable subscriptions at the prices shown above. Payment is charged to your Apple Account at purchase confirmation. Each renews automatically unless auto-renewal is turned off at least 24 hours before the current period ends; manage or cancel anytime in your Apple Account settings. Founding Member is a one-time purchase for lifetime access — it does not renew.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Link("Terms of Use", destination: URL(string: "https://tidbitstrivia.com/terms.html")!)
                Link("Privacy Policy", destination: URL(string: "https://tidbitstrivia.com/privacy.html")!)
            }
            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.blue)
        }
        .padding(.top, 4)
    }

    /// Price with billing period for subscriptions (e.g. "$29.99/yr"); the raw price for the
    /// one-time lifetime product. Apple requires the period be shown before purchase.
    static func priceLabel(_ product: StoreKit.Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        let unit: String
        switch period.unit {
        case .day: unit = "day"; case .week: unit = "wk"; case .month: unit = "mo"; case .year: unit = "yr"
        @unknown default: return product.displayPrice
        }
        return "\(product.displayPrice)/\(unit)"
    }

    private func buy(_ product: StoreKit.Product) async {
        busy = product.id; message = nil
        switch await store.purchase(product) {
        case .success:   message = nil
        case .pending:   message = "Your purchase is pending approval. Club unlocks once it's approved."
        case .cancelled: break
        case .failed:    message = "That didn't go through. No charge was made — try again."
        }
        busy = nil
    }
}
#endif
