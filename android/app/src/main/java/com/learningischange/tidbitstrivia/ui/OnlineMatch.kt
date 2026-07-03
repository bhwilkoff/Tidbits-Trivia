package com.learningischange.tidbitstrivia.ui

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
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.Category
import com.learningischange.tidbitstrivia.data.Corpus
import com.learningischange.tidbitstrivia.data.Mode
import com.learningischange.tidbitstrivia.data.Question
import com.learningischange.tidbitstrivia.data.Store
import com.learningischange.tidbitstrivia.net.FirebaseNet
import com.learningischange.tidbitstrivia.net.WireQuestion
import com.learningischange.tidbitstrivia.net.toQuestion
import com.learningischange.tidbitstrivia.net.toWire
import com.learningischange.tidbitstrivia.ui.theme.Ink
import com.learningischange.tidbitstrivia.ui.theme.Pops
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

private val onlineJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

/**
 * Online Quick Match (Decision 040) — the Android screen. Same-questions race:
 * a leader publishes the shared set, everyone plays it locally and self-reports
 * their score, standings from the live roster. Mirrors the web OnlineMatch.
 */
@Composable
fun OnlineMatchScreen(store: Store, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    var phase by remember { mutableStateOf("connecting") }   // connecting | lobby | playing | finished | error
    var error by remember { mutableStateOf<String?>(null) }
    var roomId by remember { mutableStateOf<String?>(null) }
    var isLeader by remember { mutableStateOf(false) }
    var roster by remember { mutableStateOf<Map<String, FirebaseNet.Player>>(emptyMap()) }
    var meta by remember { mutableStateOf<Map<String, Any?>>(emptyMap()) }
    var game by remember { mutableStateOf<GameState?>(null) }
    val name = remember { store.lastPlayerName().ifBlank { "Player" } }

    DisposableEffect(Unit) {
        var unsubRoster: (() -> Unit)? = null
        var unsubMeta: (() -> Unit)? = null
        scope.launch {
            try {
                val m = FirebaseNet.quickMatch(name)
                roomId = m.roomId; isLeader = m.isLeader; phase = "lobby"
                unsubRoster = FirebaseNet.onRoster(m.roomId) { roster = it }
                unsubMeta = FirebaseNet.onMeta(m.roomId) { meta = it }
            } catch (e: Exception) {
                error = if ((e.message ?: "").contains("CONFIGURATION_NOT_FOUND", true) ||
                    (e.message ?: "").contains("disabled", true))
                    "Online play needs Anonymous sign-in enabled in Firebase (owner setup)."
                else "Couldn't reach the match server. Check your connection."
                phase = "error"
            }
        }
        onDispose { unsubRoster?.invoke(); unsubMeta?.invoke(); roomId?.let { FirebaseNet.leave(it) } }
    }

    // React to meta state changes (leader started → everyone plays the shared set).
    LaunchedEffect(meta["state"], meta["questions"]) {
        val state = meta["state"] as? String
        val qJson = meta["questions"] as? String
        if (state == "playing" && game == null && qJson != null) {
            val qs = runCatching { onlineJson.decodeFromString<List<WireQuestion>>(qJson).map { it.toQuestion() } }.getOrDefault(emptyList())
            if (qs.isNotEmpty()) {
                game = GameState(Mode.MIX, Category.byId("mixed"), store, custom = qs, label = "Online Match").also { it.start() }
                phase = "playing"
            }
        }
        if (state == "finished" && phase != "finished") phase = "finished"
    }

    // Report score live during play + at the end.
    LaunchedEffect(game?.index, game?.phase) {
        val g = game ?: return@LaunchedEffect
        val rid = roomId ?: return@LaunchedEffect
        if (g.phase == GamePhase.REVEAL) FirebaseNet.reportScore(rid, g.score, false)
        if (g.phase == GamePhase.FINISHED) {
            FirebaseNet.reportScore(rid, g.score, true)
            if (isLeader) FirebaseNet.setMeta(rid, mapOf("state" to "finished"))
            phase = "finished"
        }
    }

    when (phase) {
        "connecting" -> Center { CircularProgressIndicator(); Spacer(Modifier.height(12.dp)); Text("Finding a match…") }
        "error" -> Center {
            Text("Couldn't start online play", fontWeight = FontWeight.Black, fontSize = 22.sp)
            Spacer(Modifier.height(8.dp)); Text(error ?: "", textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Spacer(Modifier.height(16.dp)); Button(onClick = onDone) { Text("Back") }
        }
        "lobby" -> OnlineLobby(roomId ?: "", isLeader, roster, onStart = {
            scope.launch {
                val rid = roomId ?: return@launch
                val qs = Corpus.pull("mixed", emptySet(), 8).map { it.toWire() }
                FirebaseNet.setMeta(rid, mapOf(
                    "state" to "playing", "startedAt" to System.currentTimeMillis(),
                    "questions" to onlineJson.encodeToString(qs),
                ))
            }
        }, onLeave = onDone)
        "playing" -> game?.let { PlayingScreen(it, onlineRoster = roster) } ?: Center { CircularProgressIndicator() }
        "finished" -> OnlineStandings(roster, onDone = onDone)
    }
}

@Composable
private fun Center(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally, content = content)
}

