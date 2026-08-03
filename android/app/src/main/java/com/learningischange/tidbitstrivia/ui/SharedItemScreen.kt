package com.learningischange.tidbitstrivia.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.Category
import com.learningischange.tidbitstrivia.data.Question
import com.learningischange.tidbitstrivia.data.sharedItem
import com.learningischange.tidbitstrivia.ui.theme.Pops

/**
 * What a `tidbits://item/<id>` link opens (DEEP_LINKS.md) — the in-app half of the
 * canonical twin the web renders at `https://tidbitstrivia.com/item/<id>`.
 *
 * It shows the FACT, not a quiz. Someone arriving here was sent a thing worth knowing by
 * a friend; making them guess it first is a puzzle they didn't ask for. The answer, the
 * explanation and the door out to the source are the payload — playing is the invitation
 * underneath it.
 */
@Composable
fun SharedItemScreen(id: String, onBack: () -> Unit, onPlay: () -> Unit) {
    val ctx = LocalContext.current
    // produceState, not remember: the lookup has to load the corpus + sets from disk, and a
    // deep link is usually the first thing this process does. The result is BOXED so that
    // "still loading" and "resolved to nothing" are different states — a bare null for both
    // makes every link read as dead for the first beat.
    val found by produceState<Lookup?>(initialValue = null, id) { value = Lookup(sharedItem(ctx, id)) }
    val q = found?.question
    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)
    val uri = LocalUriHandler.current

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
           verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
            Text("Tidbits", fontSize = 22.sp, fontWeight = FontWeight.Black, color = ink)
        }
        if (q == null) {
            // A retired row is a real outcome, not an error state to hide — but only say so
            // once the lookup has actually finished, or every link reads as dead for a beat.
            if (found == null) { Text("Opening…", color = soft); return@Column }
            Text("Not found", fontSize = 26.sp, fontWeight = FontWeight.Black, color = ink)
            Text("This link doesn't point at a question any more — it may have been retired " +
                 "from the bank since it was shared.", color = soft)
            Button(onClick = onPlay, modifier = Modifier.fillMaxWidth()) { Text("Play Tidbits") }
            return@Column
        }
        Text(Category.byId(q.categoryId).name.uppercase(), fontSize = 12.sp,
             fontWeight = FontWeight.Bold, color = soft)
        Text(q.prompt, fontSize = 26.sp, fontWeight = FontWeight.Black, color = ink)
        ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant) {
            Column(Modifier.padding(16.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("ANSWER", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = soft)
                Text(q.answerText, fontSize = 22.sp, fontWeight = FontWeight.Black, color = ink)
                if (q.explanation.isNotBlank()) Text(q.explanation, color = ink)
                q.sourceUrl?.takeIf { it.isNotBlank() }?.let { url ->
                    TextButton(onClick = { runCatching { uri.openUri(url) } }) {
                        Text("Read on Wikipedia", color = Pops.blue, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
        Spacer(Modifier.height(4.dp))
        Button(onClick = onPlay, modifier = Modifier.fillMaxWidth()) { Text("Play Tidbits") }
    }
}

/// Boxes the lookup so "not finished" (null box) and "no such question" (box with a null
/// inside) are distinguishable states.
private class Lookup(val question: Question?)
