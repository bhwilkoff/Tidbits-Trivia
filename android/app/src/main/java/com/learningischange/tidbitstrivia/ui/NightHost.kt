package com.learningischange.tidbitstrivia.ui

import android.graphics.Bitmap
import android.graphics.Color as AColor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.learningischange.tidbitstrivia.data.Category
import com.learningischange.tidbitstrivia.data.Night
import com.learningischange.tidbitstrivia.data.Question
import com.learningischange.tidbitstrivia.data.Store
import com.learningischange.tidbitstrivia.data.buildNightQuestions
import com.learningischange.tidbitstrivia.data.TypeMatch
import com.learningischange.tidbitstrivia.net.FirebaseNet
import com.learningischange.tidbitstrivia.ui.theme.Pops
import kotlinx.coroutines.launch

/**
 * Host a casual **Trivia Night** from Android — on the SAME Firebase RTDB backend
 * as Tidbits Live (owner architecture). Build the night, show a join code + a
 * scannable QR, then run it: Reveal → Next while phones/web/other apps join (the
 * unified live player) and auto-score. Twin of iOS NightHostView + the web host.
 */
@Composable
fun NightHostScreen(rounds: List<Pair<String, Int>>, category: Category, store: Store, onDone: () -> Unit) {
    var code by remember { mutableStateOf("") }
    var questions by remember { mutableStateOf<List<Question>>(emptyList()) }
    var index by remember { mutableStateOf(0) }
    var revealed by remember { mutableStateOf(false) }
    var stage by remember { mutableStateOf("lobby") }
    var teams by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var scores by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var answers by remember { mutableStateOf<Map<String, FirebaseNet.LiveAnswer>>(emptyMap()) }
    var hostPlays by remember { mutableStateOf(false) }
    var hostName by remember { mutableStateOf("Host") }
    var hostChoice by remember { mutableStateOf<Int?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var ansUnsub by remember { mutableStateOf<(() -> Unit)?>(null) }
    // Per-question shuffles, fixed once so publish + reveal agree (ordering/matching).
    var shuffledOrder by remember { mutableStateOf<List<String>>(emptyList()) }
    var shuffledValues by remember { mutableStateOf<List<String>>(emptyList()) }
    val scope = rememberCoroutineScope()

    fun qid(): String = questions.getOrNull(index)?.let { "r${it.roundIndex ?: 0}q$index" } ?: "end"

    fun prepareQuestion() {
        val q = questions.getOrNull(index)
        shuffledOrder = q?.ordering?.shuffled() ?: emptyList()
        shuffledValues = q?.matching?.values?.shuffled() ?: emptyList()
    }

    fun pubMap(): Map<String, Any?> {
        val q = questions.getOrNull(index) ?: return mapOf(
            "round" to 0, "roundTitle" to "", "qid" to "end", "qNum" to 0, "qTotal" to 0,
            "phase" to "ended", "prompt" to "", "options" to emptyList<String>(), "format" to "")
        val ri = q.roundIndex ?: 0
        val inRound = questions.filter { (it.roundIndex ?: 0) == ri }
        val kind = rounds.getOrNull(ri)?.first ?: ""
        val mcq = liveIsMCQ(q)
        val m = mutableMapOf<String, Any?>(
            "round" to ri + 1, "roundTitle" to (Night.roundTitle[kind] ?: kind),
            "qid" to "r${ri}q$index", "qNum" to inRound.indexOf(q) + 1, "qTotal" to inRound.size,
            "phase" to if (revealed) "reveal" else "question",
            "prompt" to q.prompt, "format" to kind)
        if (mcq) { m["options"] = q.options; if (revealed) m["answerIndex"] = q.correctIndex }
        q.imageUrl?.let { m["imageURL"] = it }
        q.closest?.let { m["numeric"] = mapOf("min" to it.min, "max" to it.max, "step" to it.step, "unit" to it.unit) }
        if (q.ordering != null) m["orderItems"] = shuffledOrder
        q.matching?.let { m["matchKeys"] = it.keys; m["matchValues"] = shuffledValues }
        q.enumerate?.let { m["enumTarget"] = it.total }
        return m
    }
    fun watchAnswers() {
        ansUnsub?.invoke(); answers = emptyMap()
        ansUnsub = FirebaseNet.liveOnAnswers(code, qid()) { answers = it }
    }

    DisposableEffect(Unit) {
        val unsubs = mutableListOf<() -> Unit>()
        val job = scope.launch {
            try {
                questions = buildNightQuestions(rounds, category.id, emptySet())
                code = FirebaseNet.liveHostOpen("Trivia Night")
                unsubs += FirebaseNet.liveOnTeams(code) { teams = it }
                unsubs += FirebaseNet.liveOnScores(code) { scores = it }
            } catch (e: Exception) { error = "Couldn't open a room. Check your connection." }
        }
        onDispose {
            job.cancel(); unsubs.forEach { it() }; ansUnsub?.invoke()
            if (code.isNotEmpty()) FirebaseNet.liveClose(code)
        }
    }

    fun start() = scope.launch {
        if (questions.isEmpty() || code.isEmpty()) return@launch
        if (hostPlays) FirebaseNet.liveHostJoinAsTeam(code, hostName.ifBlank { "Host" })
        index = 0; revealed = false; hostChoice = null; stage = "playing"
        prepareQuestion()
        FirebaseNet.liveSetState(code, "live")
        FirebaseNet.livePublish(code, pubMap()); watchAnswers()
    }
    fun reveal() = scope.launch {
        if (revealed) return@launch
        revealed = true
        FirebaseNet.livePublish(code, pubMap())
        val q = questions.getOrNull(index) ?: return@launch
        answers.forEach { (uid, a) ->
            val pts = liveScore(q, a, shuffledOrder, shuffledValues, 1)
            if (pts > 0) FirebaseNet.liveSetScore(code, uid, (scores[uid] ?: 0) + pts)
        }
    }
    fun next() = scope.launch {
        if (!revealed) return@launch
        revealed = false; hostChoice = null; index++
        if (questions.getOrNull(index) == null) {
            stage = "ended"; FirebaseNet.liveSetState(code, "ended"); FirebaseNet.livePublish(code, pubMap())
        } else { prepareQuestion(); FirebaseNet.livePublish(code, pubMap()); watchAnswers() }
    }
    fun hostAnswer(i: Int) = scope.launch {
        if (!hostPlays || revealed || hostChoice != null) return@launch
        hostChoice = i; FirebaseNet.liveHostAnswer(code, qid(), i)
    }

    val standings = teams.map { (uid, name) -> Triple(uid, name, scores[uid] ?: 0) }
        .sortedWith(compareByDescending<Triple<String, String, Int>> { it.third }.thenBy { it.second })
    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        when (stage) {
            "ended" -> {
                Text(standings.firstOrNull()?.let { "${it.second} wins!" } ?: "That's a night!", fontSize = 28.sp, fontWeight = FontWeight.Black, color = ink)
                StandingsList(standings, ink)
                Button(onClick = { onDone() }, colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Done") }
            }
            "lobby" -> {
                Text("Trivia Night", fontSize = 28.sp, fontWeight = FontWeight.Black, color = ink)
                error?.let { Text(it, color = Pops.coral, fontWeight = FontWeight.Bold) }
                Column(Modifier.fillMaxWidth().border(2.dp, ink.copy(alpha = 0.12f), RoundedCornerShape(16.dp)).padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("SCAN TO JOIN", color = soft, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Spacer(Modifier.height(10.dp))
                    if (code.isNotEmpty()) {
                        Image(BitmapPainter(qrBitmap("https://tidbitstrivia.com/live/$code")), contentDescription = "Join QR",
                            modifier = Modifier.size(220.dp).background(Color.White).padding(8.dp))
                    } else { CircularProgressIndicator() }
                    Spacer(Modifier.height(10.dp))
                    Text(code.ifEmpty { "····" }, fontSize = 36.sp, fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace, color = ink)
                    Text("tidbitstrivia.com/live", color = soft, fontSize = 13.sp)
                }
                Text("${teams.size} in the room", color = soft, fontWeight = FontWeight.Bold)
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("I'll play too", fontWeight = FontWeight.Bold, color = ink)
                        Text("Answer on this device and join the standings.", color = soft, fontSize = 13.sp)
                    }
                    Switch(checked = hostPlays, onCheckedChange = { hostPlays = it })
                }
                if (hostPlays) OutlinedTextField(value = hostName, onValueChange = { hostName = it }, label = { Text("Your name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Button(onClick = { start() }, enabled = code.isNotEmpty(), modifier = Modifier.fillMaxWidth().height(52.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) {
                    Text(if (code.isNotEmpty()) "Start the Night" else "Opening room…", fontWeight = FontWeight.Bold)
                }
                Text("Players scan or open Tidbits → Join a game. You run the questions.", color = soft, fontSize = 13.sp)
            }
            else -> {
                val q = questions.getOrNull(index)
                if (q != null) {
                    val ri = q.roundIndex ?: 0
                    val inRound = questions.filter { (it.roundIndex ?: 0) == ri }
                    Text("ROUND ${ri + 1}/${rounds.size} · ${Night.roundTitle[rounds.getOrNull(ri)?.first ?: ""] ?: ""} — Q${inRound.indexOf(q) + 1}/${inRound.size} · ${answers.size} answered",
                        color = soft, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    q.imageUrl?.let { url ->
                        AsyncImage(model = url, contentDescription = null, modifier = Modifier.fillMaxWidth().height(200.dp))
                    }
                    Text(q.prompt, fontSize = 22.sp, fontWeight = FontWeight.Black, color = ink)
                    if (liveIsMCQ(q)) {
                        q.options.forEachIndexed { i, opt ->
                            val chosen = hostChoice == i
                            val correct = revealed && i == q.correctIndex
                            val wrong = revealed && chosen && !correct
                            val bg = when { correct -> Pops.mint; wrong -> Color(0xFFF3D1CD); chosen -> Pops.blue.copy(alpha = 0.18f); else -> MaterialTheme.colorScheme.surface }
                            Row(Modifier.fillMaxWidth().background(bg, RoundedCornerShape(14.dp))
                                .border(2.dp, ink.copy(alpha = 0.12f), RoundedCornerShape(14.dp))
                                .clickable(enabled = hostPlays && !revealed && hostChoice == null) { hostAnswer(i) }
                                .padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text("${i + 1}", color = Color.White, fontWeight = FontWeight.Black, textAlign = TextAlign.Center,
                                    modifier = Modifier.size(26.dp).background(ink, RoundedCornerShape(7.dp)).padding(top = 2.dp))
                                Spacer(Modifier.width(12.dp))
                                Text(opt, color = if (correct) Color.White else ink, fontWeight = FontWeight.Bold)
                            }
                        }
                    } else {
                        Text("Players answer on their devices. Reveal when everyone's in.", color = soft)
                        if (revealed) {
                            Text("Answer: ${liveAnswerLine(q)}", color = ink, fontWeight = FontWeight.Bold,
                                modifier = Modifier.fillMaxWidth().background(Pops.mint, RoundedCornerShape(12.dp)).padding(12.dp))
                        }
                    }
                    if (!revealed) Button(onClick = { reveal() }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Pops.blue, contentColor = Color.White)) { Text("Reveal", fontWeight = FontWeight.Bold) }
                    else Button(onClick = { next() }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Next", fontWeight = FontWeight.Bold) }
                }
                StandingsList(standings, ink)
            }
        }
    }
}

@Composable
private fun StandingsList(standings: List<Triple<String, String, Int>>, ink: Color) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("STANDINGS", color = ink.copy(alpha = 0.6f), fontWeight = FontWeight.Bold, fontSize = 13.sp)
        if (standings.isEmpty()) Text("Players appear here as they join.", color = ink.copy(alpha = 0.6f))
        standings.forEachIndexed { i, t ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("${if (i == 0) "👑 " else ""}${t.second}", color = ink, fontWeight = FontWeight.Bold)
                Text("${t.third}", color = ink, fontWeight = FontWeight.Black)
            }
        }
    }
}

