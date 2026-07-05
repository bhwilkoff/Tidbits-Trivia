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
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.graphics.vector.ImageVector
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
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import com.learningischange.tidbitstrivia.data.PlayerIdentity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.*
import com.learningischange.tidbitstrivia.net.FirebaseNet
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
    data class Game(val mode: Mode, val category: Category, val custom: List<Question>? = null, val label: String? = null, val nightRounds: List<Pair<String, Int>>? = null, val dailyDay: String? = null, val mixModes: List<Mode>? = null, val duelId: String? = null) : Route
    data class Versus(val botId: String) : Route
    object OnlineMatch : Route
    data object NightSetup : Route
    data object NightJoin : Route
    data object NightLive : Route
    data class LiveRoom(val code: String, val name: String) : Route
    data class LiveHost(val rounds: List<Pair<String, Int>>, val category: Category) : Route
    data object Settings : Route
    data object Profile : Route
    data object Leaderboard : Route   // Wave E: cross-venue / season standings
    data object Duels : Route          // L5: async friend duels
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
    val rootScope = rememberCoroutineScope()
    val backStack = remember { mutableStateListOf<Route>(Route.Home) }
    val current = backStack.last()
    var corpusReady by remember { mutableStateOf(Corpus.loaded) }
    var onboarded by remember { mutableStateOf(store.hasOnboarded()) }
    // The live networked Trivia Night (Decision 033), created on Host/Join.
    var live by remember { mutableStateOf<LiveNight?>(null) }
    // NSD discovery needs NEARBY_WIFI_DEVICES on Android 13+; request on Host/Join.
    val nearbyPerm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    fun ensureNearby() { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) nearbyPerm.launch(android.Manifest.permission.NEARBY_WIFI_DEVICES) }
    // (L2) Sync the daily log whenever signed in — pull the cross-device union (and push
    // any local anon plays so nothing is lost). Fires on boot-when-signed-in and on sign-in.
    LaunchedEffect(com.learningischange.tidbitstrivia.data.PlayerIdentity.signedIn) {
        if (com.learningischange.tidbitstrivia.data.PlayerIdentity.signedIn)
            com.learningischange.tidbitstrivia.data.PlayerIdentity.syncDailyLog(store, pushLocal = true)
    }
    LaunchedEffect(Unit) {
        com.learningischange.tidbitstrivia.data.PlayerIdentity.bootstrap()   // stable uid → portable profile
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
                        store = store,
                        onPlay = { mode, cat -> backStack.add(Route.Game(mode, cat)) },
                        onPlayMix = { modes, cat -> backStack.add(Route.Game(Mode.MIX, cat, mixModes = modes)) },
                        onPlayDaily = { day -> backStack.add(Route.Game(Mode.DAILY, Category.byId("mixed"), dailyDay = day)) },
                        onVersus = { id -> backStack.add(Route.Versus(id)) },
                        onQuickMatch = { backStack.add(Route.OnlineMatch) },
                        onNight = { backStack.add(Route.NightSetup) },
                        onParty = { backStack.add(Route.Party) },
                        onJoinNight = { ensureNearby(); backStack.add(Route.NightJoin) },
                        onCreate = { backStack.clear(); backStack.add(Route.Create) },
                        onSettings = { backStack.add(Route.Settings) },
                    )
                    is Route.NightSetup -> NightSetupScreen(
                        onStartSolo = { rounds, cat, label -> backStack.removeAt(backStack.lastIndex); backStack.add(Route.Game(Mode.BAR_TRIVIA, cat, label = label, nightRounds = rounds)) },
                        onHost = { rounds, cat, _ ->
                            // Owner architecture: host on the shared RTDB backend (any
                            // platform + web can join), not the old local mDNS night.
                            backStack.removeAt(backStack.lastIndex); backStack.add(Route.LiveHost(rounds, cat))
                        },
                        onCancel = { backStack.removeAt(backStack.lastIndex) },
                    )
                    is Route.NightJoin -> NightJoinScreen(
                        initialCode = store.lastNightCode(),
                        initialName = store.lastNightName(),
                        // Unified join on the shared RTDB backend: the screen probes
                        // live/{code}; a hit opens the Live player (Tidbits Live event
                        // OR a Trivia Night — same backend), a miss is a clear not-found.
                        onFound = { code, name ->
                            store.rememberNight(code, name)
                            backStack.removeAt(backStack.lastIndex); backStack.add(Route.LiveRoom(code, name))
                        },
                        onCancel = { backStack.removeAt(backStack.lastIndex) },
                    )
                    is Route.LiveRoom -> LiveRoomScreen(r.code, r.name) {
                        backStack.removeAt(backStack.lastIndex)
                    }
                    is Route.LiveHost -> NightHostScreen(r.rounds, r.category, store) {
                        backStack.removeAt(backStack.lastIndex)
                    }
                    is Route.NightLive -> live?.let { l ->
                        BackHandler { l.end(); live = null; backStack.removeAt(backStack.lastIndex) }
                        NightContainer(l, store) { l.end(); live = null; backStack.clear(); backStack.add(Route.Home) }
                    } ?: Box(Modifier.fillMaxSize())
                    is Route.Records -> RecordsScreen(store)
                    is Route.Create -> CreateScreen { qs, label -> backStack.add(Route.Game(Mode.MIX, Category.byId("mixed"), qs, label)) }
                    is Route.Game -> GameScreen(r, store) { backStack.removeAt(backStack.lastIndex) }
                    is Route.Versus -> VersusScreen(r.botId, store) { backStack.removeAt(backStack.lastIndex) }
                    is Route.OnlineMatch -> OnlineMatchScreen(store) { backStack.removeAt(backStack.lastIndex) }
                    is Route.Settings -> SettingsScreen(store, dynamicColor, onDynamicColor, onProfile = { backStack.add(Route.Profile) })
                    is Route.Profile -> ProfileScreen(onBack = { backStack.removeLastOrNull() }, onLeaderboard = { backStack.add(Route.Leaderboard) }, onDuels = { backStack.add(Route.Duels) })
                    is Route.Leaderboard -> LeaderboardScreen(onBack = { backStack.removeLastOrNull() })
                    is Route.Duels -> DuelsScreen(onBack = { backStack.removeLastOrNull() }, onPlay = { id, qs -> backStack.add(Route.Game(Mode.MIX, Category.byId("mixed"), qs, "Duel", duelId = id)) })
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

