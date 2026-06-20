package com.learningischange.tidbitstrivia.ui

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import coil3.compose.AsyncImage
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.*
import com.learningischange.tidbitstrivia.ui.theme.Ink
import com.learningischange.tidbitstrivia.ui.theme.Pops
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

sealed interface Route {
    data object Home : Route
    data object Records : Route
    data object Create : Route
    data class Game(val mode: Mode, val category: Category, val custom: List<Question>? = null, val label: String? = null) : Route
}

@Composable
fun AppRoot(store: Store) {
    val context = LocalContext.current
    val backStack = remember { mutableStateListOf<Route>(Route.Home) }
    val current = backStack.last()
    var corpusReady by remember { mutableStateOf(Corpus.loaded) }
    LaunchedEffect(Unit) {
        if (!Corpus.loaded) runCatching { Corpus.load(context) }
        if (!Pictures.loaded) runCatching { Pictures.load(context) }
        if (!ThisOrThat.loaded) runCatching { ThisOrThat.load(context) }
        if (!ClosestCall.loaded) runCatching { ClosestCall.load(context) }
        corpusReady = true
    }

    BackHandler(enabled = backStack.size > 1) { backStack.removeAt(backStack.lastIndex) }

    val showBar = current !is Route.Game
    Scaffold(bottomBar = { if (showBar) BottomBar(current) { backStack.clear(); backStack.add(it) } }) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            when (val r = current) {
                is Route.Home -> HomeScreen { mode, cat -> backStack.add(Route.Game(mode, cat)) }
                is Route.Records -> RecordsScreen(store)
                is Route.Create -> CreateScreen { qs, label -> backStack.add(Route.Game(Mode.CLASSIC, Category.byId("mixed"), qs, label)) }
                is Route.Game -> GameScreen(r, store) { backStack.removeAt(backStack.lastIndex) }
            }
        }
    }
}

@Composable
private fun BottomBar(current: Route, onSelect: (Route) -> Unit) {
    NavigationBar {
        NavigationBarItem(current is Route.Home, { onSelect(Route.Home) }, { Icon(Icons.Filled.PlayArrow, null) }, label = { Text("Play") })
        NavigationBarItem(current is Route.Records, { onSelect(Route.Records) }, { Icon(Icons.Filled.Star, null) }, label = { Text("Records") })
        NavigationBarItem(current is Route.Create, { onSelect(Route.Create) }, { Icon(Icons.Filled.Add, null) }, label = { Text("Create") })
    }
}

// ---- Home ----

