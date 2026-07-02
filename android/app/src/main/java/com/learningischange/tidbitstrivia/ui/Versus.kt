package com.learningischange.tidbitstrivia.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Public
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.ui.theme.Ink
import com.learningischange.tidbitstrivia.ui.theme.Pops
import com.learningischange.tidbitstrivia.ui.theme.accentText
import com.learningischange.tidbitstrivia.data.BotAnswer
import com.learningischange.tidbitstrivia.data.BotProfile
import com.learningischange.tidbitstrivia.data.Bots
import com.learningischange.tidbitstrivia.data.Category
import com.learningischange.tidbitstrivia.data.Mode
import com.learningischange.tidbitstrivia.data.Question
import com.learningischange.tidbitstrivia.data.Scoring
import com.learningischange.tidbitstrivia.data.Store
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

/**
 * Play vs CPU (Decision 038) — the online-multiplayer v0. Mirrors iOS's
 * VersusContainerView: a normal classic game with a bot resolving the same
 * questions; standings strip in play, outcome line in the reveal, final
 * standings at the end. Bots are ALWAYS labeled CPU.
 */

/** Compose-state twin of iOS's BotMatch (resolve at begin, commit at reveal). */
class VsMatch(bots: List<BotProfile>) {
    data class Seat(val bot: BotProfile, val score: Int = 0, val streak: Int = 0, val lastCorrect: Boolean? = null)

    var seats by mutableStateOf(bots.map { Seat(it) })
        private set
    var pending by mutableStateOf<List<BotAnswer>>(emptyList())
        private set
    private var committedIndex = -1

    fun beginQuestion(q: Question, window: Double) {
        pending = seats.map { Bots.resolve(it.bot, q.categoryId, q.difficulty, q.correctIndex, q.options.size, window) }
    }

    fun commit(q: Question, index: Int, budget: Double) {
        if (index == committedIndex) return
        committedIndex = index
        seats = seats.map { seat ->
            val a = pending.firstOrNull { it.botId == seat.bot.id } ?: return@map seat
            val correct = a.choiceIndex == q.correctIndex
            if (correct) {
                val streak = seat.streak + 1
                seat.copy(streak = streak, lastCorrect = true,
                    score = seat.score + Scoring.points(true, a.seconds ?: budget, budget, streak))
            } else seat.copy(streak = 0, lastCorrect = false)
        }
    }

    val standings: List<Seat> get() = seats.sortedByDescending { it.score }
}

/** The honest label: every bot is visibly CPU, everywhere. */
@Composable
fun CpuTag(tint: Color = Color.White) {
    Surface(color = tint.copy(alpha = 0.25f), shape = RoundedCornerShape(999.dp)) {
        Text("CPU", Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
            fontSize = 10.sp, fontWeight = FontWeight.Black)
    }
}

/** Home surface: Quick Match (honest v1 slot) + the four CPU opponents. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MultiplayerSheet(store: Store, onDismiss: () -> Unit, onPickBot: (String) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Online Multiplayer", fontWeight = FontWeight.Black, fontSize = 26.sp)
            Text("Face an opponent on the same questions — fastest correct answers win.",
                fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))

            Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surface,
                border = BorderStroke(2.dp, MaterialTheme.colorScheme.outline)) {
                Row(Modifier.padding(14.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Public, null, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text("Quick Match", fontWeight = FontWeight.Bold)
                        Text("Matchmaking with real players — coming soon", fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                }
            }

            Text("Play a CPU opponent now", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            BotRow(Bots.house(recentAccuracy(store)), "Adapts to how you've been playing — a fair fight", Pops.coral) { onPickBot("house") }
            BotRow(Bots.rookie, "Takes it easy. Strong on sports and film", Pops.mint) { onPickBot("rookie") }
            BotRow(Bots.regular, "A solid all-rounder. Loves history", Pops.blue) { onPickBot("regular") }
            BotRow(Bots.ace, "Fast and sharp. Science is its home turf", Pops.grape) { onPickBot("ace") }
        }
    }
}

@Composable
private fun BotRow(bot: BotProfile, blurb: String, fill: Color, onClick: () -> Unit) {
    ChunkyCard(fill = fill, onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Memory, null, tint = Color.White, modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(bot.name, fontWeight = FontWeight.Bold, fontSize = 17.sp, color = Color.White)
                    CpuTag()
                }
                Text(blurb, fontSize = 12.sp, color = Color.White.copy(alpha = 0.9f))
            }
            Icon(Icons.Filled.ChevronRight, null, tint = Color.White)
        }
    }
}

/** Rolling accuracy over recent games — tunes the adaptive House bot. */
fun recentAccuracy(store: Store): Double {
    val recs = store.records().take(20)
    val total = recs.sumOf { it.total }
    if (total == 0) return 0.6
    return recs.sumOf { it.correct }.toDouble() / total
}

