package com.learningischange.tidbitstrivia.ui

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

    fun submit(i: Int) {
        val p = pub ?: return
        if (p.phase != "question" || submittedQid == p.qid) return
        chosen = i; submittedQid = p.qid
        scope.launch {
            try { FirebaseNet.liveSubmit(code, p.qid, i) }
            catch (e: Exception) { submittedQid = null; chosen = null; error = "Answer didn't send — tap again." }
        }
    }

    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)
    val p = pub
    val ended = meta?.state == "ended" || p?.phase == "ended"

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
                Text(p.prompt, fontSize = 24.sp, fontWeight = FontWeight.Black, color = ink)
                Spacer(Modifier.height(16.dp))
                val opts = p.options
                if (opts != null) {
                    opts.forEachIndexed { i, opt ->
                        val isChosen = chosen == i
                        val correct = revealed && p.answerIndex == i
                        val wrong = revealed && isChosen && p.answerIndex != i
                        OptionRow(i, opt, isChosen, correct, wrong, enabled = !revealed && submittedQid != p.qid) { submit(i) }
                        Spacer(Modifier.height(12.dp))
                    }
                } else {
                    Text("Answer on your team sheet — the host is scoring this round.", color = soft)
                }
                Spacer(Modifier.height(6.dp))
                val note = when {
                    revealed && chosen == p.answerIndex -> "Correct!" to Pops.mint
                    revealed && chosen == null -> "No answer submitted." to soft
                    revealed -> "Not this time." to Pops.coral
                    submittedQid == p.qid -> "Locked in — waiting for the reveal…" to Pops.mint
                    else -> "Tap your answer." to soft
                }
                Text(note.first, color = note.second, fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
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
