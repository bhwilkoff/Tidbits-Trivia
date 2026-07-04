package com.learningischange.tidbitstrivia.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.TextButton
import coil3.compose.AsyncImage
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.net.FirebaseNet
import com.learningischange.tidbitstrivia.ui.theme.Pops
import kotlinx.coroutines.launch

/**
 * Tidbits Live player on Android — join a Mac-hosted pub event by code, answer on
 * your phone, watch your score. The native twin of the web player (js/live.js) and
 * the Swift LivePlayerClient, on the shared LiveRoom contract (FirebaseNet.live*).
 * Reached from the unified "Join a game" front once the RTDB probe confirms a
 * hosted event exists (a miss falls back to the LAN Trivia Night).
 */
@Composable
fun LiveRoomScreen(code: String, team: String, onDone: () -> Unit) {
    var pub by remember { mutableStateOf<FirebaseNet.LivePub?>(null) }
    var meta by remember { mutableStateOf<FirebaseNet.LiveMeta?>(null) }
    var score by remember { mutableStateOf(0) }
    var joined by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var submittedQid by remember { mutableStateOf<String?>(null) }
    var chosen by remember { mutableStateOf<Int?>(null) }
    val scope = rememberCoroutineScope()

    DisposableEffect(code) {
        val unsubs = mutableListOf<() -> Unit>()
        val job = scope.launch {
            try {
                FirebaseNet.liveJoin(code, team)
                joined = true
                unsubs += FirebaseNet.liveOnMeta(code) { meta = it }
                unsubs += FirebaseNet.liveOnScore(code) { score = it }
                unsubs += FirebaseNet.liveOnPub(code) { p ->
                    if (p != null && p.qid != pub?.qid) { submittedQid = null; chosen = null }
                    pub = p
                }
            } catch (e: Exception) {
                error = "Couldn't join. Check the code and your connection."
            }
        }
        onDispose {
            job.cancel()
            unsubs.forEach { it() }
            if (joined) FirebaseNet.liveLeave(code)
        }
    }

    fun submitFields(fields: Map<String, Any?>) {
        val p = pub ?: return
        if (p.phase != "question" || submittedQid == p.qid || p.locked) return
        submittedQid = p.qid
        scope.launch {
            try { FirebaseNet.liveSubmitAnswer(code, p.qid, fields) }
            catch (e: Exception) { submittedQid = null; chosen = null; error = "Answer didn't send — tap again." }
        }
    }
    fun submit(i: Int) { chosen = i; submitFields(mapOf("choice" to i.toLong())) }

    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)
    val p = pub
    val ended = meta?.state == "ended" || p?.phase == "ended"

    // Live→profile bridge: tally MCQ accuracy, feed the portable profile once at the end.
    var liveAnswered by remember { mutableStateOf(0) }
    var liveCorrect by remember { mutableStateOf(0) }
    var talliedQid by remember { mutableStateOf<String?>(null) }
    var recordedEnd by remember { mutableStateOf(false) }
    LaunchedEffect(p?.qid, p?.phase) {
        val pub = p ?: return@LaunchedEffect
        if (pub.phase == "reveal" && talliedQid != pub.qid) {
            talliedQid = pub.qid
            if (pub.options != null && submittedQid == pub.qid) {
                liveAnswered++
                if (chosen == pub.answerIndex) liveCorrect++
            }
        }
    }
    LaunchedEffect(ended) {
        if (ended && joined && !recordedEnd) {
            recordedEnd = true
            com.learningischange.tidbitstrivia.data.PlayerIdentity.recordLiveGame(liveCorrect, liveAnswered)
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp)) {
        if (joined) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp)) {
                Column(Modifier.weight(1f)) {
                    Text(team.ifBlank { "Your team" }, fontSize = 20.sp, fontWeight = FontWeight.Black, color = ink)
                    Text("CODE $code", fontSize = 12.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, color = soft)
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text("$score", fontSize = 26.sp, fontWeight = FontWeight.Black, color = ink)
                    Text("POINTS", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = soft)
                }
            }
        }

        when {
            error != null && !joined -> Centered {
                Text(error!!, color = Pops.coral, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                Spacer(Modifier.height(16.dp))
                Button(onClick = onDone) { Text("Back") }
            }
            !joined -> Centered {
                CircularProgressIndicator()
                Spacer(Modifier.height(14.dp))
                Text("Joining $code…", color = soft, fontWeight = FontWeight.Bold)
            }
            ended -> Centered {
                Badge("THAT'S A WRAP", Pops.coral)
                Spacer(Modifier.height(12.dp))
                Text("Final score: $score", fontSize = 26.sp, fontWeight = FontWeight.Black, color = ink)
                Spacer(Modifier.height(16.dp))
                Button(onClick = onDone, colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Done") }
            }
            p == null || meta?.state == "lobby" -> Centered {
                Badge("YOU'RE IN", Pops.mint)
                Spacer(Modifier.height(12.dp))
                Text("Waiting for the host to start…", fontSize = 22.sp, fontWeight = FontWeight.Black, color = ink, textAlign = TextAlign.Center)
                Spacer(Modifier.height(6.dp))
                Text("Keep this open — questions appear here.", color = soft, textAlign = TextAlign.Center)
            }
            else -> {
                val revealed = p.phase == "reveal"
                Text("ROUND ${p.round} · ${p.roundTitle.uppercase()} — Q${p.qNum}/${p.qTotal}",
                    fontSize = 13.sp, fontWeight = FontWeight.Bold, color = soft)
                Spacer(Modifier.height(10.dp))
                p.imageUrl?.let { url ->
                    AsyncImage(model = url, contentDescription = null, modifier = Modifier.fillMaxWidth().height(220.dp))
                    Spacer(Modifier.height(12.dp))
                }
                Text(p.prompt, fontSize = 24.sp, fontWeight = FontWeight.Black, color = ink)
                Spacer(Modifier.height(16.dp))
                val locked = revealed || submittedQid == p.qid || p.locked
                when {
                    p.numeric != null -> NumericAnswer(p.numeric, p.qid, locked) { submitFields(mapOf("number" to it)) }
                    p.options != null -> p.options.forEachIndexed { i, opt ->
                        val isChosen = chosen == i
                        val correct = revealed && p.answerIndex == i
                        val wrong = revealed && isChosen && p.answerIndex != i
                        OptionRow(i, opt, isChosen, correct, wrong, enabled = !locked) { submit(i) }
                        Spacer(Modifier.height(12.dp))
                    }
                    p.orderItems != null -> OrderingAnswer(p.orderItems, p.qid, locked) { o -> submitFields(mapOf("order" to o.map { it.toLong() })) }
                    p.matchKeys != null && p.matchValues != null -> MatchingAnswer(p.matchKeys, p.matchValues, p.qid, locked) { pr -> submitFields(mapOf("pairs" to pr.map { it.toLong() })) }
                    p.enumTarget != null -> EnumerateAnswer(p.enumTarget, p.qid, locked) { submitFields(mapOf("list" to it)) }
                    else -> TextAnswer(p.qid, locked) { submitFields(mapOf("text" to it)) }
                }
                Spacer(Modifier.height(6.dp))
                val note = when {
                    revealed && chosen == p.answerIndex -> "Correct!" to Pops.mint
                    revealed && chosen == null -> "No answer submitted." to soft
                    revealed -> "Not this time." to Pops.coral
                    submittedQid == p.qid -> "Locked in — waiting for the reveal…" to Pops.mint
                    p.locked -> "Answers locked — pencils down!" to Pops.coral
                    else -> "Tap your answer." to soft
                }
                Text(note.first, color = note.second, fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
                if (revealed && !p.story.isNullOrBlank()) {   // Wave A: the story behind the answer
                    Spacer(Modifier.height(10.dp))
                    Text(p.story!!, fontSize = 15.sp, lineHeight = 21.sp, textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.85f),
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp))
                }
            }
        }
    }
}

