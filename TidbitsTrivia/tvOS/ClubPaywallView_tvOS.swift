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
    @Environment(EntitlementStore.self) private var entitlement
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreKitStore.shared
    @State private var busy: String? = nil        // productID mid-purchase
    @State private var message: String? = nil
    @FocusState private var focus: PWFocus?

    private enum PWFocus: Hashable { case plan(Int), restore }

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
        .onExitCommand { dismiss() }   // Menu button leaves the paywall (modal: allowed)
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

    private var plans: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.loadFailed {
                Text("Couldn't load plans. Check your connection and try again.")
                    .font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            } else if store.products.isEmpty {
                ProgressView().tint(.white)
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
                else { Text(product.displayPrice).font(.system(size: 31, weight: .black, design: .rounded)) }
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

    /// R-MON-2 — sign in lives in Settings' Profile section, not here; never a code field.
    private var webNote: some View {
        Text("Bought Tidbits Club on the web? Sign in with the same email in Settings — it's already yours.")
            .font(.system(size: 22, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
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
