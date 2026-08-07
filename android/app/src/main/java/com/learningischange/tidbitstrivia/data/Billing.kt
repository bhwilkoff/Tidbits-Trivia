package com.learningischange.tidbitstrivia.data

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * Google Play Billing for Tidbits Club (docs/CLUB-MARKETING.md §3/§4b, MONETIZATION §6/§7).
 * Android's **Class A** — local, offline, Play-attested — source for [Entitlement]: the twin
 * of Apple's `StoreKitStore` (`Transaction.currentEntitlements`) and the Windows
 * `IStoreGateway`/`WindowsStoreGateway`. Play Billing Library 7 (`billing-ktx`), driven through
 * the plain callback API and wrapped in suspend functions so the rest of the app never touches
 * `BillingClient` directly.
 *
 * R-MON-3: Billing NEVER writes `entitlements/{key}` — that is the Worker's job after a
 * Merchant-of-Record web purchase. This object only ever pushes a LOCAL signal into
 * [Entitlement] via the `localCheck` seam installed in [start] — the same seam Apple's
 * `StoreKitStore.start()` installs on `EntitlementStore.shared.localCheck`.
 */
object Billing {
    /** The Club products (docs/CLUB-MARKETING.md §4b) — one entitlement, granted by any. */
    enum class ClubProduct(val id: String, val type: String) {
        LIFETIME("club_lifetime", BillingClient.ProductType.INAPP),
        ANNUAL("club_annual", BillingClient.ProductType.SUBS),
        MONTHLY("club_monthly", BillingClient.ProductType.SUBS),
    }

    /** A purchasable plan, ready for the paywall — product id, live Play price, and (for
     *  subscriptions) the offer token `launchPurchase` must pass back to `BillingFlowParams`. */
    data class Plan(val product: ClubProduct, val details: ProductDetails, val offerToken: String?, val formattedPrice: String)

    private val clubProductIds: Set<String> = ClubProduct.entries.map { it.id }.toSet()
    private val planOrder: Map<ClubProduct, Int> = mapOf(ClubProduct.LIFETIME to 0, ClubProduct.ANNUAL to 1, ClubProduct.MONTHLY to 2)

    private lateinit var appContext: Context
    private var client: BillingClient? = null
    // A paywall must never be able to kill the app. Play Billing throws synchronously out of
    // its *Async entry points for malformed requests, and this scope runs on Dispatchers.Main,
    // so without a handler any such throw is a process death on a screen the player did not ask
    // for — which is precisely how "All products should be of the same product type" turned a
    // monetization bug into "the app opens, but it keeps crashing" in App Review. Club going
    // dark is a bad outcome; the game dying is a rejected one. R-MON-2 already says the gate
    // fails OPEN, and this is the same principle one level down.
    private val scope = CoroutineScope(
        Dispatchers.Main + CoroutineExceptionHandler { _, t ->
            loadFailed = true
            android.util.Log.e("Billing", "billing failed; Club stays locked, app continues", t)
        },
    )

    /** The loaded plans for display, sorted lifetime -> annual -> monthly (best-value framing
     *  reads top-down), mirror of `StoreKitStore.products`. */
    var plans: List<Plan> by mutableStateOf(emptyList()); private set
    var loadFailed: Boolean by mutableStateOf(false); private set