@Composable
private fun Centered(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(top = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) { content() }
}

@Composable
private fun Badge(text: String, color: Color) {
    Text(text, color = Color.White, fontWeight = FontWeight.Black, fontSize = 13.sp,
        modifier = Modifier.background(color, CircleShape).padding(horizontal = 14.dp, vertical = 6.dp))
}

@Composable
private fun OptionRow(i: Int, opt: String, chosen: Boolean, correct: Boolean, wrong: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val bg = when {
        correct -> Pops.mint
        wrong -> Color(0xFFF3D1CD)
        chosen -> Pops.blue.copy(alpha = 0.18f)
        else -> MaterialTheme.colorScheme.surface
    }
    val fg = if (correct) Color.White else MaterialTheme.colorScheme.onSurface
    Row(
        Modifier.fillMaxWidth()
            .background(bg, RoundedCornerShape(16.dp))
            .border(2.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("${i + 1}", color = Color.White, fontWeight = FontWeight.Black, fontSize = 14.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.size(26.dp).background(MaterialTheme.colorScheme.onSurface, RoundedCornerShape(8.dp)).padding(top = 3.dp))
        Spacer(Modifier.width(12.dp))
        Text(opt, color = fg, fontWeight = FontWeight.Bold, fontSize = 17.sp)
    }
}

// ---- Per-type answer surfaces (host auto-scores each on reveal) -------------

@Composable
private fun NumericAnswer(spec: FirebaseNet.LiveNumeric, qid: String, locked: Boolean, onSubmit: (Double) -> Unit) {
    var value by remember(qid) { mutableStateOf((spec.min + spec.max) / 2) }
    var sent by remember(qid) { mutableStateOf(false) }
    val ink = MaterialTheme.colorScheme.onSurface
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val unit = if (spec.unit.isBlank()) "" else " ${spec.unit}"
        val label = if (value == kotlin.math.floor(value)) "${value.toInt()}$unit" else String.format("%.1f%s", value, unit)
        Text(label, fontSize = 28.sp, fontWeight = FontWeight.Black, color = ink)
        Slider(value = value.toFloat(), onValueChange = { value = it.toDouble() },
            valueRange = spec.min.toFloat()..spec.max.toFloat(), enabled = !locked && !sent)
        if (!sent) Button(onClick = { sent = true; onSubmit(value) }, enabled = !locked, modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Submit", fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun TextAnswer(qid: String, locked: Boolean, onSubmit: (String) -> Unit) {
    var text by remember(qid) { mutableStateOf("") }
    var sent by remember(qid) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text("Type your answer") },
            singleLine = true, enabled = !locked && !sent, modifier = Modifier.fillMaxWidth())
        if (!sent) Button(onClick = { val t = text.trim(); if (t.isNotEmpty()) { sent = true; onSubmit(t) } },
            enabled = !locked, modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Submit", fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun EnumerateAnswer(target: Int, qid: String, locked: Boolean, onSubmit: (List<String>) -> Unit) {
    var entry by remember(qid) { mutableStateOf("") }
    var items by remember(qid) { mutableStateOf(listOf<String>()) }
    var sent by remember(qid) { mutableStateOf(false) }
    val ink = MaterialTheme.colorScheme.onSurface
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Name as many as you can (${items.size}${if (target > 0) "/$target" else ""})", color = ink.copy(alpha = 0.6f))
        if (items.isNotEmpty()) Text(items.joinToString(" · "), color = ink, fontWeight = FontWeight.Bold)
        if (!sent) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(value = entry, onValueChange = { entry = it }, label = { Text("Add one…") }, singleLine = true, enabled = !locked, modifier = Modifier.weight(1f))
                Button(onClick = { val t = entry.trim(); if (t.isNotEmpty() && items.none { it.equals(t, true) }) { items = items + t; entry = "" } }, enabled = !locked && entry.isNotBlank()) { Text("Add") }
            }
            Button(onClick = { sent = true; onSubmit(items) }, enabled = !locked && items.isNotEmpty(), modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Done", fontWeight = FontWeight.Bold) }
        }
    }
}