// Home (rule R-HOME-1): ONE primary action — Quick Play — with mode/category
// selection behind a Customize sheet. See docs/HOME-REDESIGN-PROPOSAL.md.
@Composable
private fun HomeScreen(
    store: Store,
    onPlay: (Mode, Category) -> Unit,
    onPlayMix: (List<Mode>, Category) -> Unit,
    onPlayDaily: (String) -> Unit,
    onVersus: (String) -> Unit,
    onQuickMatch: () -> Unit,
    onNight: () -> Unit,
    onParty: () -> Unit,
    onJoinNight: () -> Unit,
    onCreate: () -> Unit,
    onSettings: () -> Unit,
) {
    var showCustomize by remember { mutableStateOf(false) }
    var showNight by remember { mutableStateOf(false) }
    var showDailyArchive by remember { mutableStateOf(false) }
    var showMultiplayer by remember { mutableStateOf(false) }
    val (qpMode, qpCat) = store.quickPlay()
    val firstRun = !store.hasQuickPlayHistory()
    val fade = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)

    fun play(mode: Mode, cat: Category) { store.rememberPlay(mode, cat); onPlay(mode, cat) }
    fun playMix(modes: List<Mode>, cat: Category) {
        if (modes.size == 1) { play(modes[0], cat); return }
        store.rememberMix(modes, cat); onPlayMix(modes, cat)
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("TIDBITS", fontSize = 40.sp, fontWeight = FontWeight.Black)
                Text("Trivia from the whole of Wikipedia.", color = fade)
            }
            IconButton(onClick = onSettings) { Icon(Icons.Filled.Settings, contentDescription = "Settings") }
        }

        // Quick Play — ONE action, one target (R-HOME-1a, Decision 036).
        ChunkyCard(fill = Pops.coral, onClick = {
            if (qpMode == Mode.MIX) playMix(store.lastMixModes(), qpCat) else play(qpMode, qpCat)
        }) {
            Column(Modifier.padding(20.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(30.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("QUICK PLAY", fontWeight = FontWeight.Black, fontSize = 28.sp, color = Color.White)
                }
                Spacer(Modifier.height(6.dp))
                Text("${qpMode.title.uppercase()} · ${qpCat.name.uppercase()}", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                Text(if (firstRun) "Tap to play — customize anytime" else "Jump straight into a round",
                    color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp)
            }
        }

        // Surprise + Customize — the quiet secondary pair under the hero (R-HOME-1a).
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = { val (m, c) = store.surprise(); play(m, c) }, modifier = Modifier.weight(1f)) {
                Icon(Icons.Filled.Casino, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Surprise me", fontWeight = FontWeight.Bold)
            }
            OutlinedButton(onClick = { showCustomize = true }, modifier = Modifier.weight(1f)) {
                Icon(Icons.Filled.Tune, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Customize", fontWeight = FontWeight.Bold)
            }
        }

        // Daily — play-once (R-DAILY-1): locked once done; tap then opens the archive.
        val todayScore = run { com.learningischange.tidbitstrivia.data.PlayerIdentity.dailyLogRev; store.dailyScore(dayKey()) }
        ChunkyCard(fill = Pops.yellow, onClick = {
            if (todayScore != null) showDailyArchive = true else onPlay(Mode.DAILY, Category.byId("mixed"))
        }) {
            Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (todayScore == null) Icons.Filled.WbSunny else Icons.Filled.Verified,
                    null, tint = Ink, modifier = Modifier.size(30.dp))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("DAILY TIDBIT", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Ink)
                    val dayStreak = PlayerIdentity.profile?.streak?.current ?: 0
                    if (todayScore != null) {
                        Text("Done for today — you scored $todayScore.${if (dayStreak >= 2) " 🔥 $dayStreak-day streak kept alive." else ""} New set tomorrow.", color = Ink.copy(alpha = 0.75f), fontSize = 13.sp)
                        Text("Play previous days", color = Ink, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                    } else {
                        Text(if (dayStreak >= 2) "🔥 $dayStreak-day streak — play today's 7 to keep it going" else "7 questions. Everyone gets the same set. Start your streak.", color = Ink.copy(alpha = 0.75f), fontSize = 13.sp)
                    }
                }
                Icon(Icons.Filled.KeyboardArrowRight, null, tint = Ink)
            }
        }

        // Trivia Night — one unified entry → host/join sheet.
        ChunkyCard(fill = Pops.coral, onClick = { showNight = true }) {
            Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Celebration, null, tint = Color.White, modifier = Modifier.size(28.dp))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("TRIVIA NIGHT", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Color.White)
                    Text("Host or join a night of mixed rounds.", color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp)
                }
                Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.White)
            }
        }

        Text("More ways to play", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            HomeTile(Icons.Filled.Group, "Pass & Play", Pops.grape, Modifier.weight(1f), onParty)
            // Live surface now (Decision 038): v0 Play-vs-CPU inside; the
            // Quick Match row is the honest v1 slot.
            HomeTile(Icons.Filled.Public, "Online Multiplayer", Pops.blue, Modifier.weight(1f)) { showMultiplayer = true }
        }
        Spacer(Modifier.height(24.dp))
    }

    if (showNight) NightEntrySheet(onDismiss = { showNight = false },
        onStart = { showNight = false; onNight() }, onJoin = { showNight = false; onJoinNight() })
    if (showCustomize) CustomizeSheet(store = store, initial = store.quickPlay(),
        onDismiss = { showCustomize = false }, onStart = { ms, c -> showCustomize = false; playMix(ms, c) })
    if (showDailyArchive) DailyArchiveSheet(store = store,
        onDismiss = { showDailyArchive = false },
        onPlayDay = { day -> showDailyArchive = false; onPlayDaily(day) })
    if (showMultiplayer) MultiplayerSheet(store = store,
        onDismiss = { showMultiplayer = false },
        onPickBot = { id -> showMultiplayer = false; onVersus(id) },
        onQuickMatch = { showMultiplayer = false; onQuickMatch() })
}

