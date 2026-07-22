package com.learningischange.tidbitstrivia.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.Billing
import com.learningischange.tidbitstrivia.data.Entitlement
import com.learningischange.tidbitstrivia.ui.theme.Pops
import kotlinx.coroutines.launch

// The four pillars (CLUB-MARKETING.md §2), verbatim — order is deliberate: two play
// reasons, two keep reasons. Android twin of ClubPaywallView.swift's `pillars`.
private data class Pillar(val icon: ImageVector, val title: String, val blurb: String)

private val pillars = listOf(
    Pillar(Icons.Filled.EmojiEvents, "Ranked Seasons", "A calendar-driven climb — and it counts your live pub nights too."),
    Pillar(Icons.Filled.Map, "Knowledge Atlas", "A map of what you actually know, by domain, over time."),
    Pillar(Icons.Filled.AutoStories, "Story Archive", "Every fact you've learned, kept forever and searchable."),
    Pillar(Icons.AutoMirrored.Filled.DirectionsRun, "Expeditions", "Multi-week campaigns that turn a session game into a pursuit."),
)

private fun planLabel(p: Billing.ClubProduct) = when (p) {
    Billing.ClubProduct.LIFETIME -> "Founding Member (Lifetime)"
    Billing.ClubProduct.ANNUAL -> "Tidbits Club (Yearly)"
    Billing.ClubProduct.MONTHLY -> "Tidbits Club (Monthly)"
}

private fun planTag(p: Billing.ClubProduct): String? = when (p) {
    Billing.ClubProduct.LIFETIME -> "Founding Member · limited time"
    Billing.ClubProduct.ANNUAL -> "Best value"
    Billing.ClubProduct.MONTHLY -> null
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/** The Tidbits Club join surface (docs/CLUB-MARKETING.md, MONETIZATION §4a/§6). Sells the
 *  tier without ever gating the free game — reachable from Profile, never an interstitial.
 *  Doubles as the marketing/explanation of what Club is. Android twin of ClubPaywallView.swift.
 *
 *  R-MON-2: purchase is via Play Billing only; the "already bought on the web?" path is
 *  **sign in**, never a code/QR field. */
@Composable
fun ClubPaywallScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    val scope = rememberCoroutineScope()
    var busyProductId by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)

    LaunchedEffect(Unit) { message = null }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
            Text("Tidbits Club", fontSize = 26.sp, fontWeight = FontWeight.Black, color = ink)
        }

        Hero(ink, soft)

        if (Entitlement.isClub) {
            MemberBanner(soft)
        } else {
            PillarList(soft)
            Plans(activity, busyProductId,
                onBuy = { productId ->
                    if (activity != null) {
                        busyProductId = productId
                        message = null
                        val launched = Billing.launchPurchase(activity, productId)
                        if (!launched) { message = "That didn't go through. No charge was made — try again."; busyProductId = null }
                        // On success the PurchasesUpdatedListener grants + acknowledges async;
                        // clear the busy state once isClub flips (or after a beat either way).
                    }
                })
            TextButton(onClick = {
                scope.launch {
                    Billing.restore()
                    message = if (Entitlement.isClub) null else "No purchase found to restore."
                }
            }) { Text("Restore Purchases", color = Pops.blue) }
            Text("Bought Tidbits Club on the web? Sign in with the same email — it's already yours.",
                fontSize = 12.sp, color = soft, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }

        // A purchase resolves isClub -> clear any pending spinner once it lands.
        if (busyProductId != null && Entitlement.isClub) busyProductId = null

        message?.let { Text(it, fontSize = 12.sp, color = soft, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun Hero(ink: Color, soft: Color) {
    ChunkyCard(fill = Pops.blue.copy(alpha = 0.14f)) {
        Column(Modifier.padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Filled.Star, null, tint = Pops.blue, modifier = Modifier.height(44.dp).width(44.dp))
            Spacer(Modifier.height(8.dp))
            Text("Get better, not just play more", fontSize = 22.sp, fontWeight = FontWeight.Black,
                color = ink, textAlign = TextAlign.Center)
            Spacer(Modifier.height(6.dp))
            Text("Ranked seasons, a map of everything you know, and a library of every fact you've learned.",
                fontSize = 14.sp, color = soft, textAlign = TextAlign.Center)
            Spacer(Modifier.height(4.dp))
            Text("The whole game stays free. Club is the layer on top.", fontSize = 12.sp, color = soft)
        }
    }
}

@Composable
private fun MemberBanner(soft: Color) {
    ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant) {
        Column(Modifier.padding(20.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Filled.CheckCircle, null, tint = Pops.mint, modifier = Modifier.height(36.dp).width(36.dp))
            Spacer(Modifier.height(6.dp))
            Text("You're a Club member", fontSize = 20.sp, fontWeight = FontWeight.Black)
            Text("Thanks for backing Tidbits.", fontSize = 13.sp, color = soft)
        }
    }
}

@Composable
private fun PillarList(soft: Color) {
    ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant) {
        Column(Modifier.padding(16.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            pillars.forEach { pillar ->
                Row(verticalAlignment = Alignment.Top) {
                    Icon(pillar.icon, null, tint = Pops.blue, modifier = Modifier.width(26.dp).height(20.dp))
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text(pillar.title, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                        Text(pillar.blurb, fontSize = 12.sp, color = soft)
                    }
                }
            }
        }
    }
}

@Composable
private fun Plans(activity: Activity?, busyProductId: String?, onBuy: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        when {
            Billing.loadFailed -> Text("Couldn't load plans. Check your connection and try again.",
                fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Billing.plans.isEmpty() -> CircularProgressIndicator(Modifier.padding(12.dp))
            else -> Billing.plans.forEach { plan ->
                val isLifetime = plan.product == Billing.ClubProduct.LIFETIME
                Button(
                    onClick = { onBuy(plan.product.id) },
                    enabled = activity != null && busyProductId == null,
                    modifier = Modifier.fillMaxWidth().height(64.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (isLifetime) Pops.coral else Pops.blue,
                        contentColor = Color.White,
                    ),
                ) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(planLabel(plan.product), fontWeight = FontWeight.Bold, fontSize = 16.sp, color = Color.White)
                            planTag(plan.product)?.let { Text(it, fontSize = 11.sp, color = Color.White.copy(alpha = 0.85f)) }
                        }
                        if (busyProductId == plan.product.id) {
                            CircularProgressIndicator(Modifier.height(20.dp).width(20.dp), color = Color.White)
                        } else {
                            Text(plan.formattedPrice, fontWeight = FontWeight.Black, fontSize = 18.sp, color = Color.White)
                        }
                    }
                }
            }
        }
    }
}
