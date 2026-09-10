package com.learningischange.tidbitstrivia.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.ScreenshotHooks
import com.learningischange.tidbitstrivia.ui.theme.Pops
import com.learningischange.tidbitstrivia.net.FirebaseNet
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** G6, native: the host's phone as a remote for the laptop cockpit. Pair with the room
 *  code AND the six-digit PIN the laptop shows (the code is on the projector, so it
 *  authorises nothing), then Reveal / Next / Skip / Scores while walking the room.
 *  Commands carry a monotonic id resumed from the HOST's counter. Mirror of the web's
 *  `remoteHTML` and the iOS `LiveRemoteView`. */
@Composable
fun LiveRemoteScreen(initialCode: String, onDone: () -> Unit) {
    var code by remember { mutableStateOf(initialCode) }
    var pin by remember { mutableStateOf("") }
    var paired by remember { mutableStateOf(false) }
    var pub by remember { mutableStateOf<FirebaseNet.LivePub?>(null) }
    var remoteId by remember { mutableIntStateOf(0) }
    var note by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    suspend fun pair() {
        if (code.length < 4) { error = "Enter the 4-letter room code."; return }
        if (pin.length < 6) { error = "Enter the 6-digit PIN from your laptop."; return }
        error = null
        // Auth FIRST. `listen()` swallows onCancelled, so a pub listener attached before
        // anonymous auth is denied by the rules (auth != null) and never retries — the
        // remote sat on "Waiting for the host…" all night while its commands still worked.
        // The joiner never hit this because liveJoin() authenticates before it listens.
        runCatching { FirebaseNet.ensureAuth() }
        remoteId = runCatching { FirebaseNet.liveRemoteLastId(code) }.getOrDefault(0)
        paired = true
    }
    suspend fun send(verb: String) {
        remoteId += 1
        try { FirebaseNet.liveRemoteSend(code, remoteId, verb, pin); note = null }
        catch (e: Exception) { remoteId -= 1; note = "That did not send — try again." }   // keep the id: a gap is skipped forever
    }
    DisposableEffect(paired, code) {
        val stop = if (paired) FirebaseNet.liveOnPub(code) { pub = it } else null
        onDispose { stop?.invoke() }
    }
    LaunchedEffect(Unit) {   // harness: pair, then send one verb the way a tap does
        ScreenshotHooks.liveRemote?.let { (c, p) ->
            code = c; pin = p; pair()
            ScreenshotHooks.liveRemoteVerb?.let { verb -> delay(ScreenshotHooks.liveRemoteAt * 1000L); send(verb) }
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).then(tvOverscan()),
           verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (!paired) {
            Text("Drive the night", fontSize = 28.sp, fontWeight = FontWeight.Black)
            Text("Enter your room code and the PIN from your laptop.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            OutlinedTextField(value = code, onValueChange = { code = it.uppercase().filter { c -> c.isLetterOrDigit() }.take(4); error = null },
                label = { Text("Room code") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters))
            OutlinedTextField(value = pin, onValueChange = { pin = it.filter { c -> c.isDigit() }.take(6); error = null },
                label = { Text("PIN") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
            error?.let { Text(it, color = Pops.coral, fontWeight = FontWeight.Bold) }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(onClick = onDone) { Text("Cancel") }
                Button(onClick = { scope.launch { pair() } }, enabled = code.length == 4 && pin.length == 6, modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Pair") }
            }
            Text("The PIN is on the host screen, not the projector — the room code alone cannot drive the show.",
                fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        } else {
            val p = pub
            Text("REMOTE · $code" + (p?.let { " · ROUND ${it.round}" } ?: ""), fontSize = 13.sp, fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            Text(p?.prompt?.takeIf { it.isNotBlank() } ?: "Waiting for the host…", fontSize = 24.sp, fontWeight = FontWeight.Black)
            if (p?.phase == "reveal") {
                val a = p.options?.getOrNull(p.answerIndex ?: -1) ?: p.answer
                a?.let { Text("Answer: $it", color = Pops.mint, fontWeight = FontWeight.Bold) }
            }
            Spacer(Modifier.height(8.dp))
            @Composable fun Verb(label: String, verb: String, fill: Color, text: Color, modifier: Modifier) =
                Button(onClick = { scope.launch { send(verb) } }, modifier = modifier.height(72.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = fill, contentColor = text)) { Text(label, fontSize = 18.sp, fontWeight = FontWeight.Black) }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Verb("Reveal", "reveal", Pops.coral, Color.White, Modifier.weight(1f))
                Verb("Next", "next", MaterialTheme.colorScheme.onSurface, MaterialTheme.colorScheme.surface, Modifier.weight(1f))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Verb("Skip", "skip", MaterialTheme.colorScheme.surfaceVariant, MaterialTheme.colorScheme.onSurface, Modifier.weight(1f))
                Verb("Scores", "scores", MaterialTheme.colorScheme.surfaceVariant, MaterialTheme.colorScheme.onSurface, Modifier.weight(1f))
            }
            note?.let { Text(it, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)) }
            TextButton(onClick = onDone) { Text("Done") }
        }
    }
}