@Composable
private fun OnlineLobby(roomId: String, isLeader: Boolean, roster: Map<String, FirebaseNet.Player>,
                        onStart: () -> Unit, onLeave: () -> Unit) {
    val enough = roster.size >= 2
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Online Match", fontSize = 30.sp, fontWeight = FontWeight.Black)
        Text(if (enough) "Ready when you are." else "Waiting for another player to join…",
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        ChunkyCard(fill = MaterialTheme.colorScheme.surface) {
            Column(Modifier.padding(16.dp)) {
                Text("ROOM CODE", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                Text(roomId, fontSize = 34.sp, fontWeight = FontWeight.Black, letterSpacing = 4.sp)
                Text("Share this code, or wait for a random opponent.", fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
        Text("${roster.size} in the room", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        roster.forEach { (uid, p) ->
            ChunkyCard(fill = MaterialTheme.colorScheme.surface) {
                Text("${p.name}${if (uid == FirebaseNet.uid) " (you)" else ""}", Modifier.padding(14.dp), fontWeight = FontWeight.Bold)
            }
        }
        if (isLeader) {
            Button(onClick = onStart, enabled = enough, modifier = Modifier.fillMaxWidth().height(52.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) {
                Text("Start the Match", fontWeight = FontWeight.Bold)
            }
        } else {
            ChunkyCard(fill = MaterialTheme.colorScheme.surface) {
                Text("Waiting for the host to start…", Modifier.padding(14.dp),
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
        TextButton(onClick = onLeave) { Text("Leave") }
    }
}

@Composable
private fun OnlineStandings(roster: Map<String, FirebaseNet.Player>, onDone: () -> Unit) {
    val ranked = roster.entries.sortedByDescending { it.value.score }
    val won = ranked.firstOrNull()?.key == FirebaseNet.uid
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(20.dp))
        Text(if (won) "You won! 🎉" else "${ranked.firstOrNull()?.value?.name ?: "Opponent"} takes it",
            fontSize = 28.sp, fontWeight = FontWeight.Black)
        ranked.forEachIndexed { i, e ->
            ChunkyCard(fill = if (i == 0) Pops.yellow else MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("${e.value.name}${if (e.key == FirebaseNet.uid) " (you)" else ""}",
                        fontWeight = FontWeight.Bold, fontSize = 17.sp, color = if (i == 0) Ink else MaterialTheme.colorScheme.onSurface)
                    Spacer(Modifier.weight(1f))
                    Text("${e.value.score}", fontWeight = FontWeight.Black, fontSize = 22.sp, color = if (i == 0) Ink else MaterialTheme.colorScheme.onSurface)
                }
            }
        }
        TextButton(onClick = onDone) { Text("Done") }
    }
}
