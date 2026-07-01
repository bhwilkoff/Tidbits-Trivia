package com.learningischange.tidbitstrivia.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.Store
import com.learningischange.tidbitstrivia.net.NightPlayer
import com.learningischange.tidbitstrivia.ui.theme.Ink
import com.learningischange.tidbitstrivia.ui.theme.Pops
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// The networked Trivia Night surface (Decision 033): lobby -> live game -> standings.
// Reuses PlayingScreen for the question; adds the standings strip + host controls.
@Composable
fun NightContainer(live: LiveNight, store: Store, onExit: () -> Unit) {
    when (live.stage) {
        LiveNight.Stage.LOBBY ->
            if (live.role == LiveNight.Role.HOST) HostLobby(live, onExit) else JoinerWaiting(live, onExit)
        LiveNight.Stage.PLAYING -> NightPlaying(live, onExit)
        LiveNight.Stage.FINISHED -> NightStandings(live, onExit)
    }
}

@Composable
private fun HostLobby(live: LiveNight, onExit: () -> Unit) {
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth()) {
            TextButton(onClick = onExit) { Text("Cancel", color = Pops.coral, fontWeight = FontWeight.Bold) }
        }
        Text("Trivia Night", fontWeight = FontWeight.Black, fontSize = 26.sp)
        Text("Others join with this code:", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        NightCard(fill = Pops.coral) {
            Text(live.roomCode, Modifier.padding(vertical = 22.dp, horizontal = 40.dp),
                fontWeight = FontWeight.Black, fontSize = 56.sp, color = Color.White)
        }
        Text("On the same Wi-Fi. Apple or Android — same code.", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), textAlign = TextAlign.Center)
        Roster(live.players, live.leaderSeat)
        Button(onClick = { scope.launch { live.startNight() } }, modifier = Modifier.fillMaxWidth().height(54.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Ink, contentColor = Color.White)) {
            Text("Start the Night", fontWeight = FontWeight.Bold, fontSize = 17.sp)
        }
    }
}

@Composable
private fun JoinerWaiting(live: LiveNight, onExit: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        val joined = live.mySeat != null
        if (!joined) CircularProgressIndicator()
        Spacer(Modifier.height(16.dp))
        Text(
            if (joined) "You're in!" else "Looking for the room…",
            fontWeight = FontWeight.Black, fontSize = 24.sp, textAlign = TextAlign.Center,
        )
        Text(
            if (joined) "Waiting for the host to start." else (live.clientStatus?.name ?: "Searching the Wi-Fi"),
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), textAlign = TextAlign.Center,
        )
        if (joined) { Spacer(Modifier.height(20.dp)); Roster(live.players, live.leaderSeat) }
        Spacer(Modifier.height(20.dp))
        TextButton(onClick = onExit) { Text("Leave") }
    }
}

@Composable
private fun NightPlaying(live: LiveNight, onExit: () -> Unit) {
    val game = live.game ?: return
    var confirmLeave by remember { mutableStateOf(false) }
    // Drive the per-question clock locally (host paces reveal/advance).
    LaunchedEffect(game.index, game.phase, game.awaitingReveal) {
        while (game.phase == GamePhase.PLAYING && !game.awaitingReveal) { delay(100); game.tick() }
    }
    val host = live.role == LiveNight.Role.HOST
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = 4.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { confirmLeave = true }) {
                Text(if (host) "End night" else "Leave", color = Pops.coral, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.weight(1f))
        }
        if (live.reconnecting) {
            Surface(color = Pops.yellow.copy(alpha = 0.9f), modifier = Modifier.fillMaxWidth()) {
                Text("Reconnecting…", Modifier.padding(vertical = 6.dp), textAlign = TextAlign.Center,
                    fontWeight = FontWeight.Bold, color = Ink)
            }
        }
        StandingsStrip(live.players, live.mySeat, live.leaderSeat)
        Box(Modifier.weight(1f)) { PlayingScreen(game) }
        if (host) HostControls(live)
    }
    if (confirmLeave) {
        AlertDialog(
            onDismissRequest = { confirmLeave = false },
            title = { Text(if (host) "End the night?" else "Leave the night?") },
            text = { Text(if (host) "This ends the night for everyone." else "You'll drop out; the others keep playing.") },
            confirmButton = { TextButton(onClick = { confirmLeave = false; onExit() }) { Text(if (host) "End" else "Leave", color = Pops.coral) } },
            dismissButton = { TextButton(onClick = { confirmLeave = false }) { Text("Keep playing") } },
        )
    }
}

