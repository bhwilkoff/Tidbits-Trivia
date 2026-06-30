package com.learningischange.tidbitstrivia.ui

import android.content.Intent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.*
import com.learningischange.tidbitstrivia.ui.theme.Ink
import com.learningischange.tidbitstrivia.ui.theme.Pops

// Local pass-and-play (parity with iOS PartyContainerView): 2-4 players, ONE
// shared fair question set, hand-off between turns, ranked scoreboard. Solo
// device; everyone answers the same questions so scores are comparable.
private enum class PartyPhase { SETUP, LOADING, HANDOFF, PLAYING, SCOREBOARD }
private const val PARTY_QS = 6

@Composable
fun PartyContainer(store: Store, onExit: () -> Unit) {
    val context = LocalContext.current
    var phase by remember { mutableStateOf(PartyPhase.SETUP) }
    var names by remember { mutableStateOf(listOf("Player 1", "Player 2")) }
    var questions by remember { mutableStateOf<List<Question>>(emptyList()) }
    var scores by remember { mutableStateOf(IntArray(0)) }
    var corrects by remember { mutableStateOf(IntArray(0)) }
    var player by remember { mutableIntStateOf(0) }
    var qIndex by remember { mutableIntStateOf(0) }
    var chosen by remember { mutableStateOf<Int?>(null) }
    val haptics = rememberGameHaptics(store)

    fun loadAndStart() {
        phase = PartyPhase.LOADING
        val qs = Corpus.pull("mixed", emptySet(), PARTY_QS)
        if (qs.size < 3) { phase = PartyPhase.SETUP; return }
        questions = qs
        scores = IntArray(names.size); corrects = IntArray(names.size)
        player = 0; qIndex = 0; chosen = null; phase = PartyPhase.HANDOFF
    }

    when (phase) {
        PartyPhase.SETUP -> PartySetup(names, onNames = { names = it }, onCancel = onExit, onStart = { loadAndStart() })
        PartyPhase.LOADING -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        PartyPhase.HANDOFF -> Handoff(names[player], player + 1, names.size) { qIndex = 0; chosen = null; phase = PartyPhase.PLAYING }
        PartyPhase.PLAYING -> {
            val q = questions[qIndex]
            PartyTurn(
                playerName = names[player], qNumber = qIndex + 1, qTotal = questions.size,
                question = q, chosen = chosen,
                onPick = { i ->
                    if (chosen != null) return@PartyTurn
                    chosen = i
                    if (i == q.correctIndex) { scores[player] = scores[player] + 100; corrects[player] = corrects[player] + 1; haptics.correct() } else haptics.wrong()
                },
                onNext = {
                    if (qIndex + 1 >= questions.size) {
                        if (player + 1 >= names.size) phase = PartyPhase.SCOREBOARD
                        else { player += 1; phase = PartyPhase.HANDOFF }
                    } else { qIndex += 1; chosen = null }
                },
            )
        }
        PartyPhase.SCOREBOARD -> Scoreboard(names, scores, corrects, questions.size,
            onRematch = { loadAndStart() },
            onShare = {
                val ranked = names.indices.sortedByDescending { scores[it] }
                val body = ranked.joinToString("\n") { "${names[it]}: ${scores[it]} pts (${corrects[it]}/${questions.size})" }
                val text = "🧠 Tidbits — Pass & Play\n$body\nhttps://tidbitstrivia.com"
                context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }, "Share"))
            },
            onDone = onExit)
    }
}