@Composable
private fun HomeTile(icon: ImageVector, title: String, fill: Color, modifier: Modifier, onClick: () -> Unit) {
    ChunkyCard(fill = fill, onClick = onClick, modifier = modifier) {
        Column(Modifier.padding(14.dp).heightIn(min = 76.dp)) {
            Icon(icon, null, tint = onAccent(fill), modifier = Modifier.size(24.dp))
            Spacer(Modifier.height(6.dp))
            Text(title, fontWeight = FontWeight.Bold, fontSize = 16.sp, color = onAccent(fill))
        }
    }
}

/** Previous Tidbits — the Daily archive (R-DAILY-1). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DailyArchiveSheet(store: Store, onDismiss: () -> Unit, onPlayDay: (String) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Previous Tidbits", fontWeight = FontWeight.Black, fontSize = 22.sp)
            Text("Every day has its own set of 7 — the same for everyone. Catching up doesn't change your streak.",
                fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            recentDayKeys(30).forEach { day ->
                val score = store.dailyScore(day)
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(dayLabel(day), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    if (score != null) {
                        Text("Scored $score", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    } else {
                        TextButton(onClick = { onPlayDay(day) }) { Text("Play") }
                    }
                }
            }
        }
    }
}

private fun recentDayKeys(count: Int): List<String> {
    val c = java.util.Calendar.getInstance()
    return (0 until count).map {
        val k = "%04d-%02d-%02d".format(c.get(java.util.Calendar.YEAR), c.get(java.util.Calendar.MONTH) + 1, c.get(java.util.Calendar.DAY_OF_MONTH))
        c.add(java.util.Calendar.DAY_OF_MONTH, -1)
        k
    }
}

private fun dayLabel(day: String): String {
    if (day == dayKey()) return "Today"
    val f = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
    val d = runCatching { f.parse(day) }.getOrNull() ?: return day
    return java.text.SimpleDateFormat("EEE, MMM d", java.util.Locale.getDefault()).format(d)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NightEntrySheet(onDismiss: () -> Unit, onStart: () -> Unit, onJoin: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Trivia Night", fontWeight = FontWeight.Black, fontSize = 26.sp)
            Text("A night of mixed rounds — every kind of question. Host for the room, or join someone's code. Apple or Android, same code.",
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), fontSize = 14.sp)
            ChunkyCard(fill = Pops.coral, onClick = onStart, modifier = Modifier.fillMaxWidth()) { NightRow(Icons.Filled.PlayArrow, "Start a night", "Host for others, or play solo") }
            ChunkyCard(fill = Pops.teal, onClick = onJoin, modifier = Modifier.fillMaxWidth()) { NightRow(Icons.Filled.Tag, "Join a game", "Enter a host's 4-letter code") }
        }
    }
}

@Composable
private fun NightRow(icon: ImageVector, title: String, sub: String) {
    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp, color = Color.White)
            Text(sub, fontSize = 13.sp, color = Color.White.copy(alpha = 0.9f))
        }
        Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.White)
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun CustomizeSheet(store: Store, initial: Pair<Mode, Category>, onDismiss: () -> Unit, onStart: (List<Mode>, Category) -> Unit) {
    var modes by remember { mutableStateOf(
        if (initial.first == Mode.MIX) store.lastMixModes().toSet().ifEmpty { setOf(Mode.CLASSIC) }
        else setOf(initial.first)) }
    var cat by remember { mutableStateOf(initial.second) }
    var showAll by remember { mutableStateOf(!coreModes.toSet().containsAll(modes)) }
    var presets by remember { mutableStateOf(store.presets()) }
    var saving by remember { mutableStateOf(false) }
    val fade = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Customize a game", fontWeight = FontWeight.Black, fontSize = 22.sp)
            Text("Mode", fontWeight = FontWeight.Bold, fontSize = 13.sp, color = fade)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                (if (showAll) playableModes else coreModes).forEach { m ->
                    // Multi-select: tap toggles; the last selected can't be removed.
                    FilterChip(selected = m in modes, onClick = {
                        modes = if (m in modes) { if (modes.size > 1) modes - m else modes } else modes + m
                    }, label = { Text(m.title) })
                }
            }
            // Bare mode names ("Stake", "Which First?") don't explain themselves —
            // one mode shows its blurb; several explain the mix.
            Text(if (modes.size == 1) modes.first().let { "${it.title}: ${it.blurb}" }
                 else "Custom Mix: questions drawn from all ${modes.size} selected modes, shuffled together.",
                fontSize = 13.sp, color = fade)
            TextButton(onClick = { showAll = !showAll }, contentPadding = PaddingValues(0.dp)) {
                Text(if (showAll) "Show fewer modes" else "Show all modes", color = Pops.blue)
            }
            Text("Category", fontWeight = FontWeight.Bold, fontSize = 13.sp, color = fade)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Category.all.forEach { c -> FilterChip(selected = cat.id == c.id, onClick = { cat = c }, label = { Text(c.name) }) }
            }
            if (presets.isNotEmpty()) {
                Text("My presets", fontWeight = FontWeight.Bold, fontSize = 13.sp, color = fade)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    presets.forEach { p -> AssistChip(onClick = {
                    modes = if (p.mode == Mode.MIX) p.modes.toSet().ifEmpty { setOf(Mode.CLASSIC) } else setOf(p.mode)
                    if (!coreModes.toSet().containsAll(modes)) showAll = true
                    cat = p.category
                }, label = { Text(p.name) }) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(onClick = { saving = true }) { Text("Save preset") }
                Button(onClick = { onStart(playableModes.filter { it in modes }, cat) }, modifier = Modifier.weight(1f).height(50.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) {
                    Text(if (modes.size > 1) "Start the Mix (${modes.size})" else "Start", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                }
            }
        }
    }
    if (saving) {
        var name by remember { mutableStateOf(if (modes.size == 1) "${cat.name} ${modes.first().title}" else "${cat.name} Mix") }
        AlertDialog(onDismissRequest = { saving = false },
            title = { Text("Save this combination") },
            text = { OutlinedTextField(value = name, onValueChange = { name = it }, singleLine = true, label = { Text("Name") }) },
            confirmButton = {
                TextButton(onClick = {
                    if (name.isNotBlank()) {
                        val m = if (modes.size == 1) modes.first() else Mode.MIX
                        store.savePreset(GamePreset(name.trim(), m.name, listOf(cat.id),
                            modeIds = playableModes.filter { it in modes }.map { it.name }))
                        presets = store.presets()
                    }
                    saving = false
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { saving = false }) { Text("Cancel") } })
    }
}

/** The beat between rounds of a solo/pass Trivia Night — what's coming and how
 *  many questions, then an explicit start (owner: rounds must be FELT). */