@Composable
private fun OrderingAnswer(items: List<String>, qid: String, locked: Boolean, onSubmit: (List<Int>) -> Unit) {
    var order by remember(qid) { mutableStateOf(items.indices.toList()) }
    var sent by remember(qid) { mutableStateOf(false) }
    val ink = MaterialTheme.colorScheme.onSurface
    fun swap(pos: Int, d: Int) {
        val n = pos + d
        if (n in order.indices) order = order.toMutableList().apply { val t = this[pos]; this[pos] = this[n]; this[n] = t }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Put them in order (top = first).", color = ink.copy(alpha = 0.6f))
        order.forEachIndexed { pos, idx ->
            Row(Modifier.fillMaxWidth().border(2.dp, ink.copy(alpha = 0.12f), RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("${pos + 1}.", fontWeight = FontWeight.Black, color = ink.copy(alpha = 0.6f))
                Spacer(Modifier.width(8.dp))
                Text(items[idx], color = ink, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                if (!locked && !sent) {
                    IconButton(onClick = { swap(pos, -1) }, enabled = pos > 0) { Icon(Icons.Filled.KeyboardArrowUp, "Up") }
                    IconButton(onClick = { swap(pos, 1) }, enabled = pos < order.size - 1) { Icon(Icons.Filled.KeyboardArrowDown, "Down") }
                }
            }
        }
        if (!sent) Button(onClick = { sent = true; onSubmit(order) }, enabled = !locked, modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Submit", fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun MatchingAnswer(keys: List<String>, values: List<String>, qid: String, locked: Boolean, onSubmit: (List<Int>) -> Unit) {
    var pairs by remember(qid) { mutableStateOf(List(keys.size) { -1 }) }
    var sent by remember(qid) { mutableStateOf(false) }
    val ink = MaterialTheme.colorScheme.onSurface
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Match each to its pair.", color = ink.copy(alpha = 0.6f))
        keys.forEachIndexed { i, key ->
            var expanded by remember(qid, i) { mutableStateOf(false) }
            Row(Modifier.fillMaxWidth().border(2.dp, ink.copy(alpha = 0.12f), RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(key, color = ink, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                Box {
                    TextButton(onClick = { if (!locked && !sent) expanded = true }) {
                        Text(if (pairs[i] >= 0) values[pairs[i]] else "Choose…", color = if (pairs[i] >= 0) Pops.blue else ink.copy(alpha = 0.6f))
                    }
                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                        values.forEachIndexed { vi, v ->
                            DropdownMenuItem(text = { Text(v) }, onClick = { pairs = pairs.toMutableList().also { it[i] = vi }; expanded = false })
                        }
                    }
                }
            }
        }
        if (!sent) Button(onClick = { sent = true; onSubmit(pairs) }, enabled = !locked && pairs.none { it < 0 }, modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Submit", fontWeight = FontWeight.Bold) }
    }
}