@Composable
private fun PartySetup(names: List<String>, onNames: (List<String>) -> Unit, onCancel: () -> Unit, onStart: () -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Pass & Play", fontSize = 28.sp, fontWeight = FontWeight.Black)
        Text("2–4 players, one phone, the same questions. Take turns; pass the phone when it's the next player's go.",
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        Text("Players", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            (2..4).forEach { n ->
                FilterChip(selected = names.size == n, onClick = {
                    onNames((0 until n).map { names.getOrNull(it) ?: "Player ${it + 1}" })
                }, label = { Text("$n") })
            }
        }
        names.forEachIndexed { i, nm ->
            OutlinedTextField(value = nm, onValueChange = { v -> onNames(names.toMutableList().also { it[i] = v }) },
                label = { Text("Player ${i + 1}") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(onClick = onCancel) { Text("Cancel") }
            Button(onClick = onStart, enabled = names.all { it.isNotBlank() },
                colors = ButtonDefaults.buttonColors(containerColor = Pops.grape)) { Text("Start") }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun Handoff(name: String, num: Int, total: Int, onBegin: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Box(Modifier.size(96.dp).background(Pops.at(num), CircleShape).border(BorderStroke(3.dp, Ink), CircleShape), contentAlignment = Alignment.Center) {
            Text("👋", fontSize = 44.sp)
        }
        Spacer(Modifier.height(20.dp))
        Text("Pass the phone to", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        Text(name, fontWeight = FontWeight.Black, fontSize = 34.sp, textAlign = TextAlign.Center)
        Text("Player $num of $total", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        Spacer(Modifier.height(28.dp))
        Button(onClick = onBegin, modifier = Modifier.fillMaxWidth().height(54.dp), colors = ButtonDefaults.buttonColors(containerColor = Ink)) {
            Text("I'm $name — Begin", fontWeight = FontWeight.Bold, fontSize = 17.sp)
        }
    }
}

@Composable
private fun PartyTurn(playerName: String, qNumber: Int, qTotal: Int, question: Question, chosen: Int?, onPick: (Int) -> Unit, onNext: () -> Unit) {
    val revealed = chosen != null
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(playerName, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
            AssistChip(onClick = {}, label = { Text("$qNumber / $qTotal") })
        }
        Text(Category.byId(question.categoryId).name.uppercase(), color = Pops.at(Category.byId(question.categoryId).colorIndex), fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Text(question.prompt, fontWeight = FontWeight.Black, fontSize = 23.sp)
        question.options.forEachIndexed { i, opt ->
            val state = when {
                !revealed -> AnswerVisual.IDLE
                i == question.correctIndex -> AnswerVisual.CORRECT
                i == chosen -> AnswerVisual.WRONG
                else -> AnswerVisual.DIM
            }
            PartyAnswer(opt, state, !revealed) { onPick(i) }
        }
        if (revealed) {
            Surface(shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.surfaceVariant, border = BorderStroke(2.5.dp, Ink), modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(if (chosen == question.correctIndex) "Nice — you knew it." else "Now you know.", fontWeight = FontWeight.Bold, fontSize = 17.sp)
                    if (question.explanation.isNotEmpty()) Text(question.explanation)
                }
            }
            Button(onClick = onNext, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Ink)) {
                Text(if (qNumber >= qTotal) "Done — pass it on" else "Next")
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun PartyAnswer(text: String, state: AnswerVisual, enabled: Boolean, onClick: () -> Unit) {
    val bg = when (state) { AnswerVisual.CORRECT -> Pops.mint; AnswerVisual.WRONG -> Pops.coral; else -> MaterialTheme.colorScheme.surface }
    val fg = when (state) { AnswerVisual.CORRECT, AnswerVisual.WRONG -> Color.White; else -> MaterialTheme.colorScheme.onSurface }
    Surface(onClick = onClick, enabled = enabled, shape = RoundedCornerShape(14.dp), color = bg, border = BorderStroke(2.5.dp, Ink), modifier = Modifier.fillMaxWidth()) {
        Text(text, Modifier.padding(16.dp), color = fg, fontWeight = FontWeight.Bold, fontSize = 17.sp)
    }
}

@Composable
private fun Scoreboard(names: List<String>, scores: IntArray, corrects: IntArray, qTotal: Int, onRematch: () -> Unit, onShare: () -> Unit, onDone: () -> Unit) {
    val ranked = names.indices.sortedByDescending { scores[it] }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("🏆 ${names[ranked.first()]} wins!", fontWeight = FontWeight.Black, fontSize = 26.sp, textAlign = TextAlign.Center)
        ranked.forEachIndexed { rank, p ->
            Surface(shape = RoundedCornerShape(18.dp), color = if (rank == 0) Pops.yellow.copy(alpha = 0.25f) else MaterialTheme.colorScheme.surface, border = BorderStroke(2.5.dp, Ink), modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("${rank + 1}", fontWeight = FontWeight.Black, fontSize = 20.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    Column(Modifier.weight(1f)) {
                        Text(names[p], fontWeight = FontWeight.Bold, fontSize = 18.sp)
                        Text("${corrects[p]}/$qTotal correct", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                    Text("${scores[p]}", fontWeight = FontWeight.Black, fontSize = 22.sp)
                }
            }
        }
        Button(onClick = onShare, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Pops.blue)) { Text("Share") }
        Button(onClick = onRematch, modifier = Modifier.fillMaxWidth()) { Text("Rematch") }
        TextButton(onClick = onDone) { Text("Done") }
    }
}