@Composable
private fun RoundIntroScreen(game: GameState) {
    val kindName = game.currentRoundTitle ?: "Next Round"
    Column(Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Text("ROUND ${game.currentRoundNumber} OF ${game.roundCount}",
            fontSize = 13.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        Spacer(Modifier.height(10.dp))
        Text(kindName, fontSize = 30.sp, fontWeight = FontWeight.Black, textAlign = TextAlign.Center)
        Spacer(Modifier.height(6.dp))
        Text("${game.introRoundCount} questions", fontSize = 15.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        Spacer(Modifier.height(28.dp))
        Button(onClick = { game.startRound() }, modifier = Modifier.fillMaxWidth().height(52.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) {
            Text("Start Round ${game.currentRoundNumber}", fontWeight = FontWeight.Bold)
        }
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
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(p.name, fontWeight = FontWeight.Black, fontSize = 17.sp)
                    // The full lineup — owner: it must be OBVIOUS what the rounds
                    // are and how many questions each holds. Full names, no rails.
                    p.rounds.forEachIndexed { ri, r ->
                        Text("${ri + 1}.  ${Night.roundTitle[r.first] ?: r.first} · ${r.second} questions",
                            fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f))
                    }
                }
            }
        }
        Text("Category", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Category.all.forEach { c ->
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
private fun NightJoinScreen(initialCode: String, initialName: String, onFound: (String, String) -> Unit, onCancel: () -> Unit) {
    var code by remember { mutableStateOf(initialCode) }
    var name by remember { mutableStateOf(initialName) }
    var probing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Join a game", fontSize = 28.sp, fontWeight = FontWeight.Black)
        Text("Enter a host's code — a Tidbits Live event or a Trivia Night. Works from anywhere.",
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        OutlinedTextField(
            value = code, onValueChange = { code = it.uppercase().filter { c -> c.isLetterOrDigit() }.take(4); error = null },
            label = { Text("Room code") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
        )
        OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Your name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        error?.let { Text(it, color = Pops.coral, fontWeight = FontWeight.Bold) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(onClick = onCancel) { Text("Cancel") }
            Button(
                onClick = {
                    scope.launch {
                        probing = true; error = null
                        val exists = runCatching { FirebaseNet.probeLive(code) }.getOrDefault(false)
                        probing = false
                        if (exists) onFound(code, name) else error = "No game found for that code."
                    }
                },
                enabled = code.length == 4 && !probing, modifier = Modifier.weight(1f),
                colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White),
            ) { Text(if (probing) "Finding…" else "Join") }
        }
    }
}

// ---- Game ----

@Composable
private fun GameScreen(route: Route.Game, store: Store, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    val haptics = rememberGameHaptics(store)
    val game = remember { GameState(route.mode, route.category, store, route.custom, route.label, route.nightRounds, dailyDay = route.dailyDay, mixModes = route.mixModes) }
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
        GamePhase.ROUND_INTRO -> RoundIntroScreen(game)
        // The Daily is play-once (R-DAILY-1) — no replay of a locked set.
        GamePhase.FINISHED -> ResultsScreen(game,
            onPlayAgain = if (route.mode == Mode.DAILY || route.duelId != null) null else ({ scope.launch { game.restart() } }),
            onDone = onDone, duelId = route.duelId)
        else -> PlayingScreen(game)
    }
}

@Composable
internal fun PlayingScreen(game: GameState, match: VsMatch? = null, onlineRoster: Map<String, com.learningischange.tidbitstrivia.net.FirebaseNet.Player>? = null) {
    val q = game.current ?: return
    val live = game.phase == GamePhase.PLAYING && !game.awaitingReveal   // accepting input
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(game.progressLabel, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            LinearProgressIndicator(progress = { game.clockFraction.toFloat() }, modifier = Modifier.weight(1f),
                color = if (game.remaining <= 5) Pops.coral else Pops.blue)
            AssistChip(onClick = {}, label = { Text("${game.streak}") },
                leadingIcon = { Icon(Icons.Filled.LocalFireDepartment, null, modifier = Modifier.size(16.dp)) })
            AssistChip(onClick = {}, label = { Text("${game.score}") },
                leadingIcon = { Icon(Icons.Filled.Star, null, modifier = Modifier.size(16.dp)) })
        }
        if (match != null) VersusStrip(game, match)
        if (onlineRoster != null) OnlineStrip(game, onlineRoster)
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
            val uriHandler = LocalUriHandler.current
            ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(if (game.lastCorrect) Icons.Filled.Verified else Icons.Filled.Lightbulb, null,
                            tint = if (game.lastCorrect) accentText(Pops.mint) else accentText(Pops.coral),
                            modifier = Modifier.size(22.dp))
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
                    if (q.explanation.isNotEmpty()) Text(q.explanation, fontSize = 15.sp,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.9f))
                    if (game.mode == Mode.BAR_TRIVIA && game.nextRoundTitle != null)
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Filled.SportsScore, null, tint = accentText(Pops.coral), modifier = Modifier.size(18.dp))
                            Text("Round ${game.currentRoundNumber} complete · up next: ${game.nextRoundTitle}",
                                color = accentText(Pops.coral), fontWeight = FontWeight.Bold)
                        }
                    if (match != null) { Spacer(Modifier.height(2.dp)); }
                    // Parity with iOS/web: every reveal links back to its source article.
                    if (q.sourceUrl.isNotEmpty()) {
                        TextButton(onClick = { uriHandler.openUri(q.sourceUrl) }, contentPadding = PaddingValues(0.dp)) {
                            Icon(Icons.AutoMirrored.Filled.OpenInNew, null, modifier = Modifier.size(16.dp), tint = Pops.blue)
                            Spacer(Modifier.width(6.dp))
                            Text("Read ${q.sourceTitle} on Wikipedia", color = Pops.blue, fontSize = 13.sp)
                        }
                    }
                }
            }
            if (match != null) VersusRevealCard(match)
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
private fun ResultsScreen(game: GameState, onPlayAgain: (() -> Unit)?, onDone: () -> Unit, duelId: String? = null) {
    val context = LocalContext.current
    if (duelId != null) LaunchedEffect(duelId) { com.learningischange.tidbitstrivia.data.Duels.submit(duelId, game.score) }   // L5: submit my duel score
    val total = game.answered.size
    val acc = if (total == 0) 0 else game.correctCount * 100 / total
    val grid = game.answered.joinToString("") { if (it.chosen == null) "⚫️" else if (it.correct) "🟢" else "🔴" }
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
        // L2: the cross-context day streak made visible — encouragement, never punishing.
        val st = PlayerIdentity.profile?.streak
        if (st != null && st.current >= 1) {
            ChunkyCard(fill = Pops.coral.copy(alpha = 0.12f)) {
                Column(Modifier.padding(16.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("🔥 ${st.current}", fontWeight = FontWeight.Black, fontSize = 44.sp, color = Pops.coral)
                    Text(if (st.current > 1 && st.current == st.longest) "day streak · your best ever!" else "day streak", fontWeight = FontWeight.Bold)
                    if (st.freezes > 0) Text("🧊 ${st.freezes} freeze${if (st.freezes == 1) "" else "s"} banked — miss a day and this keeps your streak alive",
                        fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), textAlign = TextAlign.Center)
                }
            }
        }
        Button(onClick = {
            val filled = Math.round(acc * 7 / 100.0).toInt().coerceIn(0, 7)
            val meter = "▰".repeat(filled) + "▱".repeat(7 - filled)
            val dayStreak = PlayerIdentity.profile?.streak?.current ?: 0
            val streak = if (dayStreak >= 2) "\n🔥 $dayStreak-day streak" else if (game.maxStreak >= 3) "\n🔥 Best run ${game.maxStreak}" else ""
            val text = "🧠 Tidbits — ${game.mode.title}\n${game.score} pts · ${game.correctCount}/$total\n$meter $acc%\n$grid$streak\nPlay at https://tidbitstrivia.com"
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
        // L5 (charter): hard questions you nailed → invite the story + a conversation.
        val nailed = game.answered.filter { it.correct && it.q.difficulty >= 4 }
        if (nailed.isNotEmpty()) {
            Text("Tough ones you nailed", fontWeight = FontWeight.Bold, fontSize = 20.sp, modifier = Modifier.fillMaxWidth())
            nailed.forEach { a ->
                ChunkyCard(modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(14.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(a.q.prompt, fontWeight = FontWeight.Bold)
                        Text("You got it: ${a.q.answerText}", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                        TextButton(onClick = {
                            val text = "I knew \"${a.q.prompt}\" on Tidbits Trivia — it's ${a.q.answerText}. How did YOU know that? 🧠"
                            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }, "Share"))
                        }, contentPadding = PaddingValues(0.dp)) { Text("How did you know that? · Share", color = Pops.blue) }
                    }
                }
            }
        }
        if (onPlayAgain != null) Button(onClick = onPlayAgain, modifier = Modifier.fillMaxWidth()) { Text("Play Again") }
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
    var recap by remember { mutableStateOf<Store.Rec?>(null) }
    var drillDomain by remember { mutableStateOf<String?>(null) }
    var bestsMode by remember { mutableStateOf<Mode?>(null) }
    var showAllGames by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Records", fontSize = 30.sp, fontWeight = FontWeight.Black)
        if (records.isEmpty()) {
            ChunkyCard { Column(Modifier.padding(20.dp)) { Text("No games yet", fontWeight = FontWeight.Bold); Text("Play a round and your scores and streaks show up here.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)) } }
            return@Column
        }
        ChunkyCard(fill = Pops.yellow) {
            Row(Modifier.padding(18.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column { Text("DAY STREAK", color = Ink.copy(alpha = 0.7f), fontSize = 12.sp); Text("${PlayerIdentity.profile?.streak?.current ?: 0} days", fontWeight = FontWeight.Black, fontSize = 26.sp, color = Ink) }
                Text("best ${PlayerIdentity.profile?.streak?.longest ?: 0} 🔥", color = Ink, fontWeight = FontWeight.Bold)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatBox("${life.first}", "Games", Pops.grape); StatBox("${life.third}%", "Accuracy", Pops.blue); StatBox("${life.second}", "Correct", Pops.mint)
        }
        Text("Your games", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Text("Your latest rounds — tap one to see the questions.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        // ANDROID-DESIGN §5.3: a bounded preview (3 most recent) + a "See all"
        // drill-in, so Records stays a dashboard, not a 40-card ledger.
        records.take(3).forEach { rec -> GameHistoryRow(rec) { recap = rec } }
        if (records.size > 3) ChunkyCard(onClick = { showAllGames = true }, modifier = Modifier.fillMaxWidth()) {
            Row(Modifier.padding(14.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                Text("See all ${records.size} games", fontWeight = FontWeight.Bold)
                Icon(Icons.Filled.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
            }
        }
        val prog = remember { store.progress() }
        val explored = prog.count { it.total > 0 }
        val mastered = prog.count { it.hasWedge }
        Text("Your knowledge", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Text("Each domain levels up as you answer its questions correctly. You've explored $explored of 7 domains and mastered $mastered. A ✓ means mastered — 15+ right at 60%+ accuracy.",
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        prog.filter { it.total > 0 }.forEach { TopicRow(it) { drillDomain = it.id } }
        // L4: levelable badges — tiered milestones from BadgeMath (mirror of Core), hidden until one is earned.
        val totalQ = records.sumOf { it.total }
        val badges = BadgeMath.badges(
            games = records.size,
            longestStreak = PlayerIdentity.profile?.streak?.longest ?: 0,
            mastered = mastered,
            lifetimeAccuracy = if (totalQ > 0) records.sumOf { it.correct } * 100 / totalQ else 0,
            liveNights = PlayerIdentity.profile?.stats?.liveNights ?: 0)
        if (badges.any { it.tier > 0 }) {
            Text("Badges", fontWeight = FontWeight.Bold, fontSize = 20.sp)
            Text("Milestones that level up as you play — depth, consistency, and range.",
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            badges.forEach { b -> BadgeRow(b) }
        }
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
        Text("Tap a mode to scroll your previous attempts.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        Mode.entries.forEach { m ->
            val attempts = records.filter { it.mode == m.name }
            val b = attempts.maxOfOrNull { it.score } ?: 0
            if (b > 0) ChunkyCard(onClick = { bestsMode = m }) {
                Row(Modifier.padding(14.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Column { Text(m.title, fontWeight = FontWeight.Bold); Text("${attempts.size} played", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)) }
                    Row(verticalAlignment = Alignment.CenterVertically) { Text("$b", fontWeight = FontWeight.Black, fontSize = 20.sp); Icon(Icons.Filled.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)) }
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
    recap?.let { RecapDialog(it) { recap = null } }
    drillDomain?.let { DomainDrillDialog(it, records) { drillDomain = null } }
    bestsMode?.let { m -> BestAttemptsDialog(m, records.filter { it.mode == m.name }, onOpen = { recap = it; bestsMode = null }) { bestsMode = null } }
    if (showAllGames) AllGamesDialog(records, onOpen = { recap = it; showAllGames = false }) { showAllGames = false }
}

// One past game as a card: mode, category, score, colored answer dots, when.
@Composable
private fun GameHistoryRow(rec: Store.Rec, onClick: () -> Unit) {
    val mode = runCatching { Mode.valueOf(rec.mode) }.getOrDefault(Mode.CLASSIC)
    ChunkyCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(mode.title, fontWeight = FontWeight.Bold)
                    Text(" · ${Category.byId(rec.categoryId).name}", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                }
                Spacer(Modifier.height(4.dp)); AnswerDots(rec)
                Text("${rec.correct}/${rec.total} correct${if (rec.at > 0) " · " + relativeTime(rec.at) else ""}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
            Text("${rec.score}", fontWeight = FontWeight.Black, fontSize = 20.sp)
        }
    }
}

// The run's shape: a pip per question in the domain's color when correct, hollow
// when missed (owner: more compelling than red/green squares). Falls back to a
// correct/total bar for old records with no per-question detail.
@Composable
private fun AnswerDots(rec: Store.Rec) {
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        if (rec.answers.isEmpty()) {
            repeat(maxOf(rec.total, 1)) { i ->
                Box(Modifier.size(10.dp).background(if (i < rec.correct) Pops.mint else MaterialTheme.colorScheme.surface, CircleShape).border(1.5.dp, Ink, CircleShape))
            }
        } else {
            rec.answers.take(24).forEach { a ->
                val c = Pops.at(Category.byId(a.categoryId).colorIndex)
                Box(Modifier.size(10.dp).background(if (a.correct) c else MaterialTheme.colorScheme.surface, CircleShape).border(1.5.dp, Ink, CircleShape))
            }
        }
    }
}

private fun relativeTime(at: Long): String {
    val d = System.currentTimeMillis() - at
    return when {
        d < 60_000 -> "just now"
        d < 3_600_000 -> "${d / 60_000}m ago"
        d < 86_400_000 -> "${d / 3_600_000}h ago"
        else -> "${d / 86_400_000}d ago"
    }
}

@Composable
private fun AnswerLine(a: Store.AnswerDetail) {
    ChunkyCard(fill = MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(if (a.correct) Icons.Filled.CheckCircle else Icons.Filled.Cancel, null,
                tint = if (a.correct) accentText(Pops.mint) else accentText(Pops.coral), modifier = Modifier.size(20.dp))
            Column(Modifier.weight(1f)) {
                Text(a.prompt, fontWeight = FontWeight.Bold)
                Text("Answer: ${a.answer}", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecapDialog(rec: Store.Rec, onDismiss: () -> Unit) {
    val mode = runCatching { Mode.valueOf(rec.mode) }.getOrDefault(Mode.CLASSIC)
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("${mode.title} · ${rec.score}", fontWeight = FontWeight.Black, fontSize = 22.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatBox("${rec.correct}/${rec.total}", "Correct", Pops.mint)
                StatBox("${if (rec.total > 0) rec.correct * 100 / rec.total else 0}%", "Accuracy", Pops.blue)
            }
            if (rec.answers.isEmpty()) Text("This game was played before per-question history was added, so only the totals are here.", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            rec.answers.forEach { AnswerLine(it) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DomainDrillDialog(categoryId: String, records: List<Store.Rec>, onDismiss: () -> Unit) {
    val seen = HashSet<String>(); val answers = mutableListOf<Store.AnswerDetail>()
    records.forEach { r -> r.answers.forEach { a -> if (a.categoryId == categoryId && seen.add(a.qid)) answers.add(a) } }
    val wrong = answers.filter { !it.correct }; val right = answers.filter { it.correct }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(Category.byId(categoryId).name, fontWeight = FontWeight.Black, fontSize = 22.sp)
            if (answers.isEmpty()) Text("No per-question history yet for this domain. Play a game here and it'll show up.", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            if (wrong.isNotEmpty()) { Text("Missed (${wrong.size})", fontWeight = FontWeight.Bold, fontSize = 18.sp); wrong.forEach { AnswerLine(it) } }
            if (right.isNotEmpty()) { Text("Got right (${right.size})", fontWeight = FontWeight.Bold, fontSize = 18.sp); right.forEach { AnswerLine(it) } }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BestAttemptsDialog(mode: Mode, attempts: List<Store.Rec>, onOpen: (Store.Rec) -> Unit, onDismiss: () -> Unit) {
    val best = attempts.maxOfOrNull { it.score } ?: 0
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("${mode.title} attempts", fontWeight = FontWeight.Black, fontSize = 22.sp)
            Text("Newest first. Your best is $best.", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            attempts.forEach { rec ->
                ChunkyCard(onClick = { onOpen(rec) }, modifier = Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(14.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (rec.score == best) Icon(Icons.Filled.EmojiEvents, null, tint = Pops.yellow, modifier = Modifier.size(18.dp))
                        Column(Modifier.weight(1f)) {
                            Text(if (rec.at > 0) relativeTime(rec.at) else rec.day, fontWeight = FontWeight.Bold)
                            Spacer(Modifier.height(4.dp)); AnswerDots(rec)
                        }
                        Text("${rec.score}", fontWeight = FontWeight.Black, fontSize = 20.sp)
                        Icon(Icons.Filled.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
                    }
                }
            }
        }
    }
}

// Full game history (the "See all" drill-in, ANDROID-DESIGN §5.3): the long
// tail lives here, behind the 3-game preview on Records.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AllGamesDialog(records: List<Store.Rec>, onOpen: (Store.Rec) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("All games", fontWeight = FontWeight.Black, fontSize = 22.sp)
            Text("Newest first — tap one to see the questions.", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            records.forEach { rec -> GameHistoryRow(rec) { onOpen(rec) } }
        }
    }
}

// L4: one levelable badge — tier number, name, tier chip, progress bar, plain-language detail.
@Composable
private fun BadgeRow(b: LevelableBadge) {
    ChunkyCard(modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(36.dp).background(if (b.tier > 0) Pops.coral else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f), CircleShape).border(2.dp, Ink, CircleShape), contentAlignment = Alignment.Center) {
                Text(if (b.tier > 0) "${b.tier}" else "·", fontWeight = FontWeight.Black, color = Color.White)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(b.name, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    Text("Tier ${b.tier}/${b.maxTier}", fontWeight = FontWeight.Black, fontSize = 12.sp, color = accentText(Pops.blue),
                        modifier = Modifier.background(Pops.blue, RoundedCornerShape(999.dp)).border(2.dp, Ink, RoundedCornerShape(999.dp)).padding(horizontal = 9.dp, vertical = 3.dp))
                }
                Box(Modifier.fillMaxWidth().height(12.dp).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(999.dp)).border(2.dp, Ink, RoundedCornerShape(999.dp))) {
                    Box(Modifier.fillMaxWidth(b.progress).fillMaxHeight().background(Pops.coral, RoundedCornerShape(999.dp)))
                }
                Text(b.detail, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
    }
}

// One domain's depth: icon, name, mastered check, level badge, XP bar, and a
// plain-language "N more to Level X" so the number means something.
@Composable
private fun TopicRow(d: DomainProgress, onClick: () -> Unit = {}) {
    val c = Category.byId(d.id); val col = Pops.at(c.colorIndex)
    val remaining = (5 * (d.level + 1) * (d.level + 2) / 2 - d.correct).coerceAtLeast(0)
    ChunkyCard(onClick = onClick) {
        Row(Modifier.padding(12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(36.dp).background(col, CircleShape).border(2.5.dp, Ink, CircleShape), contentAlignment = Alignment.Center) {
                Icon(categoryIcon(c.id), null, tint = onAccent(col), modifier = Modifier.size(18.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(c.name, fontWeight = FontWeight.Bold)
                    if (d.hasWedge) Icon(Icons.Filled.Verified, "Mastered", tint = accentText(Pops.mint), modifier = Modifier.size(16.dp))
                    Spacer(Modifier.weight(1f))
                    Surface(color = col, shape = RoundedCornerShape(999.dp), border = BorderStroke(2.dp, Ink)) {
                        Text("Level ${d.level}", color = onAccent(col), fontWeight = FontWeight.Black, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 9.dp, vertical = 2.dp))
                    }
                }
                Box(Modifier.fillMaxWidth().height(12.dp).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(999.dp)).border(2.dp, Ink, RoundedCornerShape(999.dp))) {
                    Box(Modifier.fillMaxWidth(d.levelProgress.coerceIn(0.05f, 1f)).fillMaxHeight().background(col, RoundedCornerShape(999.dp)))
                }
                Text("${d.correct} correct · $remaining more to Level ${d.level + 1}",
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), fontSize = 13.sp)
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
            // Grounded + VARIED (owner): diversity-capped corpus MCQ plus a couple
            // of topic-matched OTHER shapes so the set mixes question types AND
            // categories. Live Wikipedia only when the corpus is thin.
            val topicT = t.trim()
            val shaped = mutableListOf<Question>()
            for (src in listOf(Pictures, ThisOrThat, ClosestCall)) shaped += src.searchMatch(topicT, 1)
            var mcq = Corpus.search(topicT, maxOf(4, 8 - shaped.size))
            if (mcq.size < 3) { val gen = Wikipedia.generate(topicT, "mixed", 8); if (gen.size >= 3) { mcq = gen; shaped.clear() } }
            val qs = (mcq + shaped).shuffled().take(8)
            working = false
            if (qs.size >= 3) onPlay(qs, topicT) else error = "Couldn't build a good quiz for “$topicT”. Try a broader subject."
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
internal fun ChunkyCard(modifier: Modifier = Modifier, fill: Color = MaterialTheme.colorScheme.surface, onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val base = modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)
    Surface(shape = RoundedCornerShape(18.dp), color = fill, border = BorderStroke(2.5.dp, Ink), modifier = base) { content() }
}

/** R-ICON-1: category glyphs come from Material Symbols, not the emoji field. */
internal fun categoryIcon(id: String): ImageVector = when (id) {
    "history" -> Icons.Filled.HistoryEdu
    "science" -> Icons.Filled.Science
    "geography" -> Icons.Filled.Public
    "arts" -> Icons.Filled.TheaterComedy
    "film" -> Icons.Filled.Movie
    "music" -> Icons.Filled.MusicNote
    "sports" -> Icons.Filled.EmojiEvents
    else -> Icons.Filled.Shuffle
}

// L5 async friend duels ------------------------------------------------------

internal suspend fun buildDuelSet(): List<com.learningischange.tidbitstrivia.data.DuelQ> {
    val topics = listOf("history", "science", "movies", "music", "sports", "geography", "art", "nature")
    return Corpus.search(topics.random(), 6).filter { it.options.size >= 2 }.take(6)
        .map { com.learningischange.tidbitstrivia.data.DuelQ(it.prompt, it.options, it.correctIndex, it.explanation) }
}

@Composable
private fun DuelsScreen(onBack: () -> Unit, onPlay: (String, List<Question>) -> Unit) {
    var inbox by remember { mutableStateOf<List<com.learningischange.tidbitstrivia.data.DuelInvite>>(emptyList()) }
    var mine by remember { mutableStateOf<List<com.learningischange.tidbitstrivia.data.DuelStanding>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    val scope = rememberCoroutineScope()
    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)
    LaunchedEffect(Unit) {
        inbox = com.learningischange.tidbitstrivia.data.Duels.inbox()
        mine = com.learningischange.tidbitstrivia.data.Duels.mine()
        loading = false
    }
    fun play(id: String) = scope.launch {
        com.learningischange.tidbitstrivia.data.Duels.accept(id)
        val snap = com.learningischange.tidbitstrivia.data.Duels.load(id) ?: return@launch
        val qs = com.learningischange.tidbitstrivia.data.Duels.questionsOf(snap).mapIndexed { i, q ->
            Question(id = "duel-$i", prompt = q.p, options = q.o, correctIndex = q.c, categoryId = "mixed",
                difficulty = 3, explanation = q.e, sourceTitle = "", sourceUrl = "")
        }
        onPlay(id, qs)
    }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Back") }
            Text("Duels", fontSize = 28.sp, fontWeight = FontWeight.Black, color = ink)
        }
        Text("Challenge a friend to the same questions — higher score wins. Answer on your own time.",
            color = soft, modifier = Modifier.padding(bottom = 12.dp))
        when {
            loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            else -> {
                val mineIds = mine.map { it.id }.toSet()
                val pending = inbox.filter { it.id !in mineIds }
                LazyColumn(Modifier.fillMaxSize()) {
                    if (pending.isEmpty() && mine.isEmpty()) item {
                        Text("No duels yet. Add friends from a live night, then tap Duel on the Leaderboard.", color = soft)
                    }
                    if (pending.isNotEmpty()) {
                        item { Text("Challenges for you", fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(vertical = 6.dp)) }
                        items(pending, key = { it.id }) { inv ->
                            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text("${inv.fromName} challenged you", fontWeight = FontWeight.SemiBold, color = ink, modifier = Modifier.weight(1f))
                                TextButton(onClick = { play(inv.id) }) { Text("Play", color = Pops.blue) }
                            }
                        }
                    }
                    if (mine.isNotEmpty()) {
                        item { Text("Your duels", fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(vertical = 6.dp)) }
                        items(mine, key = { it.id }) { d ->
                            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text("vs ${d.oppName}", fontWeight = FontWeight.SemiBold, color = ink, modifier = Modifier.weight(1f))
                                when {
                                    d.myDone && d.oppDone -> Text(
                                        if (d.myScore > d.oppScore) "Won ${d.myScore}-${d.oppScore}"
                                        else if (d.myScore < d.oppScore) "Lost ${d.myScore}-${d.oppScore}"
                                        else "Tied ${d.myScore}-${d.oppScore}",
                                        fontWeight = FontWeight.Bold, color = if (d.myScore > d.oppScore) Pops.coral else soft)
                                    d.myDone -> Text("Waiting on ${d.oppName}", fontSize = 13.sp, color = soft)
                                    else -> TextButton(onClick = { play(d.id) }) { Text("Your turn", color = Pops.blue) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
