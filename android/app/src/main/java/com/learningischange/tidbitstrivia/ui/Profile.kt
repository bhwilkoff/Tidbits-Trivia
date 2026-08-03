package com.learningischange.tidbitstrivia.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import com.learningischange.tidbitstrivia.R
import kotlinx.coroutines.launch
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.Entitlement
import com.learningischange.tidbitstrivia.data.PlayerIdentity
import com.learningischange.tidbitstrivia.ui.theme.Pops
import kotlin.math.abs

/** The portable Tidbits identity, native Material — the Android twin of the iOS
 *  ProfileView. Reads PlayerIdentity.profile (the ONE shared cross-platform profile). */
@Composable
fun ProfileScreen(onBack: () -> Unit, onLeaderboard: () -> Unit = {}, onDuels: () -> Unit = {}, onClub: () -> Unit = {}) {
    val p = PlayerIdentity.profile
    var editing by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf("") }
    val ctx = LocalContext.current
    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
            Text("Profile", fontSize = 28.sp, fontWeight = FontWeight.Black, color = ink)
        }
        if (p == null) {
            CircularProgressIndicator(Modifier.padding(top = 80.dp))
            return@Column
        }
        Spacer(Modifier.height(12.dp))
        Box(Modifier.clickable { PlayerIdentity.rerollAvatar() }) { ProfileAvatar(p.avatarSeed, initialsOf(p.name), 96.dp) }   // L4 cosmetics
        Text("Tap your avatar to shuffle its color", fontSize = 12.sp, color = soft)
        TextButton(onClick = { draft = p.name; editing = true }) {
            Text(p.name, fontSize = 24.sp, fontWeight = FontWeight.Black, color = ink)
        }
        Spacer(Modifier.height(8.dp))

        StatRow("TIDBITS RATING", "${p.rating.value.toInt()}",
            if (p.rating.provisional) "Provisional · ${p.rating.games}/${PlayerIdentity.ESTABLISHED_AT} games"
            else "${p.rating.games} games rated", ink, soft)
        Spacer(Modifier.height(12.dp))
        StatRow("STREAK", "${p.streak.current}",
            "Longest ${p.streak.longest} · ${p.streak.freezes} freeze${if (p.streak.freezes == 1) "" else "s"}", ink, soft)
        Spacer(Modifier.height(12.dp))
        val acc = if (p.stats.questionsAnswered > 0) p.stats.correct * 100 / p.stats.questionsAnswered else 0
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatTile("Games", "${p.stats.gamesPlayed}", ink, soft, Modifier.weight(1f))
            StatTile("Accuracy", "$acc%", ink, soft, Modifier.weight(1f))
        }
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatTile("Live nights", "${p.stats.liveNights}", ink, soft, Modifier.weight(1f))
            StatTile("Venues", "${p.stats.venuesVisited}", ink, soft, Modifier.weight(1f))
        }

        Spacer(Modifier.height(14.dp))
        Button(onClick = onLeaderboard, modifier = Modifier.fillMaxWidth()) { Text("Leaderboard") }   // Wave E
        Spacer(Modifier.height(8.dp))
        Button(onClick = onDuels, modifier = Modifier.fillMaxWidth()) { Text("Duels") }   // L5 async friend duels
        Spacer(Modifier.height(8.dp))
        Button(
            onClick = onClub, modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = if (Entitlement.isClub) MaterialTheme.colorScheme.surfaceVariant else Pops.yellow,
                contentColor = ink,
            ),
        ) {
            Icon(Icons.Filled.Star, null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(if (Entitlement.isClub) "Tidbits Club — Member" else "Join Tidbits Club", fontWeight = FontWeight.Bold)
        }

        Spacer(Modifier.height(18.dp))
        val scope = rememberCoroutineScope()
        val context = LocalContext.current
        val webClientId = stringResource(R.string.tidbits_web_client_id)
        if (PlayerIdentity.signedIn) {
            Text("✓ Signed in — your records sync to every device", color = soft, fontSize = 14.sp,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            TextButton(onClick = { scope.launch { runCatching { PlayerIdentity.signOut() } } },
                modifier = Modifier.fillMaxWidth()) { Text("Sign out") }
        } else if (webClientId != "TODO_ENABLE_GOOGLE_IN_FIREBASE") {
            Text("Save your progress", fontSize = 18.sp, fontWeight = FontWeight.Black, color = ink)
            Text("Sign in so your records follow you to any device.", color = soft, fontSize = 13.sp,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            Button(onClick = {
                scope.launch {
                    runCatching { PlayerIdentity.linkGoogle(context, webClientId) }
                        .onFailure {
                            android.util.Log.e("Identity", "Google sign-in failed", it)
                            android.widget.Toast.makeText(context, "Sign-in didn’t complete: ${it.message ?: it.javaClass.simpleName}", android.widget.Toast.LENGTH_LONG).show()
                        }
                }
            }, modifier = Modifier.fillMaxWidth()) { Text("Continue with Google", fontWeight = FontWeight.Bold) }
        }

        // Account deletion sits with the account, on every platform. Shown whether or not
        // the player signed in — the anonymous account IS an account, and it holds their
        // rating, streak and board rows.
        Spacer(Modifier.height(10.dp))
        TextButton(onClick = { confirmDelete = true }, modifier = Modifier.fillMaxWidth()) {
            Text("Delete account", color = Pops.coral)
        }
    }

    if (confirmDelete) {
        val store = remember(ctx) { com.learningischange.tidbitstrivia.data.Store(ctx) }
        DeleteAccountConfirm(store) { confirmDelete = false }
    }

    if (editing) {
        AlertDialog(
            onDismissRequest = { editing = false },
            title = { Text("Display name") },
            text = {
                OutlinedTextField(value = draft, onValueChange = { draft = it }, singleLine = true,
                    label = { Text("Name") })
            },
            confirmButton = { TextButton(onClick = { PlayerIdentity.rename(draft); editing = false }) { Text("Save") } },
            dismissButton = { TextButton(onClick = { editing = false }) { Text("Cancel") } })
    }
}

@Composable
private fun StatRow(label: String, value: String, sub: String, ink: Color, soft: Color) {
    Row(
        Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(16.dp)).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(label, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = soft)
            Text(sub, fontSize = 12.sp, color = soft)
        }
        Text(value, fontSize = 38.sp, fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace, color = ink)
    }
}

@Composable
private fun StatTile(label: String, value: String, ink: Color, soft: Color, modifier: Modifier = Modifier) {
    Column(
        modifier.background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(16.dp)).padding(vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, fontSize = 26.sp, fontWeight = FontWeight.Black, color = ink)
        Text(label.uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Bold, color = soft)
    }
}

@Composable
fun ProfileAvatar(seed: String, initials: String, size: Dp) {
    val stable = seed.fold(5381) { h, c -> h * 33 + c.code }        // djb2 — stable, matches iOS
    val hue = (abs(stable) % 360).toFloat()
    Box(
        Modifier.size(size).background(Color.hsv(hue, 0.55f, 0.85f), CircleShape)
            .border(3.dp, MaterialTheme.colorScheme.onSurface, CircleShape),
        contentAlignment = Alignment.Center
    ) {
        Text(initials, fontSize = (size.value / 2.8f).sp, fontWeight = FontWeight.Black,
            color = MaterialTheme.colorScheme.onSurface)
    }
}

fun initialsOf(name: String): String {
    val parts = name.trim().split(" ").filter { it.isNotEmpty() }.take(2)
    val s = parts.mapNotNull { it.firstOrNull() }.joinToString("")
    return if (s.isEmpty()) "?" else s.uppercase()
}
