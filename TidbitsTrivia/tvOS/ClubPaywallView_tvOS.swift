#if os(tvOS)
import SwiftUI
import StoreKit

/// Apple TV Tidbits Club paywall — ten-foot, dark-first mirror of the iOS `ClubPaywallView`
/// (docs/CLUB-MONETIZATION-BUILD.md, MONETIZATION §4a). Reuses the SAME shared `StoreKitStore` /
/// `EntitlementStore`; only the presentation is tvOS-native — `TVTheme` dark palette,
/// focusable `TVChipStyle` plan buttons (never `.buttonStyle(.plain)`, which would kill
/// focusability), and `TVRecordsCard` for the panel chrome (shared with `RecordsView_tvOS`).
///
/// R-MON-2: purchase is via StoreKit only. There is no sign-in surface here (Settings owns
/// that) — the web note points back there, never a code/QR field.
struct ClubPaywallView_tvOS: View {
    /// Set when the paywall is shown INLINE (Settings swaps its own content rather than
    /// stacking a second `.fullScreenCover` — see `SettingsView_tvOS`). nil means "I'm a
    /// modal, dismiss me."
    var onClose: (() -> Void)? = nil

    @Environment(EntitlementStore.self) private var entitlement
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreKitStore.shared
    @State private var busy: String? = nil        // productID mid-purchase
    @State private var message: String? = nil
    @FocusState private var focus: PWFocus?

    private enum PWFocus: Hashable { case plan(Int), restore, retry }

    // The pitch (§4a "The pitch, in one sentence") — play + keep. Kept verbatim from iOS.
    private let pillars: [(String, String, String)] = [
        ("trophy.fill",        "Ranked Seasons",  "A calendar-driven climb — and it counts your live pub nights too."),
        ("map.fill",           "Knowledge Atlas", "A map of what you actually know, by domain, over time."),
        ("books.vertical.fill","Story Archive",   "Every fact you've learned, kept forever and searchable."),
        ("figure.run",         "Expeditions",     "Multi-week campaigns that turn a session game into a pursuit."),
    ]

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    hero
                    if entitlement.isClub { memberBanner } else {
                        pillarList
                        plans
                        restoreRow
                        webNote
                        legalFooter
                    }
                    if let message {
                        Text(message).font(.system(size: 25, weight: .medium, design: .rounded))
                            .foregroundStyle(TVTheme.textSoft)
                    }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onExitCommand { if let onClose { onClose() } else { dismiss() } }   // Menu leaves the paywall
        .defaultFocus($focus, .plan(0))
        .task { await store.loadProducts() }
    }

    private var hero: some View {
        TVRecordsCard(fill: Tidbits.Palette.blue, dark: false) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "star.circle.fill").font(.system(size: 60, weight: .black)).foregroundStyle(.white)
                Text("Get better, not just play more")
                    .font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text("Ranked seasons, a map of everything you know, and a library of every fact you've learned.")
                    .font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                Text("The whole game stays free. Club is the layer on top.")
                    .font(.system(size: 23, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var memberBanner: some View {
        TVRecordsCard(dark: true) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 48, weight: .black)).foregroundStyle(Tidbits.Palette.mint)
                Text("You're a Club member").font(.system(size: 36, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.text)
                Text("Thanks for backing Tidbits.").font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
        }
    }

    private var pillarList: some View {
        TVRecordsCard(dark: true) {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(pillars, id: \.1) { icon, title, blurb in
                    HStack(alignment: .top, spacing: 20) {
                        Image(systemName: icon).font(.system(size: 30, weight: .bold)).foregroundStyle(Tidbits.Palette.blue).frame(width: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.text)
                            Text(blurb).font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var plans: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.loading && store.products.isEmpty {
                ProgressView().tint(.white)
            } else if store.products.isEmpty {
                // A store that didn't answer is a RECOVERABLE state, never a dead end — the
                // retry button is what App Review 2.1(a) found missing behind the error text.
                Text(store.lastError
                     ?? (store.returnedEmpty
                         ? "The App Store hasn't published the plans for this build yet."
                         : "The App Store didn't send the plans back. This usually clears on a second try."))
                    .font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { Task { await store.loadProducts() } }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                    .focused($focus, equals: .retry)
            } else {
                ForEach(Array(store.products.enumerated()), id: \.element.id) { i, product in
                    planButton(product, index: i)
                }
            }
        }
    }

    private func planButton(_ product: StoreKit.Product, index: Int) -> some View {
        let isLifetime = product.id == StoreKitStore.Product.lifetime.rawValue
        let isAnnual = product.id == StoreKitStore.Product.annual.rawValue
        let tag = isLifetime ? "Founding Member · limited time" : (isAnnual ? "Best value" : nil)
        return Button {
            Task { await buy(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName).font(.system(size: 29, weight: .heavy, design: .rounded))
                    if let tag { Text(tag).font(.system(size: 21, weight: .semibold, design: .rounded)).opacity(0.85) }
                }
                Spacer()
                if busy == product.id { ProgressView().tint(.white) }
                else { Text(Self.priceLabel(product)).font(.system(size: 31, weight: .black, design: .rounded)) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TVChipStyle(accent: isLifetime ? Tidbits.Palette.coral : Tidbits.Palette.blue, selected: false))
        .focused($focus, equals: .plan(index))
        .disabled(busy != nil)
    }

    private var restoreRow: some View {
        Button("Restore Purchases") { Task { await store.restore(); message = entitlement.isClub ? nil : "No purchase found to restore." } }
            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
            .focused($focus, equals: .restore)
    }

    /// R-MON-2 — an existing membership unlocks by SIGNING IN (Settings → Profile), never a
    /// code field. Worded neutrally (no external-purchase steering) for App Store 3.1.3(b).
    private var webNote: some View {
        Text("Already have Tidbits Club? Sign in with the same account in Settings and it unlocks here.")
            .font(.system(size: 22, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
    }

    /// App Store 3.1.2 — auto-renew disclosure must appear next to the purchase controls.
    /// tvOS has no browser, so Terms/Privacy are cited by URL (Apple's tvOS convention) rather
    /// than as tappable links.
    private var legalFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monthly and Yearly are auto-renewable subscriptions at the prices shown above. Payment is charged to your Apple Account at purchase confirmation. Each renews automatically unless auto-renewal is turned off at least 24 hours before the current period ends; manage or cancel anytime in your Apple Account settings. Founding Member is a one-time purchase for lifetime access — it does not renew.")
                .font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            Text("Terms of Use and Privacy Policy: tidbitstrivia.com/terms.html · tidbitstrivia.com/privacy.html")
                .font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
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
        case .failed:    message = store.lastError ?? "That didn't go through. No charge was made — try again."
        }
        busy = nil
    }
}
#endif
