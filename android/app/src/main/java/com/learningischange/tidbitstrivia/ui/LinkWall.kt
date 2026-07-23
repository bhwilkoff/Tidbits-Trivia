package com.learningischange.tidbitstrivia.ui

import android.content.Context
import android.content.Intent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.Entitlement
import com.learningischange.tidbitstrivia.data.LinkWall
import com.learningischange.tidbitstrivia.data.MatchingSet
import com.learningischange.tidbitstrivia.data.Store
import com.learningischange.tidbitstrivia.data.dayKey
import com.learningischange.tidbitstrivia.ui.theme.Pops
import com.learningischange.tidbitstrivia.ui.theme.onAccent
import kotlinx.coroutines.delay

/** Link Wall (Tidbits Club EXCLUSIVE — docs/CLUB-FEATURES-BUILD.md "Feature 6") — a
 *  NYT-Connections-style SECOND daily: 16 tiles hide 4 themed groups of 4. UNLIKE the
 *  game engine's MCQ modes, Link Wall never routes through GameScreen/GameState — it
 *  owns its own tiny play loop here (mirrors the iOS `LinkWallView` and web's
 *  #/linkwall, which for the same reason never route through the shared game engine
 *  either). Android mirror of `LinkWallView.swift` / web's Link Wall section in
 *  app.js. */
private fun difficultyColor(d: Int): Color = when (d) {
    1 -> Pops.yellow
    2 -> Pops.mint
    3 -> Pops.blue
    else -> Pops.grape
}

private data class LinkWallSession(
    val day: String,
    val puzzle: LinkWall.LinkWallPuzzle,
    val result: LinkWall.LinkWallResult,
    val remaining: List<String>,
    val selected: List<String>,
    val solved: List<LinkWall.LinkWallGroup>,
)

private fun initSession(store: Store, day: String, puzzle: LinkWall.LinkWallPuzzle): LinkWallSession {
    val result = store.linkWallResultOrCreate(day)
    val byLabel = puzzle.groups.associateBy { it.label }
    val solved = result.solvedLabels.mapNotNull { byLabel[it] }
    val solvedMembers = solved.flatMap { it.members }.toSet()
    val remaining = puzzle.tiles.filter { it !in solvedMembers }
    return LinkWallSession(day, puzzle, result, remaining, emptyList(), solved)
}

