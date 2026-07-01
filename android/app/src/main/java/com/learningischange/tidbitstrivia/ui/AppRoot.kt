package com.learningischange.tidbitstrivia.ui

import android.content.Intent
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import coil3.compose.AsyncImage
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.*
import com.learningischange.tidbitstrivia.ui.theme.Ink
import com.learningischange.tidbitstrivia.ui.theme.Pops
import com.learningischange.tidbitstrivia.ui.theme.accentText
import com.learningischange.tidbitstrivia.ui.theme.onAccent
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

sealed interface Route {
    data object Home : Route
    data object Records : Route
    data object Create : Route
    data class Game(val mode: Mode, val category: Category, val custom: List<Question>? = null, val label: String? = null, val nightRounds: List<Pair<String, Int>>? = null) : Route
    data object NightSetup : Route
    data object NightJoin : Route
    data object NightLive : Route
    data object Settings : Route
    data object Party : Route
}

@Composable
fun AppRoot(
    store: Store,
    dynamicColor: Boolean = false,
    onDynamicColor: (Boolean) -> Unit = {},
    deepLink: String? = null,
    onDeepLinkConsumed: () -> Unit = {},
) {
    val context = LocalContext.current
    val backStack = remember { mutableStateListOf<Route>(Route.Home) }
    val current = backStack.last()
    var corpusReady by remember { mutableStateOf(Corpus.loaded) }
    var onboarded by remember { mutableStateOf(store.hasOnboarded()) }
    // The live networked Trivia Night (Decision 033), created on Host/Join.
    var live by remember { mutableStateOf<LiveNight?>(null) }
    // NSD discovery needs NEARBY_WIFI_DEVICES on Android 13+; request on Host/Join.
    val nearbyPerm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    fun ensureNearby() { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) nearbyPerm.launch(android.Manifest.permission.NEARBY_WIFI_DEVICES) }
    LaunchedEffect(Unit) {
        if (!Corpus.loaded) runCatching { Corpus.load(context) }
        if (!Pictures.loaded) runCatching { Pictures.load(context) }
        if (!ThisOrThat.loaded) runCatching { ThisOrThat.load(context) }
        if (!ClosestCall.loaded) runCatching { ClosestCall.load(context) }
        if (!OrderingSet.loaded) runCatching { OrderingSet.load(context) }
        if (!MatchingSet.loaded) runCatching { MatchingSet.load(context) }
        if (!TypeAnswerSet.loaded) runCatching { TypeAnswerSet.load(context) }
        if (!OddOneOutSet.loaded) runCatching { OddOneOutSet.load(context) }
        if (!EnumerateSet.loaded) runCatching { EnumerateSet.load(context) }
        if (!Difficulty.loaded) runCatching { Difficulty.load(context) }
        corpusReady = true
    }

    // Deep-link inbox (parity with iOS .onOpenURL): MainActivity hands the
    // parsed host here; we route then mark consumed. Unknown links open Home.
    LaunchedEffect(deepLink) {
        when (deepLink) {
            null -> {}
            "daily" -> { backStack.clear(); backStack.add(Route.Home); backStack.add(Route.Game(Mode.DAILY, Category.byId("mixed"))) }
            "night" -> { backStack.clear(); backStack.add(Route.Home); backStack.add(Route.NightSetup) }
            "party" -> { backStack.clear(); backStack.add(Route.Home); backStack.add(Route.Party) }
            "create" -> { backStack.clear(); backStack.add(Route.Create) }
            "settings" -> { backStack.clear(); backStack.add(Route.Home); backStack.add(Route.Settings) }
            else -> { backStack.clear(); backStack.add(Route.Home) }
        }
        if (deepLink != null) onDeepLinkConsumed()
    }

    BackHandler(enabled = backStack.size > 1) { backStack.removeAt(backStack.lastIndex) }

    val showBar = current is Route.Home || current is Route.Records || current is Route.Create
    Box(Modifier.fillMaxSize()) {
        Scaffold(bottomBar = { if (showBar) BottomBar(current) { backStack.clear(); backStack.add(it) } }) { pad ->
            Box(Modifier.padding(pad).fillMaxSize()) {
                when (val r = current) {
                    is Route.Home -> HomeScreen(
                        onPlay = { mode, cat -> backStack.add(Route.Game(mode, cat)) },
                        onNight = { backStack.add(Route.NightSetup) },
                        onParty = { backStack.add(Route.Party) },
                        onJoinNight = { ensureNearby(); backStack.add(Route.NightJoin) },
                        onSettings = { backStack.add(Route.Settings) },
                    )
                    is Route.NightSetup -> NightSetupScreen(
                        onStartSolo = { rounds, cat, label -> backStack.removeAt(backStack.lastIndex); backStack.add(Route.Game(Mode.BAR_TRIVIA, cat, label = label, nightRounds = rounds)) },
                        onHost = { rounds, cat, _ ->
                            ensureNearby()
                            live = LiveNight.host(store, context, rounds, cat.id, hostName = "Host")
                            backStack.removeAt(backStack.lastIndex); backStack.add(Route.NightLive)
                        },
                        onCancel = { backStack.removeAt(backStack.lastIndex) },
                    )
                    is Route.NightJoin -> NightJoinScreen(
                        initialCode = store.lastNightCode(),
                        initialName = store.lastNightName(),
                        onJoin = { code, name ->
                            val l = LiveNight.join(store, context); live = l; l.join(code, name)
                            backStack.removeAt(backStack.lastIndex); backStack.add(Route.NightLive)
                        },
                        onCancel = { backStack.removeAt(backStack.lastIndex) },
                    )
                    is Route.NightLive -> live?.let { l ->
                        BackHandler { l.end(); live = null; backStack.removeAt(backStack.lastIndex) }
                        NightContainer(l, store) { l.end(); live = null; backStack.clear(); backStack.add(Route.Home) }
                    } ?: Box(Modifier.fillMaxSize())
                    is Route.Records -> RecordsScreen(store)
                    is Route.Create -> CreateScreen { qs, label -> backStack.add(Route.Game(Mode.CLASSIC, Category.byId("mixed"), qs, label)) }
                    is Route.Game -> GameScreen(r, store) { backStack.removeAt(backStack.lastIndex) }
                    is Route.Settings -> SettingsScreen(store, dynamicColor, onDynamicColor)
                    is Route.Party -> PartyContainer(store) { backStack.removeAt(backStack.lastIndex) }
                }
            }
        }
        // First-run onboarding overlays everything (incl. the bottom bar).
        if (!onboarded) OnboardingScreen { store.setOnboarded(true); onboarded = true }
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
private fun HomeScreen(onPlay: (Mode, Category) -> Unit, onNight: () -> Unit, onParty: () -> Unit, onJoinNight: () -> Unit, onSettings: () -> Unit) {
    var selectedMode by remember { mutableStateOf(Mode.CLASSIC) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("TIDBITS", fontSize = 40.sp, fontWeight = FontWeight.Black)
                Text("Trivia from the whole of Wikipedia.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
            IconButton(onClick = onSettings) { Icon(Icons.Filled.Settings, contentDescription = "Settings") }
        }

        ChunkyCard(fill = Pops.yellow, onClick = { onPlay(Mode.DAILY, Category.byId("mixed")) }) {
            Column(Modifier.padding(18.dp)) {
                Text("DAILY TIDBIT", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Ink)
                Text("7 questions. Everyone gets the same set. Keep your streak.", color = Ink.copy(alpha = 0.75f))
            }
        }

        ChunkyCard(fill = Pops.coral, onClick = onNight) {
            Column(Modifier.padding(18.dp)) {
                Text("TRIVIA NIGHT", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Color.White)
                Text("Host a night of mixed rounds — every kind of question.", color = Color.White.copy(alpha = 0.85f))
                Spacer(Modifier.height(10.dp))
                Surface(onClick = onJoinNight, shape = RoundedCornerShape(999.dp), color = Color.White) {
                    Text("Join a night →", Modifier.padding(horizontal = 14.dp, vertical = 7.dp),
                        fontWeight = FontWeight.Bold, color = Pops.coral, fontSize = 14.sp)
                }
            }
        }

        ChunkyCard(fill = Pops.grape, onClick = onParty) {
            Column(Modifier.padding(18.dp)) {
                Text("PASS & PLAY", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Color.White)
                Text("2–4 players, one phone, the same questions. Take turns.", color = Color.White.copy(alpha = 0.85f))
            }
        }

        Text("Pick a mode", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(listOf(Mode.CLASSIC, Mode.TIME_ATTACK, Mode.SURVIVAL, Mode.STAKE, Mode.SWEEP, Mode.PICTURE_ID, Mode.THIS_OR_THAT, Mode.CLOSEST_CALL, Mode.ORDERING, Mode.MATCHING, Mode.TYPE_ANSWER, Mode.ODD_ONE_OUT, Mode.LADDER), key = { it.name }) { m ->
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

// ---- Trivia Night setup ----

@Composable
private fun NightSetupScreen(
    onStartSolo: (List<Pair<String, Int>>, Category, String) -> Unit,
    onHost: (List<Pair<String, Int>>, Category, String) -> Unit,
    onCancel: () -> Unit,
) {
    var preset by remember { mutableStateOf(1) }
    var cat by remember { mutableStateOf(Category.byId("mixed")) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Trivia Night", fontSize = 28.sp, fontWeight = FontWeight.Black)
        Text("A night of mixed rounds — every kind of question. Each answer ends on a fact to learn.",
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        Text("Format", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Night.presets.forEachIndexed { i, p ->
            ChunkyCard(fill = if (preset == i) Pops.coral.copy(alpha = 0.16f) else MaterialTheme.colorScheme.surface, onClick = { preset = i }) {
                Column(Modifier.padding(14.dp)) {
                    Text(p.name, fontWeight = FontWeight.Black, fontSize = 17.sp)
                    Text(p.blurb, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                }
            }
        }
        Text("Category", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(Category.all, key = { it.id }) { c ->
                FilterChip(selected = cat.id == c.id, onClick = { cat = c }, label = { Text(c.name) })
            }
        }
        Button(onClick = { val p = Night.presets[preset]; onHost(p.rounds, cat, p.name) }, modifier = Modifier.fillMaxWidth().height(52.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) {
            Text("Host for others (Apple or Android)", fontWeight = FontWeight.Bold)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(onClick = onCancel) { Text("Cancel") }
            OutlinedButton(onClick = { val p = Night.presets[preset]; onStartSolo(p.rounds, cat, p.name) }, modifier = Modifier.weight(1f)) { Text("Play here (solo)") }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun NightJoinScreen(initialCode: String, initialName: String, onJoin: (String, String) -> Unit, onCancel: () -> Unit) {
    var code by remember { mutableStateOf(initialCode) }
    var name by remember { mutableStateOf(initialName) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Join a Trivia Night", fontSize = 28.sp, fontWeight = FontWeight.Black)
        Text("On the same Wi-Fi as the host. Works whether they're on Apple or Android.",
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        OutlinedTextField(
            value = code, onValueChange = { code = it.uppercase().filter { c -> c.isLetterOrDigit() }.take(4) },
            label = { Text("Room code") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
        )
        OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Your name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(onClick = onCancel) { Text("Cancel") }
            Button(onClick = { onJoin(code, name) }, enabled = code.length == 4, modifier = Modifier.weight(1f),
                colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Join") }
        }
    }
}

// ---- Game ----

@Composable
private fun GameScreen(route: Route.Game, store: Store, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    val haptics = rememberGameHaptics(store)
    val game = remember { GameState(route.mode, route.category, store, route.custom, route.label, route.nightRounds) }
    LaunchedEffect(Unit) { game.start() }
    LaunchedEffect(game.index, game.phase) {
        while (game.phase == GamePhase.PLAYING) { delay(100); game.tick() }
    }
    // Correct/wrong haptics fire once per question when the reveal lands.
    LaunchedEffect(game.index, game.phase) {
        if (game.phase == GamePhase.REVEAL) { if (game.lastCorrect) haptics.correct() else haptics.wrong() }
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
internal fun PlayingScreen(game: GameState) {
    val q = game.current ?: return
    val live = game.phase == GamePhase.PLAYING && !game.awaitingReveal   // accepting input
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(game.progressLabel, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            LinearProgressIndicator(progress = { game.clockFraction.toFloat() }, modifier = Modifier.weight(1f),
                color = if (game.remaining <= 5) Pops.coral else Pops.blue)
            AssistChip(onClick = {}, label = { Text("🔥 ${game.streak}") })
            AssistChip(onClick = {}, label = { Text("★ ${game.score}") })
        }
        if (game.mode == Mode.BAR_TRIVIA && game.currentRoundTitle != null) {
            ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("ROUND ${game.currentRoundNumber} OF ${game.roundCount}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                        Text(game.currentRoundTitle!!.uppercase(), fontWeight = FontWeight.Black, fontSize = 16.sp)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        repeat(game.roundCount) { i ->
                            Box(Modifier.size(9.dp).background(if (i == game.currentRoundNumber - 1) Pops.coral else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.2f), CircleShape))
                        }
                    }
                }
            }
        }
        Text(Category.byId(q.categoryId).name.uppercase(), color = accentText(Pops.at(Category.byId(q.categoryId).colorIndex)), fontWeight = FontWeight.Bold, fontSize = 13.sp)
        q.imageUrl?.let { url ->
            ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.fillMaxWidth()) {
                AsyncImage(model = url, contentDescription = "Identify this",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxWidth().heightIn(max = 240.dp).padding(8.dp))
            }
        }
        Text(q.prompt, fontWeight = FontWeight.Black, fontSize = 23.sp)
        if (game.mode == Mode.SWEEP) SweepGrid(game)
        if (game.mode == Mode.STAKE && live) StakeSelector(game)
        q.closest?.let { ClosestPanel(game, it) }
        if (q.ordering != null) OrderingPanel(game)
        q.matching?.let { MatchingPanel(game, it) }
        if (q.accepted != null && live) {
            OutlinedTextField(
                value = game.typedText, onValueChange = { game.typedText = it },
                placeholder = { Text("Type your answer…") }, singleLine = true,
                keyboardActions = KeyboardActions(onDone = { game.submitText() }),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done, capitalization = KeyboardCapitalization.Words),
                modifier = Modifier.fillMaxWidth())
            Button(onClick = { game.submitText() }, enabled = game.typedText.isNotBlank(), modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Pops.mint, contentColor = Ink)) { Text("Submit") }
        }
        q.enumerate?.let { spec -> if (live) EnumeratePanel(game, spec) }
        val answersLocked = !live || (game.mode == Mode.STAKE && game.currentStake == 0)
        q.options.forEachIndexed { i, opt -> AnswerButton(opt, game.answerState(i), !answersLocked) { game.submit(i) } }
        if (game.awaitingReveal) {
            ChunkyCard(fill = Pops.blue.copy(alpha = 0.14f)) {
                Text("Locked in — waiting for the host…", Modifier.padding(16.dp).fillMaxWidth(),
                    fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, color = accentText(Pops.blue))
            }
        }
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
                        if (q.ordering != null) AssistChip(onClick = {}, label = { Text("+${game.lastOrderPoints}", fontWeight = FontWeight.Black) })
                        if (q.matching != null) AssistChip(onClick = {}, label = { Text("+${game.lastMatchPoints}", fontWeight = FontWeight.Black) })
                    }
                    q.closest?.let { s ->
                        Text("You said ${s.fmt(game.currentGuess)} · actual ${s.formattedAnswer} · off by ${Math.abs(Math.round(game.currentGuess - s.answer))}",
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                    if (q.accepted != null) Text("Answer: ${q.answerText}", fontWeight = FontWeight.Bold)
                    q.enumerate?.let { spec -> EnumerateReveal(game, spec) }
                    if (q.explanation.isNotEmpty()) Text(q.explanation)
                    if (game.mode == Mode.BAR_TRIVIA && game.nextRoundTitle != null)
                        Text("🏁 Round ${game.currentRoundNumber} complete · up next: ${game.nextRoundTitle}",
                            color = accentText(Pops.coral), fontWeight = FontWeight.Bold)
                }
            }
            // Self-paced advances here; a networked night is advanced by the host (below the game).
            if (!game.hostPaced) Button(onClick = { game.advance() }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Ink, contentColor = Color.White)) {
                Text(if (game.isLast) "See Results" else if (game.nextRoundTitle != null) "Start ${game.nextRoundTitle}" else "Next")
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}

// Enumeration (Q8): a live counter + text field; each unique correct answer
// fills a chip. The list you fill IS the score (count-scored, like Sweep).
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EnumeratePanel(game: GameState, spec: EnumSpec) {
    var input by remember(game.index) { mutableStateOf("") }
    val submit = { game.submitEnumGuess(input); input = "" }
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text("${game.enumFilled.size} / ${spec.total}", fontWeight = FontWeight.Black, fontSize = 24.sp,
            color = accentText(Pops.teal), modifier = Modifier.weight(1f))
        TextButton(onClick = { game.finishEnum() }) { Text("Done") }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        OutlinedTextField(
            value = input, onValueChange = { input = it },
            placeholder = { Text("Name one…") }, singleLine = true,
            keyboardActions = KeyboardActions(onDone = { submit() }),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done, capitalization = KeyboardCapitalization.Words),
            modifier = Modifier.weight(1f))
        Button(onClick = submit, enabled = input.isNotBlank(),
            colors = ButtonDefaults.buttonColors(containerColor = Pops.teal, contentColor = Ink)) { Text("Add") }
    }
    if (game.enumNamed.isNotEmpty()) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            game.enumNamed.forEach { name ->
                Box(Modifier.background(Pops.teal.copy(alpha = 0.18f), RoundedCornerShape(10.dp))
                    .border(BorderStroke(2.dp, Pops.teal), RoundedCornerShape(10.dp))
                    .padding(horizontal = 10.dp, vertical = 6.dp)) {
                    Text(name, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                }
            }
        }
    }
}

// Reveal the full set after a list round — named in mint, missed in muted: the
// testing-effect payload (you see exactly what you couldn't recall).
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EnumerateReveal(game: GameState, spec: EnumSpec) {
    val named = game.enumNamed.toSet()
    Text("You named ${game.enumFilled.size} of ${spec.total}", fontWeight = FontWeight.Bold)
    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        spec.displayNames.forEach { name ->
            val got = name in named
            Box(Modifier.background(if (got) Pops.mint.copy(alpha = 0.28f) else MaterialTheme.colorScheme.surface, RoundedCornerShape(8.dp))
                .padding(horizontal = 8.dp, vertical = 5.dp)) {
                Text(name, fontSize = 13.sp, fontWeight = if (got) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (got) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
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

// Matching (Q5): key rows (tap to select) + value chips (tap to link) + Submit.
@Composable
private fun MatchingPanel(game: GameState, m: MatchSpec) {
    val live = game.phase == GamePhase.PLAYING
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        m.keys.forEachIndexed { i, key ->
            val selected = game.matchSelectedKey == i
            Surface(onClick = { game.selectMatchKey(i) }, enabled = live, shape = RoundedCornerShape(12.dp),
                color = if (selected) Pops.coral.copy(alpha = 0.22f) else MaterialTheme.colorScheme.surface,
                border = BorderStroke(2.5.dp, Ink), modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(horizontal = 14.dp, vertical = 12.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text(key, fontWeight = FontWeight.Bold)
                    Text(game.matchedValue(i) ?: "tap a value →", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), fontSize = 14.sp)
                }
            }
        }
        LazyVerticalGrid(columns = GridCells.Fixed(2), modifier = Modifier.heightIn(max = 260.dp), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            itemsIndexed(game.matchValues) { j, v ->
                val used = game.matchAssign.contains(j)
                Surface(onClick = { game.assignMatchValue(j) }, enabled = live && !used, shape = RoundedCornerShape(12.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant, border = BorderStroke(2.5.dp, Ink),
                    modifier = Modifier.alpha(if (used) 0.35f else 1f)) {
                    Text(v, fontWeight = FontWeight.Bold, fontSize = 14.sp, modifier = Modifier.padding(vertical = 12.dp, horizontal = 6.dp).fillMaxWidth(), textAlign = TextAlign.Center)
                }
            }
        }
        if (live) Button(onClick = { game.submitMatch() }, modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Submit") }
    }
}

// Ordering (Q4): rows with up/down + Submit; partial credit by inversions.
@Composable
private fun OrderingPanel(game: GameState) {
    val live = game.phase == GamePhase.PLAYING
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        game.currentOrder.forEachIndexed { i, item ->
            ChunkyCard(modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("${i + 1}", fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    Text(item, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    if (live) {
                        IconButton(onClick = { game.moveOrderItem(i, true) }, enabled = i != 0) { Text("▲") }
                        IconButton(onClick = { game.moveOrderItem(i, false) }, enabled = i != game.currentOrder.lastIndex) { Text("▼") }
                    }
                }
            }
        }
        if (live) Button(onClick = { game.submitOrder() }, modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Pops.blue, contentColor = Color.White)) { Text("Submit Order") }
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
                    // Ink on the mint selected fill (not theme onSurface, which goes light in dark mode).
                    val tierFg = if (selected) Ink else MaterialTheme.colorScheme.onSurface
                    Column(Modifier.padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(tier.label, color = tierFg, fontWeight = FontWeight.Black, fontSize = 15.sp)
                        Text("+${tier.value} · ${tier.remaining} left", color = tierFg, fontWeight = FontWeight.Bold, fontSize = 11.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun AnswerButton(text: String, state: AnswerVisual, enabled: Boolean, onClick: () -> Unit) {
    val bg = when (state) { AnswerVisual.CORRECT -> Pops.mint; AnswerVisual.WRONG -> Pops.coral; else -> MaterialTheme.colorScheme.surface }
    // Ink on the light mint (white-on-mint is ~1.6:1); white on the deeper coral.
    val fg = when (state) { AnswerVisual.CORRECT -> Ink; AnswerVisual.WRONG -> Color.White; else -> MaterialTheme.colorScheme.onSurface }
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
            val text = "🧠 Tidbits Trivia — ${game.mode.title}\n$grid\n${game.correctCount}/$total right · ${game.score} pts · $acc%\nTrivia from all of Wikipedia.\nhttps://tidbitstrivia.com"
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }, "Share"))
        }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Pops.blue, contentColor = Color.White)) { Text("Share Score") }
        // F2 — full missed-fact recap: every wrong answer becomes a "now you know" card.
        val missed = game.answered.filter { !it.correct }
        if (missed.isNotEmpty()) {
            Text("Tidbits to remember", fontWeight = FontWeight.Bold, fontSize = 20.sp, modifier = Modifier.fillMaxWidth())
            missed.forEach { a ->
                ChunkyCard(modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(14.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(a.q.prompt, fontWeight = FontWeight.Bold)
                        Text(a.q.answerText, color = accentText(Pops.mint), fontWeight = FontWeight.Black)
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
                    if (d.hasWedge) Text("✓", color = accentText(Pops.mint), fontWeight = FontWeight.Black)
                    Spacer(Modifier.weight(1f))
                    Surface(color = col, shape = RoundedCornerShape(999.dp), border = BorderStroke(2.dp, Ink)) {
                        Text("Lvl ${d.level}", color = onAccent(col), fontWeight = FontWeight.Black, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 9.dp, vertical = 2.dp))
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
        Button(onClick = { generate(topic) }, enabled = !working, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Pops.grape, contentColor = Color.White)) {
            if (working) { CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp); Spacer(Modifier.width(10.dp)); Text("Building your quiz…") } else Text("Generate Quiz")
        }
        error?.let { Text(it, color = accentText(Pops.coral)) }
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
