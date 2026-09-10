package com.learningischange.tidbitstrivia.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import java.text.DateFormat
import java.util.Date
import kotlin.math.ceil

/** A3.14 — the room is on a break, said on the player's own phone. Mirrors Swift's
 *  `LiveBreakCard` and the pure `LiveBreak` text: whole minutes rounded UP, and the
 *  clock time the room actually acts on. */
@Composable
fun LiveBreakCard(breakUntil: Long?) {
    // Re-render every half second so a minute rolling over is visible here too,
    // rather than waiting for the host's next publish.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(breakUntil) {
        while (true) { now = System.currentTimeMillis(); delay(500) }
    }
    // Nearest minute, not up: rounding up turned every slightly-slow clock in the room
    // into a different number (the projector said 10 and a joiner said 11).
    val mins = breakUntil?.let { u ->
        val secs = (u - now) / 1000.0
        if (secs <= 0) null else kotlin.math.round(secs / 60).toInt().takeIf { it > 0 }
    }
    val head = when {
        mins == null -> "Back in a moment"
        mins == 1 -> "Back in a minute"
        else -> "Back in $mins minutes"
    }
    val clock = if (mins != null && breakUntil != null)
        "back at " + DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(breakUntil)) else ""
    Column(
        Modifier.fillMaxWidth().padding(vertical = 26.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(head, fontSize = 30.sp, fontWeight = FontWeight.Black, textAlign = TextAlign.Center)
        Text(
            if (clock.isEmpty()) "Grab a drink — the next round is coming up." else "Grab a drink — $clock.",
            fontSize = 15.sp, textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
        )
    }
}