@Composable
fun LinkWallScreen(store: Store, onBack: () -> Unit, onClub: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        LinkWallHeader(onBack)
        Spacer(Modifier.height(8.dp))
        when {
            !Entitlement.isClub -> LinkWallPaywall(onClub)
            else -> {
                // MatchingSet.loaded is a plain var, not Compose-observable — AppRoot
                // already kicks off MatchingSet.load(context) once on app boot, but a
                // cold-launch tap straight into Link Wall can beat that load. A ONE-SHOT
                // `!MatchingSet.loaded -> unavailable` check here would snapshot false
                // and get stuck showing "couldn't build today's board" forever (the
                // corpus is fine — it just hadn't finished loading yet). Await it
                // properly (load() is idempotent / a no-op once loaded) and gate on a
                // real Compose state instead.
                val context = LocalContext.current
                var ready by remember { mutableStateOf(MatchingSet.loaded) }
                LaunchedEffect(Unit) {
                    if (!MatchingSet.loaded) runCatching { MatchingSet.load(context) }
                    ready = MatchingSet.loaded
                }
                if (!ready) {
                    LinkWallLoading()
                } else {
                    val day = remember { dayKey() }
                    val puzzle = remember(day) { LinkWall.puzzle(day) }
                    if (puzzle == null) {
                        LinkWallUnavailable()
                    } else {
                        var session by remember(day) { mutableStateOf(initSession(store, day, puzzle)) }
                        if (session.result.completed) {
                            LinkWallResultView(session, onDone = onBack)
                        } else {
                            LinkWallBoard(store, session, onSessionChange = { session = it })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LinkWallHeader(onBack: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = onBack) { Text("‹ Back") }
        Text("Link Wall", fontSize = 24.sp, fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
private fun LinkWallPaywall(onClub: () -> Unit) {
    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ChunkyCard { Column(Modifier.padding(18.dp)) { Text(LinkWall.previewLine(), fontWeight = FontWeight.Bold) } }
        Spacer(Modifier.height(14.dp))
        ChunkyCard(fill = Pops.grape.copy(alpha = 0.12f)) {
            Column(Modifier.padding(20.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("16 tiles. 4 hidden groups. 4 mistakes allowed.", fontWeight = FontWeight.Black, fontSize = 18.sp, textAlign = TextAlign.Center)
                Text("A second daily, NYT-Connections style — find all four groups before you run out of guesses.",
                    fontSize = 13.sp, color = soft, textAlign = TextAlign.Center)
                Spacer(Modifier.height(12.dp))
                Button(onClick = onClub) { Text("Join Tidbits Club") }
            }
        }
    }
}

@Composable
private fun LinkWallUnavailable() {
    ChunkyCard { Column(Modifier.padding(20.dp)) {
        Text("Couldn't build today's board from the corpus. Try again tomorrow.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
    } }
}

@Composable
private fun LinkWallLoading() {
    Box(Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
private fun LinkWallBoard(store: Store, session: LinkWallSession, onSessionChange: (LinkWallSession) -> Unit) {
    val ink = MaterialTheme.colorScheme.onSurface
    var oneAwayToken by remember { mutableIntStateOf(0) }
    var oneAway by remember { mutableStateOf(false) }
    var shakeToken by remember { mutableIntStateOf(0) }
    val shakeOffset = remember { Animatable(0f) }

    LaunchedEffect(oneAwayToken) {
        if (oneAwayToken > 0) { delay(1600); oneAway = false }
    }
    LaunchedEffect(shakeToken) {
        if (shakeToken > 0) {
            for (x in intArrayOf(-12, 12, -8, 8, -4, 0)) { shakeOffset.animateTo(x.toFloat(), tween(45)) }
        }
    }

    fun toggleTile(tile: String) {
        val sel = session.selected
        val next = if (tile in sel) sel - tile else if (sel.size < 4) sel + tile else sel
        onSessionChange(session.copy(selected = next))
    }

    fun submit() {
        if (session.selected.size != 4) return
        val puzzle = session.puzzle
        val tileGroup = puzzle.groups.flatMap { g -> g.members.map { m -> m to g } }.toMap()
        val selectedSet = session.selected.toSet()
        val difficulties = session.selected.map { tileGroup[it]?.difficulty ?: 0 }
        var result = store.recordLinkWallGuess(session.day, difficulties)

        val matched = puzzle.groups.firstOrNull { g ->
            session.solved.none { it.label == g.label } && g.members.all { it in selectedSet }
        }
        if (matched != null) {
            result = store.recordLinkWallSolvedGroup(session.day, matched.label)
            val newSolved = session.solved + matched
            val newRemaining = session.remaining.filterNot { it in selectedSet }
            oneAway = false
            if (newSolved.size == puzzle.groups.size) {
                val finished = result.copy(completed = true, won = true)
                store.saveLinkWallResult(session.day, finished)
                onSessionChange(session.copy(result = finished, solved = newSolved, remaining = newRemaining, selected = emptyList()))
            } else {
                onSessionChange(session.copy(result = result, solved = newSolved, remaining = newRemaining, selected = emptyList()))
            }
            return
        }

        val mistakes = result.mistakes + 1
        result = result.copy(mistakes = mistakes)
        store.saveLinkWallResult(session.day, result)
        val closest = puzzle.groups.any { g ->
            session.solved.none { it.label == g.label } && session.selected.count { it in g.members } == 3
        }
        oneAway = closest
        oneAwayToken++
        shakeToken++
        if (mistakes >= 4) {
            val remainingGroups = puzzle.groups.filter { g -> session.solved.none { it.label == g.label } }
            val finished = result.copy(completed = true, won = false)
            store.saveLinkWallResult(session.day, finished)
            onSessionChange(session.copy(result = finished, solved = session.solved + remainingGroups, selected = emptyList()))
        } else {
            onSessionChange(session.copy(result = result, selected = emptyList()))
        }
    }

    val rows = (session.remaining.size + 3) / 4
    val tileHeight = 72.dp
    val gap = 8.dp
    val gridHeight = if (rows <= 0) 0.dp else tileHeight * rows + gap * (rows - 1)

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Text("Find the four groups of four.", color = ink.copy(alpha = 0.6f), fontSize = 14.sp)
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("MISTAKES", fontSize = 12.sp, fontWeight = FontWeight.Black, color = ink.copy(alpha = 0.5f))
            Spacer(Modifier.width(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                repeat(4) { i ->
                    Box(Modifier.height(12.dp).width(12.dp)
                        .background(if (i < (4 - session.result.mistakes)) Pops.coral else ink.copy(alpha = 0.15f), RoundedCornerShape(999.dp)))
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        session.solved.forEach { g -> LinkWallGroupRow(g); Spacer(Modifier.height(8.dp)) }

        LazyVerticalGrid(
            columns = GridCells.Fixed(4),
            modifier = Modifier.fillMaxWidth().height(gridHeight).offset(x = shakeOffset.value.dp),
            horizontalArrangement = Arrangement.spacedBy(gap),
            verticalArrangement = Arrangement.spacedBy(gap),
        ) {
            items(session.remaining, key = { it }) { tile ->
                val selected = tile in session.selected
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = if (selected) ink.copy(alpha = 0.14f) else MaterialTheme.colorScheme.surfaceVariant,
                    border = BorderStroke(2.dp, if (selected) ink else ink.copy(alpha = 0.25f)),
                    modifier = Modifier.height(tileHeight).clickable { toggleTile(tile) },
                ) {
                    Box(Modifier.fillMaxSize().padding(6.dp), contentAlignment = Alignment.Center) {
                        Text(tile, fontSize = 12.sp, fontWeight = if (selected) FontWeight.Black else FontWeight.Bold,
                            textAlign = TextAlign.Center, maxLines = 4, color = ink)
                    }
                }
            }
        }
        if (oneAway) {
            Spacer(Modifier.height(8.dp))
            Text("One away…", fontWeight = FontWeight.Black, color = Pops.coral, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
        Spacer(Modifier.height(14.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(onClick = { onSessionChange(session.copy(selected = emptyList())) }, enabled = session.selected.isNotEmpty()) { Text("Deselect All") }
            OutlinedButton(onClick = { onSessionChange(session.copy(remaining = session.remaining.shuffled())) }) { Text("Shuffle") }
            Button(onClick = { submit() }, enabled = session.selected.size == 4,
                colors = ButtonDefaults.buttonColors(containerColor = Pops.grape, contentColor = Color.White)) { Text("Submit") }
        }
        Spacer(Modifier.height(20.dp))
    }
}

@Composable
private fun LinkWallGroupRow(g: LinkWall.LinkWallGroup) {
    val fill = difficultyColor(g.difficulty)
    Surface(shape = RoundedCornerShape(12.dp), color = fill, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Text(g.label.uppercase(), fontWeight = FontWeight.Black, fontSize = 13.sp, color = onAccent(fill))
            Text(g.members.joinToString(" · "), fontSize = 13.sp, color = onAccent(fill).copy(alpha = 0.9f))
        }
    }
}

@Composable
private fun LinkWallResultView(session: LinkWallSession, onDone: () -> Unit) {
    val context = LocalContext.current
    val puzzle = session.puzzle
    val result = session.result
    val ink = MaterialTheme.colorScheme.onSurface
    val tint = if (result.won) Pops.mint else Pops.coral
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ChunkyCard(fill = tint.copy(alpha = 0.16f), modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(vertical = 22.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(if (result.won) Icons.Filled.CheckCircle else Icons.Filled.Cancel, null, tint = tint, modifier = Modifier.height(36.dp).width(36.dp))
                Spacer(Modifier.height(6.dp))
                Text(if (result.won) "SOLVED" else "NEXT TIME", fontWeight = FontWeight.Black, fontSize = 15.sp)
                val sub = if (result.won) "${result.mistakes} mistake${if (result.mistakes == 1) "" else "s"} — nice work."
                    else "Here's today's four groups. New wall tomorrow."
                Text(sub, color = ink.copy(alpha = 0.65f))
            }
        }
        if (result.guessHistory.isNotEmpty()) {
            Spacer(Modifier.height(14.dp))
            ChunkyCard(modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    result.guessHistory.forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            row.forEach { d -> Box(Modifier.height(20.dp).width(20.dp).background(difficultyColor(d), RoundedCornerShape(4.dp))) }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(20.dp))
        Text("Today's four groups", fontWeight = FontWeight.Black, fontSize = 20.sp)
        Spacer(Modifier.height(10.dp))
        puzzle.groups.forEach { g ->
            Surface(shape = RoundedCornerShape(12.dp), color = difficultyColor(g.difficulty), modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
                Column(Modifier.padding(12.dp)) {
                    Text(g.label.uppercase(), fontWeight = FontWeight.Black, fontSize = 13.sp, color = onAccent(difficultyColor(g.difficulty)))
                    Text(g.why, fontSize = 12.sp, color = onAccent(difficultyColor(g.difficulty)).copy(alpha = 0.9f))
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        Button(onClick = { shareLinkWall(context, session) }, modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Pops.blue, contentColor = Color.White)) { Text("Share") }
        TextButton(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text("Done") }
        Spacer(Modifier.height(20.dp))
    }
}

// Wordle/Connections-convention emoji share (docs/CLUB-FEATURES-BUILD.md Stage 2: "a
// shareable grid of colored squares — huge organic reach"). Mirrors the app's existing
// Intent.ACTION_SEND share pattern (e.g. the Classic/Daily result "Share Score" button).
private fun shareLinkWall(context: Context, session: LinkWallSession) {
    val emoji = mapOf(1 to "🟨", 2 to "🟩", 3 to "🟦", 4 to "🟪")
    val rows = session.result.guessHistory.joinToString("\n") { row -> row.joinToString("") { emoji[it] ?: "⬜" } }
    val summary = if (session.result.won) "Solved in ${session.result.guessHistory.size} guess${if (session.result.guessHistory.size == 1) "" else "es"}."
        else "Didn't solve it today."
    val text = "🧠 Tidbits Link Wall — ${session.day}\n$rows\n$summary\nPlay at https://tidbitstrivia.com"
    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }, "Share"))
}