@Composable
private fun HostControls(live: LiveNight) {
    val game = live.game ?: return
    Surface(tonalElevation = 3.dp, shadowElevation = 8.dp) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (game.phase == GamePhase.REVEAL) {
                val last = game.index + 1 >= game.questions.size
                Button(onClick = { live.next() }, modifier = Modifier.fillMaxWidth().height(50.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Ink, contentColor = Color.White)) {
                    Text(if (last) "Finish the Night" else "Next question", fontWeight = FontWeight.Bold)
                }
            } else {
                Text("${live.answeredCount} of ${live.players.size} answered", fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                Button(onClick = { live.reveal() }, modifier = Modifier.fillMaxWidth().height(50.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) {
                    Text("Reveal the answer", fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun NightStandings(live: LiveNight, onExit: () -> Unit) {
    val ranked = live.players.sortedByDescending { it.score }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        val winner = ranked.firstOrNull()
        Text(if (winner != null) "🏆 ${winner.name} wins!" else "That's a wrap", fontWeight = FontWeight.Black, fontSize = 26.sp, textAlign = TextAlign.Center)
        ranked.forEachIndexed { rank, p ->
            NightCard(fill = if (rank == 0) Pops.yellow.copy(alpha = 0.25f) else MaterialTheme.colorScheme.surface) {
                Row(Modifier.padding(16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("${rank + 1}", fontWeight = FontWeight.Black, fontSize = 20.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    Text(p.name + if (p.isHost) " · host" else "", fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.weight(1f))
                    Text("${p.score}", fontWeight = FontWeight.Black, fontSize = 22.sp)
                }
            }
        }
        Button(onClick = onExit, modifier = Modifier.fillMaxWidth()) { Text("Done") }
    }
}

// ---- Shared bits ----

@Composable
private fun Roster(players: List<NightPlayer>, leaderSeat: Int?) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("In the room (${players.size})", fontWeight = FontWeight.Bold, fontSize = 15.sp)
        players.forEach { p ->
            NightCard {
                Row(Modifier.padding(horizontal = 14.dp, vertical = 12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.size(28.dp).background(Pops.at(p.seat), CircleShape))
                    Text(p.name + if (p.isHost) " · host" else "", fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    if (p.seat == leaderSeat) Icon(Icons.Filled.EmojiEvents, "Leader", modifier = Modifier.size(16.dp), tint = Pops.yellow)
                }
            }
        }
    }
}

@Composable
private fun StandingsStrip(players: List<NightPlayer>, mySeat: Int?, leaderSeat: Int?) {
    LazyRow(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(players.sortedByDescending { it.score }) { p ->
            val mine = p.seat == mySeat
            Surface(shape = RoundedCornerShape(999.dp), color = if (mine) Pops.blue else MaterialTheme.colorScheme.surface, border = BorderStroke(2.dp, Ink)) {
                Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (p.seat == leaderSeat) Icon(Icons.Filled.EmojiEvents, "Leader", modifier = Modifier.size(13.dp), tint = Pops.yellow)
                    Text(p.name, fontWeight = FontWeight.Bold, fontSize = 13.sp, color = if (mine) Color.White else MaterialTheme.colorScheme.onSurface)
                    Text("${p.score}", fontWeight = FontWeight.Black, fontSize = 13.sp, color = if (mine) Color.White else MaterialTheme.colorScheme.onSurface)
                }
            }
        }
    }
}

@Composable
private fun NightCard(fill: Color = Color.Unspecified, content: @Composable () -> Unit) {
    val c = if (fill == Color.Unspecified) MaterialTheme.colorScheme.surface else fill
    Surface(shape = RoundedCornerShape(18.dp), color = c, border = BorderStroke(2.5.dp, Ink), modifier = Modifier.fillMaxWidth()) { content() }
}