/** Owns one vs-CPU match: classic game + VsMatch on the same questions. */
@Composable
fun VersusScreen(botId: String, store: Store, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    val haptics = rememberGameHaptics(store)
    val game = remember { GameState(Mode.CLASSIC, Category.byId("mixed"), store, null, null) }
    val match = remember { VsMatch(listOf(Bots.byId(botId, recentAccuracy(store)))) }
    val budget = (Mode.CLASSIC.perQuestion ?: 30).toDouble()

    LaunchedEffect(Unit) { game.start() }
    LaunchedEffect(game.index, game.phase) {
        while (game.phase == GamePhase.PLAYING) { delay(100); game.tick() }
    }
    LaunchedEffect(game.index, game.phase) {
        val q = game.current ?: return@LaunchedEffect
        if (game.phase == GamePhase.PLAYING) match.beginQuestion(q, budget)
        if (game.phase == GamePhase.REVEAL) {
            match.commit(q, game.index, budget)
            if (game.lastCorrect) haptics.correct() else haptics.wrong()
        }
    }
    when (game.phase) {
        GamePhase.LOADING -> androidx.compose.foundation.layout.Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        GamePhase.ERROR -> androidx.compose.foundation.layout.Box(Modifier.fillMaxSize(), Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("No questions yet", fontWeight = FontWeight.Bold, fontSize = 22.sp)
                Button(onClick = onDone) { Text("Back") }
            }
        }
        GamePhase.FINISHED -> VersusResults(match, game,
            onRematch = { scope.launch { game.restart() } }, onDone = onDone)
        else -> PlayingScreen(game, match)
    }
}

/** "You 320 · Ace Botsworth CPU 410" — the running head-to-head. */
@Composable
fun VersusStrip(game: GameState, match: VsMatch) {
    Surface(color = MaterialTheme.colorScheme.surfaceVariant, shape = RoundedCornerShape(12.dp)) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 8.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically) {
            Text("You ${game.score}", fontWeight = FontWeight.Bold)
            Spacer(Modifier.weight(1f))
            match.seats.forEach { seat ->
                Text("${seat.bot.name} ${seat.score}", fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(6.dp))
                CpuTag(tint = MaterialTheme.colorScheme.onSurface)
            }
        }
    }
}

/** What the opponent did on THIS question — inside the reveal beat. */
@Composable
fun VersusRevealCard(match: VsMatch) {
    ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            match.seats.forEach { seat ->
                val a = match.pending.firstOrNull { it.botId == seat.bot.id }
                val line = when {
                    a == null -> seat.bot.name
                    !a.answered -> "${seat.bot.name} ran out of time"
                    seat.lastCorrect == true -> "${seat.bot.name} got it in ${"%.1f".format(a.seconds)}s"
                    else -> "${seat.bot.name} missed it"
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(if (seat.lastCorrect == true) Icons.Filled.CheckCircle else Icons.Filled.Cancel,
                        null, tint = if (seat.lastCorrect == true) accentText(Pops.mint) else accentText(Pops.coral),
                        modifier = Modifier.size(18.dp))
                    Text(line, fontSize = 14.sp)
                }
            }
        }
    }
}

@Composable
private fun VersusResults(match: VsMatch, game: GameState, onRematch: () -> Unit, onDone: () -> Unit) {
    val top = match.standings.firstOrNull()
    val won = game.score >= (top?.score ?: 0)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(20.dp))
        Text(if (won) "You won! 🎉" else "${top?.bot?.name ?: "The CPU"} takes it",
            fontWeight = FontWeight.Black, fontSize = 28.sp)
        StandingRow("You", game.score, isCpu = false, highlight = won)
        match.standings.forEach { seat ->
            StandingRow(seat.bot.name, seat.score, isCpu = true, highlight = !won && seat == top)
        }
        Text("${game.correctCount}/${game.answered.size} correct · rematches sharpen recall",
            fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        Button(onClick = onRematch, modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) {
            Text("Rematch", fontWeight = FontWeight.Bold)
        }
        TextButton(onClick = onDone) { Text("Done") }
    }
}

@Composable
private fun StandingRow(name: String, score: Int, isCpu: Boolean, highlight: Boolean) {
    ChunkyCard(fill = if (highlight) Pops.yellow else MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(name, fontWeight = FontWeight.Bold, fontSize = 17.sp, color = if (highlight) Ink else MaterialTheme.colorScheme.onSurface)
            if (isCpu) { Spacer(Modifier.width(8.dp)); CpuTag(tint = MaterialTheme.colorScheme.onSurface) }
            Spacer(Modifier.weight(1f))
            Text("$score", fontWeight = FontWeight.Black, fontSize = 22.sp, color = if (highlight) Ink else MaterialTheme.colorScheme.onSurface)
        }
    }
}