    private val listener = PurchasesUpdatedListener { result, purchases ->
        if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            scope.launch { purchases.forEach { grantAndAcknowledge(it) } }
        }
        // USER_CANCELED / ITEM_ALREADY_OWNED / etc: nothing to grant, nothing to throw —
        // mirror of StoreKitStore.purchase()'s .cancelled / .failed outcomes.
    }

    /** Called once from the Application, right after `Entitlement.init(ctx)` — installs the
     *  local-check seam and opens the Play connection. Mirror of `StoreKitStore.start()`. */
    fun start(ctx: Context) {
        appContext = ctx.applicationContext
        Entitlement.localCheck = { localClubEntitled() }
        // Called from Application.onCreate, so an exception here is a launch-path crash on a
        // device with a missing or broken Play Store — a class of device App Review does use.
        runCatching { connect() }.onFailure {
            loadFailed = true
            android.util.Log.e("Billing", "Play Billing unavailable; Club stays locked", it)
        }
    }

    private fun connect() {
        val c = BillingClient.newBuilder(appContext)
            .setListener(listener)
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .build()
        client = c
        c.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    scope.launch { loadProducts() }
                }
            }
            override fun onBillingServiceDisconnected() {
                connect()   // reconnect; the next localClubEntitled()/loadProducts() call retries
            }
        })
    }

    /** Load the three products for display in the paywall. Safe to call again (e.g. after a
     *  reconnect); replaces `plans` wholesale. */
    private suspend fun loadProducts() {
        val c = client ?: return
        if (!c.isReady) return
        // ONE QUERY PER PRODUCT TYPE. Play Billing rejects a mixed product list with
        //   java.lang.IllegalArgumentException: All products should be of the same product type.
        // thrown synchronously, on the main thread, out of queryProductDetailsAsync. Club has a
        // one-time product (Founding Member, INAPP) and two subscriptions (SUBS), so the single
        // combined query this replaced crashed on every device with a real Play Store — while
        // passing on emulators and Test Lab VIRTUAL devices, which have no Play Billing service
        // to answer at all. That is the crash Play rejected version codes 75 and 85 for, and why
        // neither OOM fix made it go away.
        val loaded = ArrayList<ProductDetails>()
        for ((type, products) in ClubProduct.entries.groupBy { it.type }) {
            val params = QueryProductDetailsParams.newBuilder().setProductList(
                products.map { p ->
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(p.id)
                        .setProductType(type)
                        .build()
                },
            ).build()
            val (result, details) = suspendCancellableCoroutine { cont ->
                c.queryProductDetailsAsync(params) { billingResult, list -> cont.resume(billingResult to list) }
            }
            if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                loadFailed = true
                return
            }
            loaded += details
        }
        plans = loaded.mapNotNull(::toPlan).sortedBy { planOrder[it.product] ?: 9 }
        loadFailed = plans.isEmpty()
    }

    private fun toPlan(details: ProductDetails): Plan? {
        val product = ClubProduct.entries.firstOrNull { it.id == details.productId } ?: return null
        return when (product.type) {
            BillingClient.ProductType.INAPP -> {
                val offer = details.oneTimePurchaseOfferDetails ?: return null
                Plan(product, details, offerToken = null, formattedPrice = offer.formattedPrice)
            }
            else -> {
                val offer = details.subscriptionOfferDetails?.firstOrNull() ?: return null
                val phase = offer.pricingPhases.pricingPhaseList.firstOrNull() ?: return null
                Plan(product, details, offerToken = offer.offerToken, formattedPrice = phase.formattedPrice)
            }
        }
    }

    /** Buy a Club plan. The purchase result itself (grant + acknowledge) arrives asynchronously
     *  via [listener]; this just launches Play's UI. Returns false only if the flow couldn't even
     *  be launched (e.g. Billing unavailable) — mirror of `StoreKitStore.purchase`'s `.failed`. */
    fun launchPurchase(activity: Activity, productId: String): Boolean {
        val c = client ?: return false
        val plan = plans.firstOrNull { it.product.id == productId } ?: return false
        val productParams = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(plan.details)
            .apply { plan.offerToken?.let { setOfferToken(it) } }
            .build()
        val flowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(productParams))
            .build()
        val result = c.launchBillingFlow(activity, flowParams)
        return result.responseCode == BillingClient.BillingResponseCode.OK
    }

    /** Play has no separate "restore" call — re-querying owned purchases and re-granting IS
     *  restore. Mirror of `StoreKitStore.restore()`'s `AppStore.sync()` + refresh. */
    suspend fun restore() {
        val c = client ?: return
        val inapp = queryPurchases(c, BillingClient.ProductType.INAPP) ?: emptyList()
        val subs = queryPurchases(c, BillingClient.ProductType.SUBS) ?: emptyList()
        (inapp + subs).forEach { grantAndAcknowledge(it) }
        Entitlement.refresh()
    }

    // MARK: - Entitlement (Class A)

    /** The local, Play-attested Club state for `Entitlement.localCheck`. Mirrors Apple's grace
     *  semantics EXACTLY:
     *   - `true`  — an owned, acknowledged, non-expired Club purchase exists.
     *   - `false` — a clean query returned purchases (or none) but no Club purchase among them.
     *   - `null`  — unknown (service not connected / query failed) — the gate treats this as
     *               "no clean signal" and FAILS OPEN. Never returns `false` on a connection error. */
    suspend fun localClubEntitled(): Boolean? {
        val c = client ?: return null
        if (!c.isReady) return null
        val inapp = queryPurchases(c, BillingClient.ProductType.INAPP) ?: return null
        val subs = queryPurchases(c, BillingClient.ProductType.SUBS) ?: return null
        val clubPurchases = (inapp + subs).filter { purchase -> purchase.products.any { it in clubProductIds } }
        if (clubPurchases.isEmpty()) return false
        return clubPurchases.any { it.purchaseState == Purchase.PurchaseState.PURCHASED && it.isAcknowledged }
    }

    private suspend fun queryPurchases(c: BillingClient, type: String): List<Purchase>? =
        suspendCancellableCoroutine { cont ->
            val params = QueryPurchasesParams.newBuilder().setProductType(type).build()
            c.queryPurchasesAsync(params) { result, purchases ->
                if (result.responseCode == BillingClient.BillingResponseCode.OK) cont.resume(purchases)
                else cont.resume(null)
            }
        }

    /** A purchase reported OK by Play: acknowledge it (never consume — the lifetime product is
     *  DURABLE, and subscriptions are never consumable), then push the fresh local entitlement
     *  into [Entitlement]. No-ops for non-Club products. */
    private suspend fun grantAndAcknowledge(purchase: Purchase) {
        if (purchase.products.none { it in clubProductIds }) return
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) return
        if (!purchase.isAcknowledged) {
            val c = client ?: return
            val params = AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
            val result = suspendCancellableCoroutine<BillingResult> { cont ->
                c.acknowledgePurchase(params) { cont.resume(it) }
            }
            if (result.responseCode != BillingClient.BillingResponseCode.OK) return
        }
        Entitlement.refresh()
    }
}