@Composable
private fun HomeScreen(onPlay: (Mode, Category) -> Unit) {
    var selectedMode by remember { mutableStateOf(Mode.CLASSIC) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text("TIDBITS", fontSize = 40.sp, fontWeight = FontWeight.Black)
        Text("Trivia from the whole of Wikipedia.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))

        ChunkyCard(fill = Pops.yellow, onClick = { onPlay(Mode.DAILY, Category.byId("mixed")) }) {
            Column(Modifier.padding(18.dp)) {
                Text("DAILY TIDBIT", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Ink)
                Text("7 questions. Everyone gets the same set. Keep your streak.", color = Ink.copy(alpha = 0.75f))
            }
        }

        Text("Pick a mode", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(listOf(Mode.CLASSIC, Mode.TIME_ATTACK, Mode.SURVIVAL, Mode.STAKE, Mode.SWEEP, Mode.PICTURE_ID, Mode.THIS_OR_THAT, Mode.CLOSEST_CALL), key = { it.name }) { m ->
                FilterChip(selected = selectedMode == m, onClick = { selectedMode = m }, label = { Text(m.title) })
            }
        }

        Text("Choose a category", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        LazyVerticalGrid(
            columns = GridCells.Fixed(2), modifier = Modifier.heightIn(max = 1000.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(14.dp),
            userScrollEnabled = false,
        ) {
            items(Category.all, key = { it.id }) { cat ->
                ChunkyCard(onClick = { onPlay(selectedMode, cat) }) {
                    Column(Modifier.padding(16.dp).height(140.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(Modifier.size(48.dp).background(Pops.at(cat.colorIndex), CircleShape), contentAlignment = Alignment.Center) { Text(cat.icon, fontSize = 24.sp) }
                        Text(cat.name, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                        Text(cat.blurb, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

// ---- Game ----

@Composable
private fun GameScreen(route: Route.Game, store: Store, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    val game = remember { GameState(route.mode, route.category, store, route.custom, route.label) }
    LaunchedEffect(Unit) { game.start() }
    LaunchedEffect(game.index, game.phase) {
        while (game.phase == GamePhase.PLAYING) { delay(100); game.tick() }
    }
    when (game.phase) {
        GamePhase.LOADING -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) { CircularProgressIndicator(); Spacer(Modifier.height(12.dp)); Text("Pulling fresh tidbits…") }
        }
        GamePhase.ERROR -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("No questions yet", fontWeight = FontWeight.Bold, fontSize = 22.sp)
                Text("Couldn't reach Wikipedia and the corpus is empty.", textAlign = TextAlign.Center)
                Button(onClick = onDone) { Text("Back") }
            }
        }
        GamePhase.FINISHED -> ResultsScreen(game, onPlayAgain = { scope.launch { game.restart() } }, onDone = onDone)
        else -> PlayingScreen(game)
    }
}

@Composable
private fun PlayingScreen(game: GameState) {
    val q = game.current ?: return
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(game.progressLabel, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            LinearProgressIndicator(progress = { game.clockFraction.toFloat() }, modifier = Modifier.weight(1f),
                color = if (game.remaining <= 5) Pops.coral else Pops.blue)
            AssistChip(onClick = {}, label = { Text("🔥 ${game.streak}") })
            AssistChip(onClick = {}, label = { Text("★ ${game.score}") })
        }
        Text(Category.byId(q.categoryId).name.uppercase(), color = Pops.at(Category.byId(q.categoryId).colorIndex), fontWeight = FontWeight.Bold, fontSize = 13.sp)
        q.imageUrl?.let { url ->
            ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.fillMaxWidth()) {
                AsyncImage(model = url, contentDescription = "Identify this",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxWidth().heightIn(max = 240.dp).padding(8.dp))
            }
        }
        Text(q.prompt, fontWeight = FontWeight.Black, fontSize = 23.sp)
        if (game.mode == Mode.SWEEP) SweepGrid(game)
        if (game.mode == Mode.STAKE && game.phase == GamePhase.PLAYING) StakeSelector(game)
        q.closest?.let { ClosestPanel(game, it) }
        val answersLocked = game.phase != GamePhase.PLAYING || (game.mode == Mode.STAKE && game.currentStake == 0)
        q.options.forEachIndexed { i, opt -> AnswerButton(opt, game.answerState(i), !answersLocked) { game.submit(i) } }
        if (game.phase == GamePhase.REVEAL) {
            ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(if (game.lastCorrect) "Nice — you knew it." else "Now you know.", fontWeight = FontWeight.Bold, fontSize = 17.sp, modifier = Modifier.weight(1f))
                        if (game.mode == Mode.STAKE) {
                            val earned = if (game.lastCorrect) "+${game.currentStake}" else "+0"
                            AssistChip(onClick = {}, label = { Text(earned, fontWeight = FontWeight.Black) })
                        }
                        if (q.closest != null) AssistChip(onClick = {}, label = { Text("+${game.lastGuessPoints}", fontWeight = FontWeight.Black) })
                    }
                    q.closest?.let { s ->
                        Text("You said ${s.fmt(game.currentGuess)} · actual ${s.formattedAnswer} · off by ${Math.abs(Math.round(game.currentGuess - s.answer))}",
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                    if (q.explanation.isNotEmpty()) Text(q.explanation)
                }
            }
            Button(onClick = { game.advance() }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Ink)) {
                Text(if (game.isLast) "See Results" else "Next")
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}

// Sweep's persistent fill-grid — one cell per question, filled mint (hit) /
// coral (miss) as you go; the current cell is ringed. The grid IS the scoreboard.
@Composable
private fun SweepGrid(game: GameState) {
    val n = game.questions.size
    val perRow = 6
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Text("Set: ${game.score} / $n", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            fontWeight = FontWeight.Bold, fontSize = 14.sp)
        var start = 0
        while (start < n) {
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                val end = minOf(start + perRow, n)
                for (i in start until end) {
                    val a = game.answered.getOrNull(i)
                    val fill = when { a == null -> MaterialTheme.colorScheme.surface; a.correct -> Pops.mint; else -> Pops.coral }
                    val current = i == game.index
                    Box(Modifier.weight(1f).height(16.dp)
                        .alpha(if (a != null || current) 1f else 0.45f)
                        .background(fill, RoundedCornerShape(5.dp))
                        .border(BorderStroke(if (current) 2.5.dp else 1.5.dp, Ink), RoundedCornerShape(5.dp)))
                }
                repeat(perRow - (end - start)) { Spacer(Modifier.weight(1f)) }
            }
            start += perRow
        }
    }
}

// Closest Call (M5): M3 Slider over [min,max] + Lock In; proximity-scored.
@Composable
private fun ClosestPanel(game: GameState, spec: ClosestSpec) {
    val live = game.phase == GamePhase.PLAYING
    ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(spec.fmt(game.currentGuess), fontWeight = FontWeight.Black, fontSize = 36.sp)
            Slider(
                value = game.currentGuess.toFloat(),
                onValueChange = { game.setGuess(it.toDouble()) },
                valueRange = spec.min.toFloat()..spec.max.toFloat(),
                steps = (((spec.max - spec.min) / spec.step).toInt() - 1).coerceIn(0, 1000),
                enabled = live,
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(spec.fmt(spec.min), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                Text(spec.fmt(spec.max), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
            if (live) Button(onClick = { game.submitGuess() }, modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Pops.yellow, contentColor = Ink)) { Text("Lock In") }
        }
    }
}

@Composable
private fun StakeSelector(game: GameState) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(if (game.currentStake == 0) "How sure are you?" else "Staked: ${game.stakeLabel}",
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), fontWeight = FontWeight.Bold, fontSize = 14.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            game.stakeTiers.forEach { tier ->
                val selected = game.currentStake == tier.value
                val usable = tier.remaining > 0 || selected
                Surface(onClick = { game.setStake(tier.value) }, enabled = usable, shape = RoundedCornerShape(12.dp),
                    color = if (selected) Pops.mint else MaterialTheme.colorScheme.surface,
                    border = BorderStroke(2.5.dp, Ink),
                    modifier = Modifier.weight(1f).alpha(if (usable) 1f else 0.4f)) {
                    Column(Modifier.padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(tier.label, fontWeight = FontWeight.Black, fontSize = 15.sp)
                        Text("+${tier.value} · ${tier.remaining} left", fontWeight = FontWeight.Bold, fontSize = 11.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun AnswerButton(text: String, state: AnswerVisual, enabled: Boolean, onClick: () -> Unit) {
    val bg = when (state) { AnswerVisual.CORRECT -> Pops.mint; AnswerVisual.WRONG -> Pops.coral; else -> MaterialTheme.colorScheme.surface }
    val fg = when (state) { AnswerVisual.CORRECT, AnswerVisual.WRONG -> Color.White; else -> MaterialTheme.colorScheme.onSurface }
    Surface(onClick = onClick, enabled = enabled, shape = RoundedCornerShape(14.dp), color = bg,
        border = BorderStroke(2.5.dp, Ink), modifier = Modifier.fillMaxWidth().alpha(if (state == AnswerVisual.DIM) 0.45f else 1f)) {
        Text(text, Modifier.padding(16.dp), color = fg, fontWeight = FontWeight.Bold, fontSize = 17.sp)
    }
}

// ---- Results ----

@Composable
private fun ResultsScreen(game: GameState, onPlayAgain: () -> Unit, onDone: () -> Unit) {
    val context = LocalContext.current
    val total = game.answered.size
    val acc = if (total == 0) 0 else game.correctCount * 100 / total
    val grid = game.answered.joinToString("") { if (it.chosen == null) "⬛" else if (it.correct) "🟩" else "🟥" }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(when { acc == 100 -> "FLAWLESS!"; acc >= 80 -> "BRILLIANT"; acc >= 50 -> "NICELY DONE"; else -> "GOOD RUN" }, fontWeight = FontWeight.Black, fontSize = 22.sp)
        Text("${game.score}", fontWeight = FontWeight.Black, fontSize = 64.sp)
        Text("${game.label ?: game.mode.title} · ${game.category.name}", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatBox("${game.correctCount}/$total", "Correct", Pops.mint); StatBox("$acc%", "Accuracy", Pops.blue); StatBox("${game.maxStreak}", "Streak", Pops.coral)
        }
        ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant) {
            Column(Modifier.padding(16.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(grid, fontSize = 24.sp); Text("Spoiler-free — safe to share", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
        Button(onClick = {
            val text = "🧠 Tidbits Trivia — ${game.mode.title}\n$grid\n${game.correctCount}/$total right · ${game.score} pts · $acc%\nTrivia from all of Wikipedia."
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }, "Share"))
        }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Pops.blue)) { Text("Share Score") }
        // F2 — full missed-fact recap: every wrong answer becomes a "now you know" card.
        val missed = game.answered.filter { !it.correct }
        if (missed.isNotEmpty()) {
            Text("Tidbits to remember", fontWeight = FontWeight.Bold, fontSize = 20.sp, modifier = Modifier.fillMaxWidth())
            missed.forEach { a ->
                ChunkyCard(modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(14.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(a.q.prompt, fontWeight = FontWeight.Bold)
                        Text(a.q.answerText, color = Pops.mint, fontWeight = FontWeight.Black)
                        if (a.q.explanation.isNotEmpty()) Text(a.q.explanation, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
                    }
                }
            }
        }
        Button(onClick = onPlayAgain, modifier = Modifier.fillMaxWidth()) { Text("Play Again") }
        TextButton(onClick = onDone) { Text("Done") }
    }
}

@Composable
private fun RowScope.StatBox(value: String, label: String, tint: Color) {
    ChunkyCard(fill = tint.copy(alpha = 0.18f), modifier = Modifier.weight(1f)) {
        Column(Modifier.padding(vertical = 16.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(value, fontWeight = FontWeight.Black, fontSize = 22.sp)
            Text(label.uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
    }
}

// ---- Records ----

@Composable
private fun RecordsScreen(store: Store) {
    val records = remember { store.records() }
    val streak = remember { store.streak() }
    val life = remember { store.lifetime() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Records", fontSize = 30.sp, fontWeight = FontWeight.Black)
        if (records.isEmpty()) {
            ChunkyCard { Column(Modifier.padding(20.dp)) { Text("No games yet", fontWeight = FontWeight.Bold); Text("Play a round and your scores and streaks show up here.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)) } }
            return@Column
        }
        ChunkyCard(fill = Pops.yellow) {
            Row(Modifier.padding(18.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column { Text("DAILY STREAK", color = Ink.copy(alpha = 0.7f), fontSize = 12.sp); Text("${streak.first} days", fontWeight = FontWeight.Black, fontSize = 26.sp, color = Ink) }
                Text("best ${streak.second} 🔥", color = Ink, fontWeight = FontWeight.Bold)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatBox("${life.first}", "Games", Pops.grape); StatBox("${life.third}%", "Lifetime", Pops.blue); StatBox("${life.second}", "Right", Pops.mint)
        }
        val prog = remember { store.progress() }
        val earned = prog.count { it.hasWedge }
        Text("Your knowledge", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Box(contentAlignment = Alignment.Center) {
                    PieProgress(prog, Modifier.size(104.dp))
                    Box(Modifier.size(44.dp).background(MaterialTheme.colorScheme.surfaceVariant, CircleShape).border(2.dp, Ink, CircleShape), contentAlignment = Alignment.Center) {
                        Text("$earned/7", fontWeight = FontWeight.Black, fontSize = 17.sp)
                    }
                }
                Text(if (earned == 7) "Full pie — every domain mastered. That breadth is yours to keep."
                     else "Earn a wedge in each domain by answering its questions well. The pie fills only when you cover them all.",
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), modifier = Modifier.weight(1f))
            }
        }
        prog.filter { it.total > 0 }.forEach { TopicRow(it) }
        val calib = remember { store.calibration() }
        if (calib.values.any { it.second > 0 }) {
            Text("Your calibration", fontWeight = FontWeight.Bold, fontSize = 20.sp)
            Text("From Stake rounds: how often each confidence level actually landed. Well-calibrated means your hit-rate climbs with your confidence.",
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            STAKE_BUDGET.filter { (calib[it.value]?.second ?: 0) > 0 }.forEach { t ->
                val o = calib[t.value]!!; val pct = o.first * 100 / o.second
                ChunkyCard {
                    Row(Modifier.padding(12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(t.label, fontWeight = FontWeight.Bold, modifier = Modifier.width(64.dp))
                        Box(Modifier.weight(1f).height(16.dp).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(999.dp)).border(2.dp, Ink, RoundedCornerShape(999.dp))) {
                            Box(Modifier.fillMaxWidth((o.first.toFloat() / o.second).coerceIn(0.05f, 1f)).fillMaxHeight().background(Pops.mint, RoundedCornerShape(999.dp)))
                        }
                        Text("${o.first}/${o.second} · $pct%", fontWeight = FontWeight.Black, fontSize = 13.sp)
                    }
                }
            }
        }
        Text("Personal bests", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Mode.entries.forEach { m ->
            val b = store.bestScore(m.name)
            if (b > 0) ChunkyCard { Row(Modifier.padding(14.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) { Text(m.title, fontWeight = FontWeight.Bold); Text("$b", fontWeight = FontWeight.Black, fontSize = 20.sp) } }
        }
        Spacer(Modifier.height(24.dp))
    }
}

// The Pie — seven equal wedges, one per domain; earned wedges show their
// category color, unearned ones are dim (SOLO-BACKLOG M3).
@Composable
private fun PieProgress(domains: List<DomainProgress>, modifier: Modifier = Modifier) {
    val n = domains.size.coerceAtLeast(1)
    Canvas(modifier) {
        val sweep = 360f / n
        domains.forEachIndexed { i, d ->
            val start = -90f + i * sweep
            val col = if (d.hasWedge) Pops.at(Category.byId(d.id).colorIndex) else Color(0xFFE8DCC2)
            drawArc(col, start, sweep, useCenter = true)
            drawArc(Ink, start, sweep, useCenter = true, style = Stroke(width = 4f))
        }
    }
}

// One domain's depth: icon, name, wedge check, level badge, XP bar (M4).
@Composable
private fun TopicRow(d: DomainProgress) {
    val c = Category.byId(d.id); val col = Pops.at(c.colorIndex)
    ChunkyCard {
        Row(Modifier.padding(12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(36.dp).background(col, CircleShape).border(2.5.dp, Ink, CircleShape), contentAlignment = Alignment.Center) {
                Text(c.icon, fontSize = 16.sp)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(c.name, fontWeight = FontWeight.Bold)
                    if (d.hasWedge) Text("✓", color = Pops.mint, fontWeight = FontWeight.Black)
                    Spacer(Modifier.weight(1f))
                    Surface(color = col, shape = RoundedCornerShape(999.dp), border = BorderStroke(2.dp, Ink)) {
                        Text("Lvl ${d.level}", color = Color.White, fontWeight = FontWeight.Black, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 9.dp, vertical = 2.dp))
                    }
                }
                Box(Modifier.fillMaxWidth().height(12.dp).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(999.dp)).border(2.dp, Ink, RoundedCornerShape(999.dp))) {
                    Box(Modifier.fillMaxWidth(d.levelProgress.coerceIn(0.05f, 1f)).fillMaxHeight().background(col, RoundedCornerShape(999.dp)))
                }
            }
        }
    }
}

// ---- Create ----

@Composable
private fun CreateScreen(onPlay: (List<Question>, String) -> Unit) {
    var topic by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val suggestions = listOf("Space exploration", "Ancient Rome", "Jazz", "Volcanoes", "The Olympics", "Marie Curie")
    fun generate(t: String) {
        if (t.trim().length < 2 || working) return
        working = true; error = null
        scope.launch {
            val qs = Wikipedia.generate(t.trim(), "mixed", 8)
            working = false
            if (qs.size >= 3) onPlay(qs, t.trim()) else error = "Couldn't build a good quiz for “${t.trim()}”. Try a broader subject."
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Create a quiz", fontSize = 30.sp, fontWeight = FontWeight.Black)
        Text("Pick any subject. We'll pull it from Wikipedia and build you a quiz.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        OutlinedTextField(topic, { topic = it }, label = { Text("e.g. The Renaissance") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Button(onClick = { generate(topic) }, enabled = !working, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Pops.grape)) {
            if (working) { CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp); Spacer(Modifier.width(10.dp)); Text("Building your quiz…") } else Text("Generate Quiz")
        }
        error?.let { Text(it, color = Pops.coral) }
        Text("Need a spark?", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(suggestions, key = { it }) { s -> AssistChip(onClick = { topic = s; generate(s) }, label = { Text(s) }) }
        }
    }
}

// ---- Reusable chunky card ----

@Composable
private fun ChunkyCard(modifier: Modifier = Modifier, fill: Color = MaterialTheme.colorScheme.surface, onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val base = modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)
    Surface(shape = RoundedCornerShape(18.dp), color = fill, border = BorderStroke(2.5.dp, Ink), modifier = base) { content() }
}