private fun qrBitmap(text: String, size: Int = 480): ImageBitmap {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    for (x in 0 until size) for (y in 0 until size) bmp.setPixel(x, y, if (matrix.get(x, y)) AColor.BLACK else AColor.WHITE)
    return bmp.asImageBitmap()
}

// ---- Host-side type helpers (mirror LiveNightHost.swift) --------------------

fun liveIsMCQ(q: Question): Boolean =
    q.closest == null && q.ordering == null && q.matching == null && q.accepted == null && q.enumerate == null

fun liveAnswerLine(q: Question): String = when {
    q.closest != null -> q.closest.formattedAnswer
    q.accepted != null -> q.accepted.firstOrNull() ?: q.answerText
    q.ordering != null -> q.ordering.joinToString(" → ")
    q.matching != null -> q.matching.keys.zip(q.matching.values).joinToString(", ") { (k, v) -> "$k = $v" }
    q.enumerate != null -> q.enumerate.displayNames.joinToString(", ")
    else -> q.answerText
}

/** Points for one submission, by question type (mirrors LiveNightHost.score). */
fun liveScore(q: Question, a: FirebaseNet.LiveAnswer, shuffledOrder: List<String>, shuffledValues: List<String>, mcqPoints: Int): Int {
    q.closest?.let { c -> return a.number?.let { c.points(it) } ?: 0 }
    q.ordering?.let { correct ->
        val order = a.order ?: return 0
        val seq = order.mapNotNull { shuffledOrder.getOrNull(it) }
        return seq.zip(correct).count { it.first == it.second }
    }
    q.matching?.let { m ->
        val pairs = a.pairs ?: return 0
        var pts = 0
        m.keys.forEachIndexed { i, _ ->
            val vi = pairs.getOrNull(i)
            if (vi != null && shuffledValues.getOrNull(vi) == m.values.getOrNull(i)) pts++
        }
        return pts
    }
    q.accepted?.let { acc -> return if (a.text != null && TypeMatch.matches(a.text, acc)) mcqPoints else 0 }
    q.enumerate?.let { e ->
        val list = a.list ?: return 0
        val filled = mutableSetOf<Int>()
        for (name in list) for ((gi, group) in e.groups.withIndex()) if (gi !in filled && TypeMatch.matches(name, group)) { filled.add(gi); break }
        return filled.size
    }
    return if (a.choice == q.correctIndex) mcqPoints else 0
}
