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
import androidx.compose.foundation.focusGroup
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
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
import com.learningischange.tidbitstrivia.BuildConfig
import com.learningischange.tidbitstrivia.data.PlayerIdentity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.*
import com.learningischange.tidbitstrivia.net.FirebaseNet
import com.learningischange.tidbitstrivia.ui.theme.Ink
import com.learningischange.tidbitstrivia.ui.theme.Pops
import com.learningischange.tidbitstrivia.ui.theme.accentText
import com.learningischange.tidbitstrivia.ui.theme.onAccent
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt
import com.learningischange.tidbitstrivia.data.Coverage

sealed interface Route {
    data object Home : Route
    data object Records : Route
    data object Create : Route
    data class Game(val mode: Mode, val category: Category, val custom: List<Question>? = null, val label: String? = null, val nightRounds: List<Pair<String, Int>>? = null, val dailyDay: String? = null, val mixModes: List<Mode>? = null, val duelId: String? = null, val weakSpotReasons: Map<String, String> = emptyMap(), val expeditionId: String? = null, val expeditionStageIndex: Int? = null) : Route
    data class Versus(val botId: String) : Route
    object OnlineMatch : Route
    data object NightSetup : Route
    data object NightJoin : Route
    data object NightLive : Route
    data class LiveRoom(val code: String, val name: String) : Route
    data class LiveHost(val rounds: List<Pair<String, Int>>, val category: Category) : Route
    /** A shared single question: `tidbits://item/<id>` (DEEP_LINKS.md). */
    data class SharedItem(val id: String) : Route
    data object Settings : Route
    data object Profile : Route
    data object Leaderboard : Route   // Wave E: cross-venue / season standings
    data object Duels : Route          // L5: async friend duels
    data object Party : Route
    data object ClubPaywall : Route    // Tidbits Club join surface (CLUB-MARKETING.md)
    data object ClubHub : Route        // R-CLUB-1: the member view of the ONE Club door
    data object StoryArchive : Route   // Tidbits Club EXCLUSIVE — Story Archive (Feature 2)
    data object MarathonHistory : Route // Tidbits Club EXCLUSIVE — Marathon History (Feature 3)
    data object KnowledgeAtlas : Route // Tidbits Club EXCLUSIVE — Knowledge Atlas (Feature 4)
    data object ExpeditionHub : Route  // Tidbits Club EXCLUSIVE — Expeditions hub (Feature 5); reachable by everyone (real preview)
    data class ExpeditionMap(val expeditionId: String) : Route // an expedition's stage path; also a real preview for non-members
    data object LinkWall : Route       // Tidbits Club EXCLUSIVE — Link Wall (Feature 6): a second daily
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
    // Club status (Entitlement.refresh) rides the same effect — mirror of js/app.js's
    // `Identity.bootstrap().then(refresh)` + `Identity.onChange(refresh)`: this key flips
    // once bootstrap() resolves a signed-in identity, and again on sign-in/sign-out.
    LaunchedEffect(com.learningischange.tidbitstrivia.data.PlayerIdentity.signedIn) {
        Entitlement.refresh()
        if (com.learningischange.tidbitstrivia.data.PlayerIdentity.signedIn)
            com.learningischange.tidbitstrivia.data.PlayerIdentity.syncDailyLog(store, pushLocal = true)
    }
    LaunchedEffect(Unit) {
        com.learningischange.tidbitstrivia.data.PlayerIdentity.bootstrap()   // stable uid → portable profile
        // bootstrap() replaces `profile` wholesale, so the MainActivity seed gets clobbered —
        // re-apply it here or the Records store shot reads "0 days" beside 24 games.
        com.learningischange.tidbitstrivia.data.ScreenshotHooks.seedRecords?.let {
            com.learningischange.tidbitstrivia.data.PlayerIdentity.seedForScreenshots(streak = 12, longest = 27, games = it)
        }
        if (!Corpus.loaded) runCatching { Corpus.load(context) }
        // The shape sets are NOT loaded here any more — GameState.filled() loads each one
        // when its mode is played (JsonQuestionSet.ensure). Loading all eight at boot put
        // 17.5MB of JSON through a full-DOM parse on the launch path and is what Play
        // rejected version code 85 for. Corpus stays: it is sqlite-backed, keeps only ids,
        // and Daily/Ladder/Classic need it on the first screen.
        if (!Difficulty.loaded) runCatching { Difficulty.load(context) }
        corpusReady = true
    }

    // Deep-link inbox (parity with iOS .onOpenURL): MainActivity hands the
    // parsed host here; we route then mark consumed. Unknown links open Home.
    // Store-screenshot hooks (docs/STORE-SCREENSHOTS.md §2) — drive Android to a known
    // screen without a tap, exactly as the Apple capture run does.
    LaunchedEffect(corpusReady) {
        if (!corpusReady) return@LaunchedEffect
        val h = com.learningischange.tidbitstrivia.data.ScreenshotHooks
        h.initialTab?.let { tab ->
            backStack.clear()
            backStack.add(when (tab) { "records" -> Route.Records; "create" -> Route.Create; else -> Route.Home })
        }
        h.autoplay?.let { (mode, cat) ->
            val m = runCatching { Mode.valueOf(mode.uppercase()) }.getOrNull()
                ?: Mode.entries.firstOrNull { it.name.replace("_", "").equals(mode, ignoreCase = true) }
                ?: Mode.CLASSIC
            backStack.add(Route.Game(m, Category.byId(cat)))
        }
        if (h.openParty) backStack.add(Route.Party)
        if (h.openNightSetup) backStack.add(Route.NightSetup)
        h.liveJoin?.let { (code, name) -> backStack.add(Route.LiveRoom(code, name)) }
        // Same quick plan Apple's TIDBITS_NIGHT_HOST uses: two short rounds of
        // mixed questions, enough to publish and be joined.
        if (h.nightHost) {
            backStack.add(Route.LiveHost(listOf("classic" to 5, "oddoneout" to 5),
                                         Category.byId("mixed")))
        }
        // Map the generic screenshot/QA destination hook onto a route. Named
        // surfaces only — an unknown value is ignored rather than crashing a
        // capture run mid-sweep.
        when (h.openRoute) {
            "clubHub" -> backStack.add(Route.ClubHub)
            "paywall" -> backStack.add(Route.ClubPaywall)
            "atlas" -> backStack.add(Route.KnowledgeAtlas)
            "linkWall" -> backStack.add(Route.LinkWall)
            "expeditions" -> backStack.add(Route.ExpeditionHub)
            "storyArchive" -> backStack.add(Route.StoryArchive)
            "marathonHistory" -> backStack.add(Route.MarathonHistory)
            "settings" -> backStack.add(Route.Settings)
            "profile" -> backStack.add(Route.Profile)
            "leaderboard" -> backStack.add(Route.Leaderboard)
            "duels" -> backStack.add(Route.Duels)
            "online" -> backStack.add(Route.OnlineMatch)
            else -> Unit
        }
    }

    LaunchedEffect(deepLink) {
        when (deepLink) {
            null -> {}
            "daily" -> { backStack.clear(); backStack.add(Route.Home); backStack.add(Route.Game(Mode.DAILY, Category.byId("mixed"))) }
            "night" -> { backStack.clear(); backStack.add(Route.Home); backStack.add(Route.NightSetup) }
            "party" -> { backStack.clear(); backStack.add(Route.Home); backStack.add(Route.Party) }
            "create" -> { backStack.clear(); backStack.add(Route.Create) }
            "settings" -> { backStack.clear(); backStack.add(Route.Home); backStack.add(Route.Settings) }
            else -> {
                // A shared quiz: "quiz/<id>". Fetch it, KEEP it (a link a friend sent
                // shouldn't evaporate), and land on Create where the shelf lives.
                // A shared single question: "item/<id>". No fetch — it is a row this
                // build either ships or doesn't, and the screen says which.
                val itemId = deepLink.removePrefix("item/").takeIf { deepLink.startsWith("item/") && it.isNotBlank() }
                val id = deepLink.removePrefix("quiz/").takeIf { deepLink.startsWith("quiz/") && it.isNotBlank() }
                // The projector's QR: "live/<code>". Open the join screen with the code
                // already in the box — the player scanned, they don't type.
                val liveCode = deepLink.removePrefix("live/").takeIf { deepLink.startsWith("live/") && it.isNotBlank() }
                backStack.clear()
                backStack.add(Route.Home)
                if (itemId != null) backStack.add(Route.SharedItem(itemId))
                if (liveCode != null) { store.rememberNight(liveCode, store.lastNightName()); backStack.add(Route.NightJoin) }
                if (id != null) {
                    backStack.add(Route.Create)
                    runCatching {
                        com.learningischange.tidbitstrivia.net.FirebaseNet.loadQuizJson(id)
                    }.getOrNull()?.let { json ->
                        com.learningischange.tidbitstrivia.data.SavedQuiz.fromJson(json)?.let {
                            com.learningischange.tidbitstrivia.data.QuizStore.save(it)
                        }
                    }
                }
            }
        }
        if (deepLink != null) onDeepLinkConsumed()
    }

    BackHandler(enabled = backStack.size > 1) { backStack.removeAt(backStack.lastIndex) }

    val showBar = current is Route.Home || current is Route.Records || current is Route.Create
    // TV: claim focus for the screen we just navigated to. A focus audit of all
    // 26 surfaces found 20 of them opening with focusable content and ZERO
    // focused — reachable, but inert, because CENTER has nothing to act on.
    // Requesting focus on a focusGroup hands it to the group's first focusable
    // child, so this one place fixes every route instead of twenty screens.
    //
    // Route.Game is excluded on purpose: it claims focus per QUESTION (the first
    // answer option), and a route-level claim would fight it and land the player
    // on a header chip instead of an answer.
    val routeFocus = remember { FocusRequester() }
    val tvRoute = isTv()
    LaunchedEffect(current, tvRoute) {
        if (tvRoute && current !is Route.Game) {
            kotlinx.coroutines.delay(400)   // let the screen finish composing
            runCatching { routeFocus.requestFocus() }
        }
    }
    Box(Modifier.fillMaxSize()) {
        // QA bench banner (tidbits_qa_label) — DEBUG-only via ScreenshotHooks, so it is
        // absent from every release build. Drawn in the root Box as an overlay rather
        // than in the Scaffold, so it survives navigation and cannot shift the layout
        // under test.
        ScreenshotHooks.qaLabel?.let { qa ->
            androidx.compose.material3.Surface(
                color = androidx.compose.ui.graphics.Color(0xFFFF5C35),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(
                    bottomStart = 10.dp, bottomEnd = 10.dp),
                modifier = Modifier.align(androidx.compose.ui.Alignment.TopCenter).zIndex(10f),
            ) {
                androidx.compose.material3.Text(
                    qa,
                    color = androidx.compose.ui.graphics.Color.White,
                    style = androidx.compose.material3.MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 5.dp),
                )
            }
        }
        Scaffold(bottomBar = { if (showBar) BottomBar(current) { backStack.clear(); backStack.add(it) } }) { pad ->
            Box(Modifier.padding(pad).fillMaxSize().focusGroup().focusRequester(routeFocus)) {
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
                        onClub = { backStack.add(if (Entitlement.isClub) Route.ClubHub else Route.ClubPaywall) },
                    )
                    is Route.ClubHub -> ClubHubScreen(
                        store = store,
                        onBack = { backStack.removeLastOrNull() },
                        onPlayWeakSpot = { qs, reasons -> backStack.add(Route.Game(Mode.WEAK_SPOT, Category.byId("mixed"), qs, "Weak-Spot Arena", weakSpotReasons = reasons)) },
                        onPlayMarathon = { backStack.add(Route.Game(Mode.MARATHON, Category.byId("mixed"), label = "Marathon")) },
                        onExpeditions = { backStack.add(Route.ExpeditionHub) },
                        onLinkWall = { backStack.add(Route.LinkWall) },
                        onArchive = { backStack.add(Route.StoryArchive) },
                        onAtlas = { backStack.add(Route.KnowledgeAtlas) },
                        onMarathonHistory = { backStack.add(Route.MarathonHistory) },
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
                    is Route.Records -> RecordsScreen(store,
                        onOpenArchive = { backStack.add(Route.StoryArchive) },
                        onOpenMarathonHistory = { backStack.add(Route.MarathonHistory) },
                        onOpenAtlas = { backStack.add(Route.KnowledgeAtlas) },
                        onClub = { backStack.add(Route.ClubPaywall) })
                    is Route.Create -> CreateScreen { qs, label -> backStack.add(Route.Game(Mode.MIX, Category.byId("mixed"), qs, label)) }
                    is Route.Game -> GameScreen(r, store) { backStack.removeAt(backStack.lastIndex) }
                    is Route.Versus -> VersusScreen(r.botId, store) { backStack.removeAt(backStack.lastIndex) }
                    is Route.OnlineMatch -> OnlineMatchScreen(store) { backStack.removeAt(backStack.lastIndex) }
                    is Route.SharedItem -> SharedItemScreen(r.id,
                        onBack = { backStack.removeLastOrNull() },
                        onPlay = { backStack.clear(); backStack.add(Route.Home) })
                    is Route.Settings -> SettingsScreen(store, dynamicColor, onDynamicColor, onProfile = { backStack.add(Route.Profile) })
                    is Route.Profile -> ProfileScreen(onBack = { backStack.removeLastOrNull() }, onLeaderboard = { backStack.add(Route.Leaderboard) }, onDuels = { backStack.add(Route.Duels) }, onClub = { backStack.add(Route.ClubPaywall) })
                    is Route.Leaderboard -> LeaderboardScreen(onBack = { backStack.removeLastOrNull() })
                    is Route.Duels -> DuelsScreen(onBack = { backStack.removeLastOrNull() }, onPlay = { id, qs -> backStack.add(Route.Game(Mode.MIX, Category.byId("mixed"), qs, "Duel", duelId = id)) })
                    is Route.Party -> PartyContainer(store) { backStack.removeAt(backStack.lastIndex) }
                    is Route.ClubPaywall -> ClubPaywallScreen(onBack = { backStack.removeLastOrNull() })
                    is Route.StoryArchive -> StoryArchiveScreen(store,
                        onBack = { backStack.removeLastOrNull() },
                        onClub = { backStack.add(Route.ClubPaywall) },
                        onReask = { q -> backStack.add(Route.Game(Mode.CLASSIC, Category.byId(q.categoryId), listOf(q), "Re-ask")) })
                    is Route.MarathonHistory -> MarathonHistoryScreen(store,
                        onBack = { backStack.removeLastOrNull() },
                        onClub = { backStack.add(Route.ClubPaywall) })
                    is Route.KnowledgeAtlas -> KnowledgeAtlasScreen(store,
                        onBack = { backStack.removeLastOrNull() },
                        onClub = { backStack.add(Route.ClubPaywall) },
                        onPlay = { catId, label -> backStack.add(Route.Game(Mode.CLASSIC, Category.byId(catId), label = label)) })
                    is Route.ExpeditionHub -> ExpeditionsHubScreen(store,
                        onBack = { backStack.removeLastOrNull() },
                        onOpenMap = { id -> backStack.add(Route.ExpeditionMap(id)) })
                    is Route.ExpeditionMap -> ExpeditionMapScreen(store, r.expeditionId,
                        onBack = { backStack.removeLastOrNull() },
                        onClub = { backStack.add(Route.ClubPaywall) },
                        onPlayStage = { expedition, stageIndex ->
                            val stage = expedition.stages.firstOrNull { it.index == stageIndex } ?: return@ExpeditionMapScreen
                            val qs = Expeditions.startStage(expedition, stageIndex)
                            backStack.add(Route.Game(Mode.CLASSIC, Category.byId(stage.categoryId), qs, stage.title,
                                expeditionId = expedition.id, expeditionStageIndex = stageIndex))
                        })
                    is Route.LinkWall -> LinkWallScreen(store,
                        onBack = { backStack.removeLastOrNull() },
                        onClub = { backStack.add(Route.ClubPaywall) })
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
        NavigationBarItem(current is Route.Home, { onSelect(Route.Home) }, { Icon(Icons.Filled.PlayArrow, null) },
            label = { Text("Play") }, modifier = Modifier.tvFocus(RoundedCornerShape(24.dp), shadow = false))
        NavigationBarItem(current is Route.Records, { onSelect(Route.Records) }, { Icon(Icons.Filled.Star, null) },
            label = { Text("Records") }, modifier = Modifier.tvFocus(RoundedCornerShape(24.dp), shadow = false))
        NavigationBarItem(current is Route.Create, { onSelect(Route.Create) }, { Icon(Icons.Filled.Add, null) },
            label = { Text("Create") }, modifier = Modifier.tvFocus(RoundedCornerShape(24.dp), shadow = false))
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
    onClub: () -> Unit,
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

    // .then(tvOverscan()) — TVs crop the outer ~5%; see TvFocus.kt. No-op off TV.
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).then(tvOverscan()),
           verticalArrangement = Arrangement.spacedBy(16.dp)) {
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
                Text(if (firstRun) "${tapVerb()} to play — customize anytime" else "Jump straight into a round",
                    color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp)
            }
        }

        // Surprise + Customize — the quiet secondary pair under the hero (R-HOME-1a).
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = { val (m, c) = store.surprise(); play(m, c) },
                modifier = Modifier.weight(1f).tvFocus(RoundedCornerShape(20.dp), shadow = false)) {
                Icon(Icons.Filled.Casino, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Surprise me", fontWeight = FontWeight.Bold)
            }
            OutlinedButton(onClick = { showCustomize = true },
                modifier = Modifier.weight(1f).tvFocus(RoundedCornerShape(20.dp), shadow = false)) {
                Icon(Icons.Filled.Tune, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Customize", fontWeight = FontWeight.Bold)
            }
        }

        // JOIN A GAME — the second thing on Home (R-JOIN-1, ANDROID-DESIGN §3.1). It was a
        // row inside the Trivia Night sheet: one tap away and behind a word that does
        // not say "join". A player with a code on the wall finds this at a glance.
        ChunkyCard(fill = Pops.teal, onClick = onJoinNight) {
            Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Tag, null, tint = Color.White, modifier = Modifier.size(28.dp))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("JOIN A GAME", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Color.White)
                    Text("Enter the host's 4-letter code, or scan the QR on the big screen.", color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp)
                }
                Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.White)
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
                    val dayStreak = PlayerIdentity.displayStreak.current
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

        // R-CLUB-1 (docs/iOS-DESIGN.md §5.2a — the rule is cross-platform): the app's ONE
        // Club entry point, quiet and BELOW the free surfaces. Club used to surface as four
        // cards here plus three in Records; the count of visible locks, not the real
        // free/paid ratio, is what reads as the size of the paywall.
        ClubDoorCard(isClub = Entitlement.isClub, onClick = onClub)
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

// R-CLUB-1 (docs/iOS-DESIGN.md §5.2a — the rule is cross-platform): the app's ONE Club
// entry point on Home. Deliberately quiet — a single row below the free surfaces, not four
// locked cards. Members see a member line instead of a price, so the door stops selling
// once they're in.
@Composable
private fun ClubDoorCard(isClub: Boolean, onClick: () -> Unit) {
    ChunkyCard(fill = MaterialTheme.colorScheme.surface, onClick = onClick) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Star, null, tint = Pops.blue, modifier = Modifier.size(26.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text("Tidbits Club", fontWeight = FontWeight.Bold, fontSize = 18.sp)
                Text(
                    if (isClub) "Your six Club features, all in one place."
                    else "Six optional extras for getting better. Everything else in Tidbits is free.",
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                )
            }
            Icon(Icons.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
    }
}

// The member view of the Club door: every Club feature in one place, with its live state.
// Non-members never reach here (Home routes them to ClubPaywallScreen), so nothing carries
// a lock, a CLUB chip, or a price.
@Composable
private fun ClubHubScreen(
    store: Store,
    onBack: () -> Unit,
    onPlayWeakSpot: (List<Question>, Map<String, String>) -> Unit,
    onPlayMarathon: () -> Unit,
    onExpeditions: () -> Unit,
    onLinkWall: () -> Unit,
    onArchive: () -> Unit,
    onAtlas: () -> Unit,
    onMarathonHistory: () -> Unit,
) {
    var showWeakSpotEmpty by remember { mutableStateOf(false) }
    var showMarathonChoice by remember { mutableStateOf(false) }
    val run = remember { Marathon.inProgress(store) }
    val history = remember { Marathon.history(store) }
    val fade = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Back") }
            Text("Tidbits Club", fontWeight = FontWeight.Black, fontSize = 26.sp)
        }
        ChunkyCard(fill = MaterialTheme.colorScheme.surface) {
            Column(Modifier.padding(18.dp)) {
                Text("You're a member", fontWeight = FontWeight.Bold, fontSize = 18.sp)
                Text("Everything below is yours. The rest of Tidbits stays free for everyone.", fontSize = 13.sp, color = fade)
            }
        }

        Text("PLAY", fontWeight = FontWeight.Bold, fontSize = 12.sp, color = fade)
        ClubHubRow(Icons.Filled.GridView, "Link Wall", "Today's board — 16 facts, 4 hidden groups.", Pops.mint, onLinkWall)
        // Member copy, NOT previewLine() — those lines are written to SELL.
        ClubHubRow(Icons.Filled.TrackChanges, "Weak-Spot Arena",
            "A round built entirely from the questions you've missed.", Pops.coral) {
            val round = WeakSpotArena.build(store)
            if (round.questions.size >= WeakSpotArena.PLAYABLE_FLOOR) onPlayWeakSpot(round.questions, round.reasons)
            else showWeakSpotEmpty = true
        }
        ClubHubRow(Icons.Filled.DirectionsRun, "Marathon", marathonHubSubtitle(run, history), Pops.blue) {
            if (run != null) showMarathonChoice = true else onPlayMarathon()
        }
        ClubHubRow(Icons.Filled.Map, "Expeditions", "Multi-week campaigns through one domain.", Pops.grape, onExpeditions)

        Text("YOUR RECORD", fontWeight = FontWeight.Bold, fontSize = 12.sp, color = fade)
        val stories = StoryArchive.count(store)
        ClubHubRow(Icons.Filled.Book, "Story Archive",
            if (stories == 0) "Every story you unlock, kept here forever."
            else "$stories stor${if (stories == 1) "y" else "ies"} collected — searchable, forever.", Pops.blue, onArchive)
        ClubHubRow(Icons.Filled.ShowChart, "Knowledge Atlas", "What you actually know, by domain, over time.", Pops.mint, onAtlas)
        ClubHubRow(Icons.Filled.EmojiEvents, "Marathon History",
            if (history.isEmpty()) "Your finished runs, kept forever."
            else "${history.size} run${if (history.size == 1) "" else "s"} on record.", Pops.yellow, onMarathonHistory)
        Spacer(Modifier.height(24.dp))
    }

    if (showWeakSpotEmpty) AlertDialog(
        onDismissRequest = { showWeakSpotEmpty = false },
        title = { Text("Not enough misses yet") },
        text = { Text("Play a few rounds first — your misses become your arena.") },
        confirmButton = { TextButton(onClick = { showWeakSpotEmpty = false }) { Text("OK") } },
    )
    if (showMarathonChoice) AlertDialog(
        onDismissRequest = { showMarathonChoice = false },
        title = { Text("Marathon in progress") },
        text = { Text(run?.let { "Question ${it.currentIndex + 1} of ${it.total} — resume where you left off, or start a fresh run." } ?: "") },
        confirmButton = { TextButton(onClick = { showMarathonChoice = false; onPlayMarathon() }) { Text("Resume") } },
        dismissButton = {
            Row {
                TextButton(onClick = { showMarathonChoice = false; Marathon.startNew(store); onPlayMarathon() }) { Text("Start Over") }
                TextButton(onClick = { showMarathonChoice = false }) { Text("Cancel") }
            }
        },
    )
}

@Composable
private fun ClubHubRow(icon: ImageVector, title: String, subtitle: String, tint: Color, onClick: () -> Unit) {
    ChunkyCard(fill = MaterialTheme.colorScheme.surface, onClick = onClick) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = tint, modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(title, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                Text(subtitle, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
            Icon(Icons.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
    }
}

/// A member's real state — never a pitch (the hub is behind the paywall already).
private fun marathonHubSubtitle(run: MarathonRun?, history: List<MarathonScore>): String {
    if (run != null) return "Question ${run.currentIndex + 1} of ${run.total} — resume where you left off."
    val last = history.firstOrNull()
    if (last != null) return "${(last.accuracy * 100).roundToInt()}% on your last run. Start another."
    return "200 questions, graded by domain. Stop and resume anytime."
}


private fun marathonSubtitle(isClub: Boolean, run: MarathonRun?, history: List<MarathonScore>): String {
    if (!isClub) return Marathon.previewLine()
    if (run != null) return "Question ${run.currentIndex + 1} of ${run.total} — tap to resume"
    val last = history.firstOrNull()
    if (last != null) return "${(last.accuracy * 100).roundToInt()}% on your last run — tap to start a new one"
    return "200 questions. Play it across as many sittings as you like — we'll keep your place."
}

@Composable
private fun WeakSpotCard(isClub: Boolean, previewLine: String?, onClick: () -> Unit) {
    val subtitle = if (isClub) "Turn your misses into a round."
        else (previewLine ?: "Your misses, turned into a round you can actually close.")
    ChunkyCard(fill = Pops.grape, onClick = onClick) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.TrackChanges, null, tint = Color.White, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("WEAK-SPOT ARENA", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Color.White)
                    if (!isClub) {
                        Spacer(Modifier.width(6.dp))
                        Surface(shape = RoundedCornerShape(999.dp), color = Color.White) {
                            Text("CLUB", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Pops.grape,
                                modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp))
                        }
                    }
                }
                Text(subtitle, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, maxLines = 2)
            }
            Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.White)
        }
    }
}

@Composable
private fun MarathonCard(isClub: Boolean, run: MarathonRun?, subtitle: String, onClick: () -> Unit) {
    ChunkyCard(fill = Pops.teal, onClick = onClick) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Flag, null, tint = Color.White, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("MARATHON", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Color.White)
                    if (!isClub) {
                        Spacer(Modifier.width(6.dp))
                        Surface(shape = RoundedCornerShape(999.dp), color = Color.White) {
                            Text("CLUB", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Pops.teal,
                                modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp))
                        }
                    }
                    if (run != null) {
                        Spacer(Modifier.width(6.dp))
                        Surface(shape = RoundedCornerShape(999.dp), color = Pops.coral) {
                            Text("RESUME", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Color.White,
                                modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp))
                        }
                    }
                }
                Text(subtitle, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, maxLines = 2)
            }
            Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.White)
        }
    }
}

// Link Wall — Tidbits Club EXCLUSIVE (docs/CLUB-FEATURES-BUILD.md "Feature 6"). Its
// OWN Home entry point right beside the free Daily card (a second daily, not a
// variant of the first). Content-clean-generated, not player data, so — like
// Marathon — the non-member pitch is the real, concrete previewLine() copy.
@Composable
private fun LinkWallCard(isClub: Boolean, onClick: () -> Unit) {
    val subtitle = if (isClub) "16 tiles, 4 groups — a brand-new wall today." else LinkWall.previewLine()
    ChunkyCard(fill = Pops.grape, onClick = onClick) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.GridView, null, tint = Color.White, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("LINK WALL", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Color.White)
                    if (!isClub) {
                        Spacer(Modifier.width(6.dp))
                        Surface(shape = RoundedCornerShape(999.dp), color = Color.White) {
                            Text("CLUB", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Pops.grape,
                                modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp))
                        }
                    }
                }
                Text(subtitle, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, maxLines = 2)
            }
            Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.White)
        }
    }
}

// Expeditions — Tidbits Club EXCLUSIVE (docs/CLUB-FEATURES-BUILD.md "Feature 5"). The
// Home card (mirrors MarathonCard/StoryArchiveCard); the hub/map/result screens live
// near ExpeditionsHubScreen below.
@Composable
private fun ExpeditionsCard(store: Store, isClub: Boolean, onClick: () -> Unit) {
    val progressCount = remember(isClub) { Expeditions.available(store).count { it.second != null } }
    val certCount = remember(isClub) { Expeditions.certificates(store).size }
    val subtitle = when {
        progressCount > 0 -> "$progressCount expedition${if (progressCount == 1) "" else "s"} in progress — tap to continue"
        certCount > 0 -> "$certCount completed — pick a new one, or play one again"
        else -> Expeditions.previewLine()
    }
    ChunkyCard(fill = Pops.mint, onClick = onClick) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Terrain, null, tint = Color.White, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("EXPEDITIONS", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Color.White)
                    if (!isClub) {
                        Spacer(Modifier.width(6.dp))
                        Surface(shape = RoundedCornerShape(999.dp), color = Color.White) {
                            Text("CLUB", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Pops.mint,
                                modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp))
                        }
                    }
                }
                Text(subtitle, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, maxLines = 2)
            }
            Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.White)
        }
    }
}

@Composable
private fun StoryArchiveCard(store: Store, isClub: Boolean, onClick: () -> Unit) {
    val n = remember(isClub) { StoryArchive.count(store) }
    val subtitle = if (isClub) {
        if (n == 0) "Every story you unlock, kept here forever."
        else "$n stor${if (n == 1) "y" else "ies"} collected — searchable, forever."
    } else (remember(isClub) { StoryArchive.previewLine(store) } ?: "Club keeps every story you unlock, searchable forever.")
    ChunkyCard(fill = Pops.blue, onClick = onClick) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.AutoStories, null, tint = Color.White, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("STORY ARCHIVE", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Color.White)
                    if (!isClub) {
                        Spacer(Modifier.width(6.dp))
                        Surface(shape = RoundedCornerShape(999.dp), color = Color.White) {
                            Text("CLUB", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Pops.blue,
                                modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp))
                        }
                    }
                }
                Text(subtitle, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, maxLines = 2)
            }
            Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.White)
        }
    }
}

// Knowledge Atlas — Tidbits Club EXCLUSIVE (docs/CLUB-FEATURES-BUILD.md "Feature 4").
// The Records card (mirrors StoryArchiveCard/MarathonHistoryCard); the screen + row
// composables live near MarathonHistoryScreen below.
@Composable
private fun KnowledgeAtlasCard(store: Store, isClub: Boolean, onClick: () -> Unit) {
    val n = remember(isClub) { if (isClub) KnowledgeAtlas.domains(store).size else 0 }
    val subtitle = if (isClub) {
        if (n == 0) "Play across a few domains and your Atlas fills in."
        else "$n domain${if (n == 1) "" else "s"} mapped over 12 months — tap one to play it."
    } else (remember(isClub) { KnowledgeAtlas.previewLine(store) } ?: "Club maps everything you know and where it's drifting.")
    ChunkyCard(fill = Pops.pink, onClick = onClick) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Map, null, tint = Color.White, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("KNOWLEDGE ATLAS", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Color.White)
                    if (!isClub) {
                        Spacer(Modifier.width(6.dp))
                        Surface(shape = RoundedCornerShape(999.dp), color = Color.White) {
                            Text("CLUB", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Pops.pink,
                                modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp))
                        }
                    }
                }
                Text(subtitle, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, maxLines = 2)
            }
            Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.White)
        }
    }
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
                // Coverage disclosure (iOS + web already carry it): a mode x category the
                // bundle cannot fill still plays, assembled from other categories, and
                // silence about that reads as a lie. Dimmed, never disabled — taking the
                // choice away is a worse answer than telling the truth.
                Category.all.forEach { c ->
                    val thin = !Coverage.canFillAny(modes, c.id)
                    FilterChip(selected = cat.id == c.id, onClick = { cat = c },
                        label = { Text(c.name) },
                        modifier = Modifier.alpha(if (thin && cat.id != c.id) 0.45f else 1f))
                }
            }
            if (!Coverage.canFillAny(modes, cat.id)) {
                Text("${cat.name} has no questions for this mode yet — you'll get a mixed round.",
                    fontSize = 13.sp, color = fade)
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
    // .then(tvOverscan()) — TVs crop the outer ~5%; see TvFocus.kt. No-op off TV.
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).then(tvOverscan()),
           verticalArrangement = Arrangement.spacedBy(16.dp)) {
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
    // G7: the teams already in the room, so a second phone at a table can JOIN it
    // rather than quietly starting a near-identical second team.
    var roomTeams by remember { mutableStateOf<List<FirebaseNet.RoomTeam>>(emptyList()) }
    val scope = rememberCoroutineScope()

    // Look the room up as soon as the code is complete, so the tables are on
    // screen BEFORE the player commits to a name.
    LaunchedEffect(code) {
        roomTeams = if (code.length == 4) runCatching { FirebaseNet.liveRoomTeams(code) }.getOrDefault(emptyList())
                    else emptyList()
    }
    // .then(tvOverscan()) — TVs crop the outer ~5%; see TvFocus.kt. No-op off TV.
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).then(tvOverscan()),
           verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Join a game", fontSize = 28.sp, fontWeight = FontWeight.Black)
        Text("Enter a host's code — a Tidbits Live event or a Trivia Night. Works from anywhere.",
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        OutlinedTextField(
            value = code, onValueChange = { code = it.uppercase().filter { c -> c.isLetterOrDigit() }.take(4); error = null },
            label = { Text("Room code") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
        )
        OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Your name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        if (roomTeams.isNotEmpty()) {
            Text("Already playing — tap to join your table",
                fontSize = 13.sp, fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            // LazyRow, not Modifier.horizontalScroll: this file already imports it,
            // and a room with a dozen tables should not lay out every chip.
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(roomTeams) { t ->
                    // Tapping fills the LEADER's spelling — that is what keeps the
                    // table one row instead of two near-identical ones.
                    AssistChip(onClick = { name = t.name },
                        label = { Text(if (t.size > 1) "${t.name} · ${t.size}" else t.name) })
                }
            }
        }
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
    // Marathon (Club — docs/CLUB-FEATURES-BUILD.md "Feature 3"): resolve (or create)
    // the in-progress run FIRST, so the engine launches with the SAME fixed id list a
    // resume must continue into — the load-bearing new mechanic. `marathonPersisted`
    // tracks how many of THIS session's answers have already round-tripped through
    // Store — reset to 0 whenever a fresh/rebuilt run begins.
    var marathonRun by remember { mutableStateOf(if (route.mode == Mode.MARATHON) (Marathon.inProgress(store) ?: Marathon.startNew(store)) else null) }
    var marathonScore by remember { mutableStateOf<MarathonScore?>(null) }
    var marathonPersisted by remember { mutableIntStateOf(0) }
    val marathonQuestions = remember(marathonRun) { marathonRun?.let { Marathon.resumeQuestions(it) } }
    val game = remember { GameState(route.mode, route.category, store, marathonQuestions ?: route.custom, route.label, route.nightRounds, dailyDay = route.dailyDay, mixModes = route.mixModes, initialWeakSpotReasons = route.weakSpotReasons) }
    // Store-screenshot autopilot — the Kotlin mirror of the Apple loop
    // (docs/STORE-SCREENSHOTS.md §2). No-op unless the DEBUG intent extras are set.
    LaunchedEffect(Unit) {
        val h = com.learningischange.tidbitstrivia.data.ScreenshotHooks
        if (!h.autopilot) return@LaunchedEffect
        var stepsLeft = h.autopilotSteps
        while (game.phase != GamePhase.FINISHED && game.phase != GamePhase.ERROR) {
            if (stepsLeft != null && stepsLeft <= 0) return@LaunchedEffect
            kotlinx.coroutines.delay(900)
            if (stepsLeft != null) stepsLeft -= 1
            when (game.phase) {
                GamePhase.PLAYING -> game.submit(if (h.autopilotCorrect) (game.current?.correctIndex ?: 0) else 0)
                GamePhase.REVEAL -> game.advance()
                GamePhase.ROUND_INTRO -> game.startRound()
                else -> {}
            }
        }
    }
    LaunchedEffect(Unit) {
        val run = marathonRun
        if (route.mode == Mode.MARATHON && run != null && marathonQuestions.isNullOrEmpty()) {
            // Edge case only (a run somehow already at its full length without having
            // been finished) — close it out rather than show a blank round.
            marathonScore = Marathon.finish(store, run)
            marathonRun = null
        } else {
            if (route.mode == Mode.MARATHON) game.marathonOffset = run?.currentIndex ?: 0
            game.start()
        }
    }
    LaunchedEffect(game.index, game.phase) {
        while (game.phase == GamePhase.PLAYING) { delay(100); game.tick() }
    }
    // Correct/wrong haptics fire once per question when the reveal lands.
    LaunchedEffect(game.index, game.phase) {
        if (game.phase == GamePhase.REVEAL) { if (game.lastCorrect) haptics.correct() else haptics.wrong() }
    }
    // Marathon: persist EVERY answer the instant it posts (not batched) — a
    // crash/quit never loses progress (the whole point of Marathon). The instant the
    // run reaches its TRUE end, write the permanent scorecard and clear the run.
    LaunchedEffect(game.answered.size) {
        if (route.mode != Mode.MARATHON) return@LaunchedEffect
        var run = marathonRun ?: return@LaunchedEffect
        while (marathonPersisted < game.answered.size) {
            val a = game.answered[marathonPersisted]
            run = Marathon.record(store, run, MarathonAnswerRecord(a.q.id, a.q.categoryId, a.q.difficulty, a.correct))
            marathonPersisted++
        }
        marathonRun = run
        if (run.currentIndex >= run.total) {
            marathonScore = Marathon.finish(store, run)
            marathonRun = null
        }
    }
    if (route.mode == Mode.MARATHON && marathonScore != null) {
        // A local overlay, NOT a backStack.add(Route.MarathonHistory) push: this
        // composable's remember state (game, marathonScore, marathonRun) would be
        // torn down the instant another route becomes current (only one route
        // composes at a time), and popping back would re-enter this branch fresh —
        // silently starting a brand-new 200-question run. Toggling a local boolean
        // keeps this scorecard alive underneath.
        var showHistory by remember { mutableStateOf(false) }
        if (showHistory) {
            MarathonHistoryScreen(store, onBack = { showHistory = false }, onClub = {})
        } else {
            MarathonResultCard(store, marathonScore!!, historical = false,
                onPlayAgain = {
                    scope.launch {
                        val fresh = Marathon.startNew(store)
                        marathonRun = fresh
                        marathonScore = null
                        marathonPersisted = 0
                        game.marathonOffset = 0
                        game.rebuildMarathon(Marathon.resumeQuestions(fresh))
                        game.restart()
                    }
                },
                onSeeHistory = { showHistory = true },
                onDone = onDone)
        }
        return
    }
    // Expedition (Club — docs/CLUB-FEATURES-BUILD.md "Feature 5"): a stage is a normal
    // CLASSIC round — GameState.end() writes an ordinary GameRecord/misses/telemetry
    // ("a stage writes a normal record, it IS a real round"), no special-casing needed
    // there. Only the RESULT screen is special: once the round finishes, record the
    // stage outcome (pass/fail, and a certificate if this was the campaign's last
    // stage) exactly once, then show the pass/fail beat instead of ResultsScreen.
    val expedition = remember(route.expeditionId) { route.expeditionId?.let { Expeditions.named(it) } }
    val expeditionStage = remember(expedition, route.expeditionStageIndex) {
        expedition?.stages?.firstOrNull { it.index == route.expeditionStageIndex }
    }
    var expeditionOutcome by remember { mutableStateOf<Pair<Boolean, ExpeditionCertificate?>?>(null) }
    LaunchedEffect(game.phase) {
        if (game.phase == GamePhase.FINISHED && expedition != null && expeditionStage != null && expeditionOutcome == null) {
            // DEBUG-only verification hook (compiled out in release): force a full pass
            // regardless of the actual score — mirrors Apple's TIDBITS_EXPEDITION_FORCE_PASS
            // (autopilot can't reliably clear a real pass bar answering blind).
            val correct = if (BuildConfig.DEBUG && Expeditions.debugForcePass) expeditionStage.questionCount else game.correctCount
            expeditionOutcome = Expeditions.recordStageResult(store, expedition, expeditionStage.index, correct, expeditionStage.questionCount)
        }
    }
    if (expedition != null && expeditionStage != null && game.phase == GamePhase.FINISHED) {
        if (expeditionOutcome == null) {
            Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        } else {
            ExpeditionStageResultScreen(expedition, expeditionStage, game.correctCount, expeditionOutcome!!,
                onRetry = {
                    scope.launch {
                        expeditionOutcome = null
                        game.rebuildExpeditionStage(Expeditions.startStage(expedition, expeditionStage.index))
                        game.restart()
                    }
                },
                onDone = onDone)
        }
        return
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
        // The Daily is play-once (R-DAILY-1) — no replay of a locked set. Weak-Spot
        // Arena rebuilds fresh from the CURRENT miss store rather than replaying the
        // exact same (now partly-resolved) set — mirror of iOS/web's replay behavior.
        GamePhase.FINISHED -> {
            if (route.mode == Mode.MARATHON) {
                // Defensive fallback only — the LaunchedEffect above writes
                // marathonScore the instant the run's last answer posts, well before
                // this phase renders (answered.size changes during REVEAL, not here).
                Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            } else {
                ResultsScreen(game,
                    onPlayAgain = when {
                        route.mode == Mode.DAILY || route.duelId != null -> null
                        route.mode == Mode.WEAK_SPOT -> ({
                            scope.launch {
                                val round = WeakSpotArena.build(store)
                                if (round.questions.size >= WeakSpotArena.PLAYABLE_FLOOR) { game.rebuildWeakSpot(round); game.restart() }
                                else onDone()
                            }
                        })
                        else -> ({ scope.launch { game.restart() } })
                    },
                    onDone = onDone, duelId = route.duelId)
            }
        }
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
        // Weak-Spot Arena's "why you're seeing this" — transparency by construction,
        // never an opaque model (docs/CLUB-FEATURES-BUILD.md "Feature 1").
        if (game.mode == Mode.WEAK_SPOT) game.weakSpotReasons[q.id]?.let { reason ->
            Text(reason, color = accentText(Pops.grape), fontWeight = FontWeight.Bold, fontSize = 13.sp)
        }
        if (game.mode == Mode.SWEEP) SweepGrid(game)
        if (game.mode == Mode.STAKE && live) StakeSelector(game)
        // The bespoke shape panels draw their own controls instead of the MCQ
        // answer list, so the MCQ first-option requester never reaches them: the
        // focus audit found closest / ordering / matching / enumerate each
        // opening with 4-11 focusable controls and ZERO focused. One focusGroup
        // around the whole panel region hands focus to the first control of
        // whichever panel is showing, keyed per question like the MCQ path.
        val panelFocus = remember { FocusRequester() }
        val tvGame = isTv()
        val hasPanel = q.closest != null || q.ordering != null || q.matching != null ||
            q.enumerate != null
        LaunchedEffect(game.index, game.phase, hasPanel) {
            if (tvGame && hasPanel) {
                kotlinx.coroutines.delay(350)
                runCatching { panelFocus.requestFocus() }
            }
        }
        Column(Modifier.focusGroup().focusRequester(panelFocus),
               verticalArrangement = Arrangement.spacedBy(10.dp)) {
            q.closest?.let { ClosestPanel(game, it) }
            if (q.ordering != null) OrderingPanel(game)
            q.matching?.let { MatchingPanel(game, it) }
            q.enumerate?.let { spec -> if (live) EnumeratePanel(game, spec) }
        }
        if (q.accepted != null && live) {
            if (isTv()) {
                // Ten-foot free recall, matching the Apple TV idiom: a text
                // field on a remote is a keyboard wall, and the audit measured
                // this one as literally unreachable (0 focusable nodes). Recall
                // out loud, reveal, mark yourself.
                var revealed by remember(game.index) { mutableStateOf(false) }
                val selfFocus = remember(game.index) { FocusRequester() }
                LaunchedEffect(game.index, revealed) {
                    kotlinx.coroutines.delay(300); runCatching { selfFocus.requestFocus() }
                }
                if (!revealed) {
                    Text("Say your answer out loud, then reveal it.",
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
                    Button(onClick = { revealed = true },
                        modifier = Modifier.fillMaxWidth().focusRequester(selfFocus)
                            .tvFocus(RoundedCornerShape(20.dp), shadow = false),
                        colors = ButtonDefaults.buttonColors(containerColor = Pops.blue, contentColor = Color.White)) {
                        Text("Reveal the answer")
                    }
                } else {
                    ChunkyCard(fill = Pops.yellow.copy(alpha = 0.30f)) {
                        Text(q.answerText, Modifier.padding(16.dp).fillMaxWidth(),
                            fontWeight = FontWeight.Black, fontSize = 20.sp, textAlign = TextAlign.Center)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Button(onClick = { game.submitSelfMark(true) },
                            modifier = Modifier.weight(1f).focusRequester(selfFocus)
                                .tvFocus(RoundedCornerShape(20.dp), shadow = false),
                            colors = ButtonDefaults.buttonColors(containerColor = Pops.mint, contentColor = Ink)) {
                            Text("I got it")
                        }
                        Button(onClick = { game.submitSelfMark(false) },
                            modifier = Modifier.weight(1f).tvFocus(RoundedCornerShape(20.dp), shadow = false),
                            colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) {
                            Text("I missed it")
                        }
                    }
                }
            } else {
                OutlinedTextField(
                    value = game.typedText, onValueChange = { game.typedText = it },
                    placeholder = { Text("Type your answer…") }, singleLine = true,
                    keyboardActions = KeyboardActions(onDone = { game.submitText() }),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done, capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth())
                Button(onClick = { game.submitText() }, enabled = game.typedText.isNotBlank(), modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = Pops.mint, contentColor = Ink)) { Text("Submit") }
            }
        }
        val answersLocked = !live || (game.mode == Mode.STAKE && game.currentStake == 0)
        // MCQ buttons ONLY for a plain multiple-choice question. An Ordering question keeps
        // its items in `options`, so rendering these unconditionally drew the four items a
        // second time BELOW the ordering panel — and they were tappable, calling submit(i)
        // and scoring the question as an MCQ, bypassing the mode entirely. Same for the
        // other shapes that carry options. iOS branches these with else-if; Android did not.
        val plainMcq = q.closest == null && q.ordering == null && q.matching == null &&
            q.accepted == null && q.enumerate == null
        if (plainMcq) {
            // TV: a game screen opened with SIX focusable nodes and ZERO focused,
            // so a D-pad player could not answer at all — the options were
            // reachable but nothing held focus and CENTER did nothing. The first
            // option claims focus per QUESTION (keyed on index+phase, not once
            // ever): keying it once would leave later questions unfocused, and
            // re-firing it unkeyed would yank focus back while the player moves.
            val firstOption = remember { FocusRequester() }
            val tv = isTv()
            LaunchedEffect(game.index, game.phase, answersLocked) {
                if (tv && !answersLocked) runCatching { firstOption.requestFocus() }
            }
            q.options.forEachIndexed { i, opt ->
                AnswerButton(opt, game.answerState(i), !answersLocked,
                    focusMod = if (i == 0) Modifier.focusRequester(firstOption) else Modifier) {
                    game.submit(i)
                }
            }
        }
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
private fun AnswerButton(text: String, state: AnswerVisual, enabled: Boolean,
                         focusMod: Modifier = Modifier, onClick: () -> Unit) {
    val bg = when (state) { AnswerVisual.CORRECT -> Pops.mint; AnswerVisual.WRONG -> Pops.coral; else -> MaterialTheme.colorScheme.surface }
    // Ink on the light mint (white-on-mint is ~1.6:1); white on the deeper coral.
    val fg = when (state) { AnswerVisual.CORRECT -> Ink; AnswerVisual.WRONG -> Color.White; else -> MaterialTheme.colorScheme.onSurface }
    val shape = RoundedCornerShape(14.dp)
    Surface(onClick = onClick, enabled = enabled, shape = shape, color = bg,
        border = BorderStroke(2.5.dp, Ink),
        modifier = Modifier.fillMaxWidth().alpha(if (state == AnswerVisual.DIM) 0.45f else 1f)
            .then(focusMod).tvFocus(shape)) {
        Text(text, Modifier.padding(16.dp), color = fg, fontWeight = FontWeight.Bold, fontSize = 17.sp)
    }
}

// ---- Results ----

@Composable
private fun ResultsScreen(game: GameState, onPlayAgain: (() -> Unit)?, onDone: () -> Unit, duelId: String? = null) {
    val context = LocalContext.current
    if (duelId != null) LaunchedEffect(duelId) { com.learningischange.tidbitstrivia.data.Duels.submit(duelId, game.score) }   // L5: submit my duel score
    // Push (docs/PUSH-CONTRACT.md): ask for notifications WITH CONTEXT — right after a
    // Daily, where "your Daily is ready tomorrow" means something — never on cold launch.
    if (game.mode == Mode.DAILY) LaunchedEffect(Unit) {
        (context as? android.app.Activity)?.let {
            com.learningischange.tidbitstrivia.notifications.PushTokens.requestIfNeeded(it)
        }
        com.learningischange.tidbitstrivia.notifications.PushTokens.uploadTokenIfAllowed(context)
    }
    val total = game.answered.size
    val acc = if (total == 0) 0 else game.correctCount * 100 / total
    val grid = game.answered.joinToString("") { if (it.chosen == null) "⚫️" else if (it.correct) "🟢" else "🔴" }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(when { acc == 100 -> "FLAWLESS!"; acc >= 80 -> "BRILLIANT"; acc >= 50 -> "NICELY DONE"; else -> "GOOD RUN" }, fontWeight = FontWeight.Black, fontSize = 22.sp)
        Text("${game.score}", fontWeight = FontWeight.Black, fontSize = 64.sp)
        Text("${game.label ?: game.mode.title} · ${game.category.name}", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        // Weak-Spot Arena's payoff — "you didn't just play, you got better."
        if (game.mode == Mode.WEAK_SPOT) {
            val n = game.weakSpotGapsClosed
            ChunkyCard(fill = Pops.grape.copy(alpha = 0.18f)) {
                Column(Modifier.padding(vertical = 16.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("You closed $n gap${if (n == 1) "" else "s"}", fontWeight = FontWeight.Black, fontSize = 22.sp)
                    Text(if (n > 0) "Turned a miss into a win" else "Nothing to close yet this round",
                        fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                }
            }
        }
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
            val dayStreak = PlayerIdentity.displayStreak.current
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
                            // Carries the canonical /item/{id} twin (DEEP_LINKS.md) — without it
                            // the recipient gets a fact they can't follow anywhere.
                            val text = "I knew \"${a.q.prompt}\" on Tidbits Trivia — it's ${a.q.answerText}. How did YOU know that? 🧠\n" +
                                com.learningischange.tidbitstrivia.data.itemUrl(a.q.id)
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
private fun RecordsScreen(store: Store, onOpenArchive: () -> Unit, onOpenMarathonHistory: () -> Unit, onOpenAtlas: () -> Unit, onClub: () -> Unit) {
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
                Column { Text("DAY STREAK", color = Ink.copy(alpha = 0.7f), fontSize = 12.sp); Text("${PlayerIdentity.displayStreak.current} days", fontWeight = FontWeight.Black, fontSize = 26.sp, color = Ink) }
                Text("best ${PlayerIdentity.displayStreak.longest} 🔥", color = Ink, fontWeight = FontWeight.Bold)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatBox("${life.first}", "Games", Pops.grape); StatBox("${life.third}%", "Accuracy", Pops.blue); StatBox("${life.second}", "Correct", Pops.mint)
        }
        Text("Your games", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Text("Your latest rounds — ${tapVerbLower()} one to see the questions.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        // ANDROID-DESIGN §5.3: a bounded preview (3 most recent) + a "See all"
        // drill-in, so Records stays a dashboard, not a 40-card ledger.
        records.take(3).forEach { rec -> GameHistoryRow(rec) { recap = rec } }
        if (records.size > 3) ChunkyCard(onClick = { showAllGames = true }, modifier = Modifier.fillMaxWidth()) {
            Row(Modifier.padding(14.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                Text("See all ${records.size} games", fontWeight = FontWeight.Bold)
                Icon(Icons.Filled.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
            }
        }
        // Story Archive — Tidbits Club EXCLUSIVE (docs/CLUB-FEATURES-BUILD.md "Feature
        // 2"), a "see all" destination off the Records dashboard (R-REC-1). Members open
        // the searchable library directly; non-members get a real preview + a CLUB chip
        // and land on the paywall — never a blank wall (R-MON-1: the free in-moment story
        // reveal, right after answering, is untouched by this surface).

        // Marathon History — Tidbits Club EXCLUSIVE (docs/CLUB-FEATURES-BUILD.md
        // "Feature 3"), a permanent record of every completed 200-Q run — reachable
        // from Records in addition to the Home card's own post-game "See Marathon
        // history" link.

        // Knowledge Atlas — Tidbits Club EXCLUSIVE (docs/CLUB-FEATURES-BUILD.md "Feature
        // 4"), a "see all" destination off Records (R-REC-1). ADDITIVE: this does NOT
        // gate or duplicate the free Topic Levels / Pie sections just below — every
        // domain row inside the Atlas itself is a tap-to-play door, never a passive
        // readout (R-MON-1).

        val prog = remember { store.progress() }
        val explored = prog.count { it.total > 0 }
        val mastered = prog.count { it.hasWedge }
        Text("Your knowledge", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Text("Each domain levels up as you answer its questions correctly. You've explored $explored of 8 domains and mastered $mastered. A ✓ means mastered — 15+ right at 60%+ accuracy.",
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        prog.filter { it.total > 0 }.forEach { TopicRow(it) { drillDomain = it.id } }
        // L4: levelable badges — tiered milestones from BadgeMath (mirror of Core), hidden until one is earned.
        val totalQ = records.sumOf { it.total }
        val badges = BadgeMath.badges(
            games = records.size,
            longestStreak = PlayerIdentity.displayStreak.longest,
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
        Text("${tapVerb()} a mode to scroll your previous attempts.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
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
            Text("Newest first — ${tapVerbLower()} one to see the questions.", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            records.forEach { rec -> GameHistoryRow(rec) { onOpen(rec) } }
        }
    }
}

// ---- Story Archive (Tidbits Club EXCLUSIVE — docs/CLUB-FEATURES-BUILD.md "Feature 2") ----
// The persistent, searchable library of every story-behind-the-answer the player has
// unlocked (right or wrong). ADDITIVE: the free in-moment reveal (Question.explanation,
// shown right after answering) is untouched — R-MON-1. Android mirror of Apple's
// StoryArchiveView.swift / web's #/archive.

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StoryArchiveScreen(store: Store, onBack: () -> Unit, onClub: () -> Unit, onReask: (Question) -> Unit) {
    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Back") }
            Text("Story Archive", fontSize = 26.sp, fontWeight = FontWeight.Black, color = ink)
        }
        Spacer(Modifier.height(8.dp))

        if (!Entitlement.isClub) {
            StoryArchivePreview(store, onClub)
            return@Column
        }

        var favVersion by remember { mutableStateOf(0) }
        var text by remember { mutableStateOf("") }
        var filter by remember { mutableStateOf(StoryFilter.ALL) }
        var domain by remember { mutableStateOf<String?>(null) }
        var selected by remember { mutableStateOf<Store.SeenStory?>(null) }
        val all = remember(favVersion) { StoryArchive.list(store) }
        val domains = remember(all) { StoryArchive.domainsSeen(store) }
        val results = remember(text, filter, domain, all) { StoryArchive.search(store, text, domain, filter) }

        if (all.isEmpty()) {
            ChunkyCard { Column(Modifier.padding(20.dp)) {
                Text("Play a few rounds — the stories you unlock are kept here forever.", fontWeight = FontWeight.Bold)
            } }
            return@Column
        }

        Text("${all.size} stor${if (all.size == 1) "y" else "ies"} kept — search or filter, then tap one to read it again.",
            fontSize = 13.sp, color = soft)
        Spacer(Modifier.height(10.dp))
        OutlinedTextField(
            value = text, onValueChange = { text = it }, singleLine = true,
            leadingIcon = { Icon(Icons.Filled.Search, null) },
            placeholder = { Text("Search prompts, answers, stories…") },
            modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(10.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            StoryFilter.entries.forEach { f -> FilterChip(selected = filter == f, onClick = { filter = f }, label = { Text(f.label) }) }
        }
        if (domains.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = domain == null, onClick = { domain = null }, label = { Text("All domains") })
                domains.forEach { c -> FilterChip(selected = domain == c.id, onClick = { domain = c.id }, label = { Text(c.name) }) }
            }
        }
        Spacer(Modifier.height(10.dp))

        if (results.isEmpty()) {
            ChunkyCard { Column(Modifier.padding(20.dp)) { Text("No stories match.", color = soft) } }
        } else {
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(results, key = { it.qid }) { s -> StoryCard(s, onClick = { selected = s }, onToggleFav = { store.toggleStoryFavorite(s.qid); favVersion++ }) }
            }
        }
        selected?.let { s ->
            StoryDetailSheet(store, s,
                onDismiss = { selected = null },
                onFavToggle = { favVersion++ },
                onReask = { q -> selected = null; onReask(q) })
        }
    }
}

@Composable
private fun StoryArchivePreview(store: Store, onClub: () -> Unit) {
    val preview = remember { StoryArchive.previewLine(store) }
        ?: "“Marie Curie is the only person to win Nobel Prizes in two different sciences.” — Club keeps every story you unlock, searchable forever."
    ChunkyCard { Column(Modifier.padding(18.dp)) { Text(preview, fontWeight = FontWeight.Bold) } }
    Spacer(Modifier.height(14.dp))
    ChunkyCard(fill = Pops.blue.copy(alpha = 0.12f)) {
        Column(Modifier.padding(20.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Club keeps every story you unlock, searchable forever.", fontWeight = FontWeight.Black, fontSize = 18.sp, textAlign = TextAlign.Center)
            Text("A permanent, searchable library of every fact you've met — favorite the ones worth keeping.",
                fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), textAlign = TextAlign.Center)
            Spacer(Modifier.height(12.dp))
            Button(onClick = onClub) { Text("Join Tidbits Club") }
        }
    }
}

// One story card: domain tag, when, right/wrong marker, favorite toggle, prompt + answer.
@Composable
private fun StoryCard(s: Store.SeenStory, onClick: () -> Unit, onToggleFav: () -> Unit) {
    val cat = Category.byId(s.categoryId)
    ChunkyCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Surface(shape = RoundedCornerShape(999.dp), color = Pops.at(cat.colorIndex)) {
                    Text(cat.name, fontSize = 12.sp, fontWeight = FontWeight.Black, color = Color.White,
                        modifier = Modifier.padding(horizontal = 9.dp, vertical = 2.dp))
                }
                Text(relativeTime(s.lastSeen), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                Spacer(Modifier.weight(1f))
                Icon(if (s.everCorrect) Icons.Filled.CheckCircle else Icons.Filled.Cancel, null,
                    tint = if (s.everCorrect) accentText(Pops.mint) else accentText(Pops.coral), modifier = Modifier.size(18.dp))
                IconButton(onClick = onToggleFav, modifier = Modifier.size(28.dp)) {
                    Icon(if (s.favorite) Icons.Filled.Star else Icons.Filled.StarBorder, "Favorite",
                        tint = if (s.favorite) Pops.yellow else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
                }
            }
            Text(s.prompt, fontWeight = FontWeight.Bold)
            Text("Answer: ${s.answer}", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StoryDetailSheet(store: Store, s: Store.SeenStory, onDismiss: () -> Unit, onFavToggle: () -> Unit, onReask: (Question) -> Unit) {
    var fav by remember(s.qid) { mutableStateOf(s.favorite) }
    val cat = Category.byId(s.categoryId)
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Surface(shape = RoundedCornerShape(999.dp), color = Pops.at(cat.colorIndex), modifier = Modifier.width(IntrinsicSize.Min)) {
                Text(cat.name, fontSize = 12.sp, fontWeight = FontWeight.Black, color = Color.White,
                    modifier = Modifier.padding(horizontal = 9.dp, vertical = 3.dp))
            }
            Text(s.prompt, fontWeight = FontWeight.Black, fontSize = 20.sp)
            Text("Answer: ${s.answer}", fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
            if (s.story.isNotBlank()) Text(s.story, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.85f))
            else Text("No story recorded for this one.", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(onClick = { fav = store.toggleStoryFavorite(s.qid); onFavToggle() }) {
                    Icon(if (fav) Icons.Filled.Star else Icons.Filled.StarBorder, null, tint = if (fav) Pops.yellow else LocalContentColor.current)
                    Spacer(Modifier.width(6.dp))
                    Text(if (fav) "Favorited" else "Favorite")
                }
                s.question?.let { q -> Button(onClick = { onReask(q) }) { Text("Re-ask this") } }
            }
        }
    }
}

// ---- Marathon (Tidbits Club EXCLUSIVE — docs/CLUB-FEATURES-BUILD.md "Feature 3") ----
// A 200-question graded endurance run whose load-bearing NEW mechanic is
// RESUME ACROSS SESSIONS (see data/Marathon.kt + GameScreen's marathon handling
// above). This section is the surface: the Records/Home "Marathon History" card
// (mirrors StoryArchiveCard), the history list + resume banner, and the shared
// scorecard used both right after finishing AND for a historical detail view.

@Composable
private fun MarathonHistoryCard(store: Store, isClub: Boolean, onClick: () -> Unit) {
    val history = remember(isClub) { if (isClub) Marathon.history(store) else emptyList() }
    val subtitle = if (isClub) {
        if (history.isEmpty()) "200 questions. Play it across as many sittings as you like — we'll keep your place."
        else "${history.size} run${if (history.size == 1) "" else "s"} played — best ${(history.maxOf { it.accuracy } * 100).roundToInt()}%."
    } else Marathon.previewLine()
    ChunkyCard(fill = Pops.teal, onClick = onClick) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Flag, null, tint = Color.White, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("MARATHON HISTORY", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Color.White)
                    if (!isClub) {
                        Spacer(Modifier.width(6.dp))
                        Surface(shape = RoundedCornerShape(999.dp), color = Color.White) {
                            Text("CLUB", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Pops.teal,
                                modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp))
                        }
                    }
                }
                Text(subtitle, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, maxLines = 2)
            }
            Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.White)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MarathonHistoryScreen(store: Store, onBack: () -> Unit, onClub: () -> Unit) {
    val ink = MaterialTheme.colorScheme.onSurface
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Back") }
            Text("Marathon History", fontSize = 24.sp, fontWeight = FontWeight.Black, color = ink)
        }
        Spacer(Modifier.height(8.dp))

        if (!Entitlement.isClub) {
            ChunkyCard { Column(Modifier.padding(18.dp)) { Text(Marathon.previewLine(), fontWeight = FontWeight.Bold) } }
            Spacer(Modifier.height(14.dp))
            ChunkyCard(fill = Pops.teal.copy(alpha = 0.12f)) {
                Column(Modifier.padding(20.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("A 200-question test of everything, graded by domain.", fontWeight = FontWeight.Black, fontSize = 18.sp, textAlign = TextAlign.Center)
                    Text("Play it across as many sittings as you like — we keep your place, and every run is measured against your last.",
                        fontSize = 13.sp, color = ink.copy(alpha = 0.6f), textAlign = TextAlign.Center)
                    Spacer(Modifier.height(12.dp))
                    Button(onClick = onClub) { Text("Join Tidbits Club") }
                }
            }
            return@Column
        }

        var selected by remember { mutableStateOf<MarathonScore?>(null) }
        val runs = remember { Marathon.history(store) }
        val active = remember { Marathon.inProgress(store) }
        if (active != null) {
            ChunkyCard(fill = Pops.teal.copy(alpha = 0.14f), modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp).fillMaxWidth()) {
                    Text("Question ${active.currentIndex + 1} of ${active.total}", fontWeight = FontWeight.Black)
                    Text("A run is in progress — resume it from Home.", fontSize = 13.sp, color = ink.copy(alpha = 0.6f))
                }
            }
            Spacer(Modifier.height(10.dp))
        }

        if (runs.isEmpty()) {
            ChunkyCard { Column(Modifier.padding(20.dp)) {
                Text("No Marathons yet — play one across as many sittings as you like, we'll keep your place.", fontWeight = FontWeight.Bold)
            } }
        } else {
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(runs, key = { it.date }) { s ->
                    ChunkyCard(onClick = { selected = s }, modifier = Modifier.fillMaxWidth()) {
                        Row(Modifier.padding(14.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                            Column {
                                Text("${s.correct}/${s.total} correct · ${(s.accuracy * 100).roundToInt()}%", fontWeight = FontWeight.Bold)
                                Text(java.text.DateFormat.getDateInstance().format(java.util.Date(s.date)), fontSize = 12.sp, color = ink.copy(alpha = 0.6f))
                            }
                            Text("${s.score}", fontWeight = FontWeight.Black, fontSize = 20.sp, color = Pops.teal)
                        }
                    }
                }
            }
        }
        selected?.let { s ->
            ModalBottomSheet(onDismissRequest = { selected = null }) {
                MarathonResultCard(store, s, historical = true, onPlayAgain = null, onSeeHistory = null, onDone = { selected = null })
            }
        }
    }
}

/** The Marathon scorecard — shared by the just-finished flow (GameScreen) and a past
 *  run's read-only detail (MarathonHistoryScreen). Unlike ResultsScreen (which reads
 *  the current session's local state), this reads the permanent MarathonScore, because
 *  a run's true total spans however many sessions it took to finish, not just one. */
@Composable
private fun MarathonResultCard(
    store: Store, score: MarathonScore, historical: Boolean,
    onPlayAgain: (() -> Unit)?, onSeeHistory: (() -> Unit)?, onDone: (() -> Unit)?,
) {
    val history = remember(score) { Marathon.history(store) }
    val previous = remember(score, history) { history.firstOrNull { it.date < score.date } }
    val acc = if (score.total == 0) 0 else (score.accuracy * 100).roundToInt()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        ChunkyCard(fill = Pops.teal.copy(alpha = 0.18f), modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(vertical = 26.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("MARATHON COMPLETE", fontWeight = FontWeight.Black, fontSize = 15.sp)
                Text("${score.score}", fontWeight = FontWeight.Black, fontSize = 56.sp)
                Text("${score.correct}/${score.total} correct · ${marathonDurationLabel(score.durationSeconds)}",
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
        // "+6% vs your last run" — the measured-mastery payoff (the whole reason
        // Marathon isn't just a long Classic).
        ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(vertical = 14.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                if (previous != null) {
                    val delta = ((score.accuracy - previous.accuracy) * 100).roundToInt()
                    Text(if (delta == 0) "Same as your last run" else "${if (delta > 0) "+" else ""}$delta% vs your last run",
                        fontWeight = FontWeight.Black, fontSize = 18.sp,
                        color = if (delta >= 0) accentText(Pops.mint) else accentText(Pops.coral))
                    Text("Last run: ${(previous.accuracy * 100).roundToInt()}% · this run: $acc%",
                        fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                } else {
                    Text("Your first Marathon", fontWeight = FontWeight.Black, fontSize = 18.sp)
                    Text("Play another to see how you're improving", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatBox("$acc%", "Accuracy", Pops.blue)
            StatBox("${score.score}", "Score", Pops.teal)
            StatBox("${history.size}", "Marathons", Pops.coral)
        }
        // Per-domain accuracy bars — the measured-mastery map, not just a score.
        ChunkyCard(modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Where you stood this run", fontWeight = FontWeight.Black, fontSize = 18.sp)
                score.domainBreakdown.filter { it.total > 0 }.forEach { stat -> MarathonDomainRow(stat) }
            }
        }
        if (!historical && onSeeHistory != null) TextButton(onClick = onSeeHistory) { Text("See Marathon history") }
        if (onPlayAgain != null) Button(onClick = onPlayAgain, modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Pops.teal, contentColor = Color.White)) { Text("Start a new Marathon") }
        if (onDone != null) TextButton(onClick = onDone) { Text("Done") }
    }
}

@Composable
private fun MarathonDomainRow(stat: MarathonDomainStat) {
    val cat = Category.byId(stat.categoryId)
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(categoryIcon(cat.id), null, tint = accentText(Pops.at(cat.colorIndex)), modifier = Modifier.size(16.dp))
                Text(cat.name, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            }
            Text("${stat.correct}/${stat.total} · ${(stat.accuracy * 100).roundToInt()}%", fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
        Spacer(Modifier.height(4.dp))
        LinearProgressIndicator(progress = { stat.accuracy.toFloat() }, modifier = Modifier.fillMaxWidth().height(8.dp), color = Pops.at(cat.colorIndex))
    }
}

private fun marathonDurationLabel(seconds: Double): String {
    val minutes = (seconds / 60).roundToInt()
    if (minutes < 60) return "${maxOf(1, minutes)} min"
    val hrs = minutes / 60; val rem = minutes % 60
    return if (rem == 0) "${hrs}h" else "${hrs}h ${rem}m"
}

// ---- Knowledge Atlas (Tidbits Club EXCLUSIVE — docs/CLUB-FEATURES-BUILD.md "Feature
// 4") ---- A transparent, interpreted layer over the SAME per-game rows the free Topic
// Levels / Pie already read (data/KnowledgeAtlas.kt) — additive, never a lock on what's
// already free (R-MON-1). The trap to avoid (design spec): "a passive Sporcle stats
// page." So EVERY domain row here is a tap target that launches a real round in that
// domain (Route.Game(Mode.CLASSIC, category) — the same launch path Quick Play uses) —
// it interprets AND acts, never a passive readout. Decay rows carry their own "Shore it
// up" round. Android mirror of Apple's KnowledgeAtlasView.swift / web's #/atlas.

@Composable
private fun KnowledgeAtlasScreen(store: Store, onBack: () -> Unit, onClub: () -> Unit, onPlay: (String, String) -> Unit) {
    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Back") }
            Text("Knowledge Atlas", fontSize = 24.sp, fontWeight = FontWeight.Black, color = ink)
        }
        Spacer(Modifier.height(8.dp))

        if (!Entitlement.isClub) {
            val preview = remember { KnowledgeAtlas.previewLine(store) }
                ?: "Club maps every domain you play across 12 months and shows what's rising or drifting."
            ChunkyCard { Column(Modifier.padding(18.dp)) { Text(preview, fontWeight = FontWeight.Bold) } }
            Spacer(Modifier.height(14.dp))
            ChunkyCard(fill = Pops.pink.copy(alpha = 0.12f)) {
                Column(Modifier.padding(20.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("A map of what you actually know, by domain, over time.", fontWeight = FontWeight.Black, fontSize = 18.sp, textAlign = TextAlign.Center)
                    Text("Plain accuracy and sample counts — no opaque score. Tap any domain to play a round in it.",
                        fontSize = 13.sp, color = soft, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(12.dp))
                    Button(onClick = onClub) { Text("Join Tidbits Club") }
                }
            }
            return@Column
        }

        val domains = remember { KnowledgeAtlas.domains(store) }
        val decaying = remember { KnowledgeAtlas.decayRadar(store) }

        if (domains.isEmpty()) {
            ChunkyCard { Column(Modifier.padding(20.dp)) {
                Text("Not enough history yet.", fontWeight = FontWeight.Bold)
                Text("Play across a few domains and your Atlas fills in — it needs a few weeks of history to show a trajectory.",
                    fontSize = 13.sp, color = soft)
            } }
            return@Column
        }

        Text("Your accuracy by domain over the trailing 12 months. Tap any domain to play a round in it.",
            fontSize = 13.sp, color = soft)
        Spacer(Modifier.height(10.dp))
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(domains, key = { it.categoryId }) { d -> AtlasDomainRow(d) { onPlay(d.categoryId, "Knowledge Atlas") } }
            if (decaying.isNotEmpty()) {
                item(key = "atlas-decay-header") {
                    Column(Modifier.padding(top = 8.dp)) {
                        Text("Decay radar", fontWeight = FontWeight.Black, fontSize = 18.sp, color = ink)
                        Text("Domains you were strong in 6+ months ago that have since slipped.", fontSize = 13.sp, color = soft)
                    }
                }
                items(decaying, key = { "atlas-decay-${it.categoryId}" }) { entry -> AtlasDecayRow(entry) { onPlay(entry.categoryId, "Shore it up") } }
            }
        }
    }
}

// Domain row: colored category glyph, accuracy %, sample size, trajectory arrow — every
// number a door, so the WHOLE row is a tap target into a round (mirrors TopicRow's chrome).
@Composable
private fun AtlasDomainRow(entry: KnowledgeAtlas.DomainAtlasEntry, onClick: () -> Unit) {
    val cat = Category.byId(entry.categoryId)
    val col = Pops.at(cat.colorIndex)
    val pct = (entry.accuracy * 100).roundToInt()
    ChunkyCard(onClick = onClick) {
        Row(Modifier.padding(12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(36.dp).background(col, CircleShape).border(2.5.dp, Ink, CircleShape), contentAlignment = Alignment.Center) {
                Icon(categoryIcon(cat.id), null, tint = onAccent(col), modifier = Modifier.size(18.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(cat.name, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    entry.trajectoryDelta?.let { delta ->
                        val up = delta >= 0
                        Surface(shape = RoundedCornerShape(999.dp), color = if (up) Pops.mint else Pops.coral, border = BorderStroke(2.dp, Ink)) {
                            Row(Modifier.padding(horizontal = 7.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(if (up) Icons.Filled.TrendingUp else Icons.Filled.TrendingDown, null, tint = Color.White, modifier = Modifier.size(12.dp))
                                Text("${(kotlin.math.abs(delta) * 100).roundToInt()}", color = Color.White, fontWeight = FontWeight.Black, fontSize = 11.sp)
                            }
                        }
                    }
                    Text("$pct%", fontWeight = FontWeight.Black, fontSize = 15.sp)
                    Icon(Icons.Filled.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
                }
                Box(Modifier.fillMaxWidth().height(12.dp).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(999.dp)).border(2.dp, Ink, RoundedCornerShape(999.dp))) {
                    Box(Modifier.fillMaxWidth(entry.accuracy.toFloat().coerceIn(0.05f, 1f)).fillMaxHeight().background(col, RoundedCornerShape(999.dp)))
                }
                Text("${entry.correct}/${entry.sampleSize} answered · last 12 months", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
    }
}

// Decay radar row: past -> now accuracy, with its own "Shore it up" round button.
@Composable
private fun AtlasDecayRow(entry: KnowledgeAtlas.DecayEntry, onPlay: () -> Unit) {
    val cat = Category.byId(entry.categoryId)
    val col = Pops.at(cat.colorIndex)
    ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant) {
        Row(Modifier.padding(12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(36.dp).background(col, CircleShape).border(2.5.dp, Ink, CircleShape), contentAlignment = Alignment.Center) {
                Icon(categoryIcon(cat.id), null, tint = onAccent(col), modifier = Modifier.size(18.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(cat.name, fontWeight = FontWeight.Bold)
                Text("${(entry.pastAccuracy * 100).roundToInt()}% then → ${(entry.recentAccuracy * 100).roundToInt()}% now",
                    fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
            Button(onClick = onPlay, colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Shore it up") }
        }
    }
}

// ---- Expeditions (Tidbits Club EXCLUSIVE — docs/CLUB-FEATURES-BUILD.md "Feature 5")
// ---- A multi-week structured campaign through one domain: an ordered list of themed
// stages, a visible map/path, and a completion certificate — assembled from the
// EXISTING engine (data/Expeditions.kt), no new game mode. UNLIKE the other Club
// surfaces above, the hub and an expedition's map are curated CONTENT — a real preview
// reachable by EVERYONE; only tapping Play on the current stage is Club-gated (routes
// non-members to the existing paywall). Android mirror of Apple's ExpeditionsView.swift
// / web's #/expeditions.

@Composable
private fun ExpeditionsHubScreen(store: Store, onBack: () -> Unit, onOpenMap: (String) -> Unit) {
    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)
    val progressRows = remember { Expeditions.available(store).associate { it.first.id to it.second } }
    val certificates = remember { Expeditions.certificates(store) }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Back") }
            Text("Expeditions", fontSize = 24.sp, fontWeight = FontWeight.Black, color = ink)
        }
        Spacer(Modifier.height(4.dp))
        Text(Expeditions.previewLine(), fontSize = 13.sp, color = soft)
        Spacer(Modifier.height(14.dp))
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(Expeditions.all, key = { it.id }) { expedition ->
                ExpeditionRow(expedition, progressRows[expedition.id], certificates.any { it.expeditionId == expedition.id }) {
                    onOpenMap(expedition.id)
                }
            }
            if (certificates.isNotEmpty()) {
                item(key = "expeditions-completed-header") {
                    Text("Completed", fontWeight = FontWeight.Black, fontSize = 18.sp, color = ink, modifier = Modifier.padding(top = 8.dp))
                }
                items(certificates, key = { "expedition-cert-${it.expeditionId}-${it.completedAt}" }) { cert -> ExpeditionCertRow(cert) }
            }
        }
    }
}

@Composable
private fun ExpeditionRow(expedition: Expedition, progress: ExpeditionProgress?, hasCertificate: Boolean, onClick: () -> Unit) {
    val col = Pops.at(Category.byId(expedition.domain).colorIndex)
    val subtitle = when {
        progress != null -> "Stage ${minOf(progress.currentStageIndex + 1, expedition.stageCount)} of ${expedition.stageCount} — tap to continue"
        hasCertificate -> "Completed — tap to play again"
        else -> expedition.subtitle
    }
    ChunkyCard(fill = col, onClick = onClick) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(categoryIcon(expedition.domain), null, tint = onAccent(col), modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(expedition.title.uppercase(), fontWeight = FontWeight.Black, fontSize = 18.sp, color = onAccent(col))
                Text(subtitle, fontSize = 13.sp, color = onAccent(col).copy(alpha = 0.85f), maxLines = 3)
            }
            Icon(Icons.Filled.KeyboardArrowRight, null, tint = onAccent(col))
        }
    }
}

@Composable
private fun ExpeditionCertRow(cert: ExpeditionCertificate) {
    ChunkyCard(fill = MaterialTheme.colorScheme.surfaceVariant) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.WorkspacePremium, null, tint = Pops.mint, modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(cert.title, fontWeight = FontWeight.Bold)
                Text("${cert.stagesCompleted} stages · ${cert.totalScore} correct · ${java.text.DateFormat.getDateInstance().format(java.util.Date(cert.completedAt))}",
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
    }
}

@Composable
private fun ExpeditionMapScreen(store: Store, expeditionId: String, onBack: () -> Unit, onClub: () -> Unit, onPlayStage: (Expedition, Int) -> Unit) {
    val expedition = remember(expeditionId) { Expeditions.named(expeditionId) }
    if (expedition == null) { LaunchedEffect(Unit) { onBack() }; return }
    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)
    val progress = remember(expeditionId) { Expeditions.progress(store, expeditionId) }
    val hasCertificate = remember(expeditionId) { Expeditions.certificates(store).any { it.expeditionId == expeditionId } }
    val currentStageIndex = progress?.currentStageIndex ?: 0
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Back") }
            Text(expedition.title, fontSize = 20.sp, fontWeight = FontWeight.Black, color = ink, maxLines = 1)
        }
        Spacer(Modifier.height(4.dp))
        Text(expedition.subtitle, fontSize = 13.sp, color = soft)
        Spacer(Modifier.height(6.dp))
        if (hasCertificate && progress == null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.WorkspacePremium, null, tint = Pops.mint, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text("Completed — play again for another certificate", fontSize = 13.sp, color = Pops.mint, fontWeight = FontWeight.Bold)
            }
        } else {
            Text("${expedition.stageCount} stages · pick up where you left off, any time", fontSize = 13.sp, color = soft)
        }
        Spacer(Modifier.height(16.dp))
        LazyColumn(Modifier.weight(1f).fillMaxWidth()) {
            items(expedition.stages, key = { it.index }) { stage ->
                ExpeditionStageRow(stage, currentStageIndex, onPlay = {
                    if (Entitlement.isClub) onPlayStage(expedition, stage.index) else onClub()
                })
                if (stage.index != expedition.stages.size - 1) {
                    Box(Modifier.padding(start = 17.dp).width(2.dp).height(14.dp).background(MaterialTheme.colorScheme.outlineVariant))
                }
            }
        }
        if (!Entitlement.isClub) {
            Spacer(Modifier.height(8.dp))
            Text("Join Tidbits Club to play this expedition. Everything above is a preview — no charge to look around.",
                fontSize = 12.sp, color = soft)
        }
    }
}

@Composable
private fun ExpeditionStageRow(stage: ExpeditionStage, currentStageIndex: Int, onPlay: () -> Unit) {
    val ink = MaterialTheme.colorScheme.onSurface
    val done = stage.index < currentStageIndex
    val isCurrent = stage.index == currentStageIndex
    val locked = !done && !isCurrent
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp).alpha(if (locked) 0.55f else 1f), verticalAlignment = Alignment.Top) {
        Box(
            Modifier.size(34.dp)
                .background(if (done) Pops.mint else if (isCurrent) Pops.coral else MaterialTheme.colorScheme.surfaceVariant, CircleShape)
                .border(2.5.dp, Ink, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            when {
                done -> Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(16.dp))
                locked -> Icon(Icons.Filled.Lock, null, tint = ink.copy(alpha = 0.6f), modifier = Modifier.size(14.dp))
                else -> Text("${stage.index + 1}", fontWeight = FontWeight.Black, color = Color.White)
            }
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(stage.title, fontWeight = FontWeight.Bold, fontSize = 16.sp, color = if (locked) ink.copy(alpha = 0.6f) else ink)
            Text(stage.blurb, fontSize = 13.sp, color = ink.copy(alpha = 0.6f), maxLines = 2)
            if (isCurrent) {
                Spacer(Modifier.height(6.dp))
                Button(onClick = onPlay, colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Play") }
            }
        }
    }
}

/** The post-stage beat (pass unlocks the next stage; fail offers "Try Again"; the
 *  campaign's last stage passing shows a certificate card) — reuses [StatBox] the same
 *  way MarathonResultCard/ResultsScreen do. */
@Composable
private fun ExpeditionStageResultScreen(
    expedition: Expedition, stage: ExpeditionStage, correct: Int,
    outcome: Pair<Boolean, ExpeditionCertificate?>, onRetry: () -> Unit, onDone: () -> Unit,
) {
    val (passed, certificate) = outcome
    val ink = MaterialTheme.colorScheme.onSurface
    val nextStageNumber = minOf(stage.index + 2, expedition.stageCount)
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp), horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        ChunkyCard(fill = (if (passed) Pops.mint else Pops.coral).copy(alpha = 0.16f), modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(vertical = 22.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    if (certificate != null) Icons.Filled.WorkspacePremium else if (passed) Icons.Filled.CheckCircle else Icons.Filled.Replay,
                    null, tint = if (passed) Pops.mint else Pops.coral, modifier = Modifier.size(44.dp),
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    if (certificate != null) "EXPEDITION COMPLETE" else if (passed) "STAGE ${stage.index + 1} PASSED" else "NOT QUITE",
                    fontWeight = FontWeight.Black, fontSize = 22.sp, color = ink,
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    when {
                        certificate != null -> "You completed ${expedition.title} — every stage, start to finish."
                        passed -> "${stage.title} is done. Stage $nextStageNumber just unlocked."
                        else -> "Needed ${stage.passBar} of ${stage.questionCount} to advance — you got $correct. Give it another go."
                    },
                    fontSize = 14.sp, color = ink.copy(alpha = 0.7f), textAlign = TextAlign.Center,
                )
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatBox("$correct/${stage.questionCount}", "Correct", Pops.blue)
            StatBox("${stage.passBar}", "Pass bar", Pops.mint)
            StatBox("${minOf(stage.index + (if (passed) 2 else 1), expedition.stageCount)}/${expedition.stageCount}", "Stage", Pops.coral)
        }
        if (certificate != null) {
            ChunkyCard(fill = Pops.mint, modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(18.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("CERTIFICATE EARNED", fontWeight = FontWeight.Black, fontSize = 15.sp, color = Color.White)
                    Text(certificate.title, fontWeight = FontWeight.Black, fontSize = 20.sp, color = Color.White)
                    Text("${certificate.stagesCompleted} stages · ${certificate.totalScore} correct total",
                        fontSize = 13.sp, color = Color.White.copy(alpha = 0.85f))
                }
            }
        }
        if (passed) {
            Button(onClick = onDone, modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Pops.mint, contentColor = Color.White)) {
                Text(if (certificate != null) "Done" else "Continue")
            }
        } else {
            Button(onClick = onRetry, modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Pops.coral, contentColor = Color.White)) { Text("Try Again") }
            TextButton(onClick = onDone) { Text("Back to map") }
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
    var saved by remember { mutableStateOf(com.learningischange.tidbitstrivia.data.QuizStore.all()) }
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current
    var playMode by remember { mutableStateOf("mix") }
    // Re-read on every appearance, not just first composition. A quiz that arrives
    // from a share link is written AFTER this screen composes, so a remembered list
    // showed the shelf without it — the link looked like it had done nothing.
    LaunchedEffect(Unit) { saved = com.learningischange.tidbitstrivia.data.QuizStore.all() }
    val suggestions = listOf("The Solar System", "Ancient Rome", "Jazz", "Volcanoes", "The Olympics", "Marie Curie")
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
            val mcq = Corpus.search(topicT, maxOf(4, 8 - shaped.size))
            var pool = mcq + shaped
            if (pool.size < 8) {
                // Top up rather than only rescuing a near-total miss: live generation
                // used to fire ONLY below three, so a topic with six silently
                // delivered six.
                val have = pool.map { it.id }.toSet()
                pool = pool + Wikipedia.generate(topicT, "mixed", 8 - pool.size + 2)
                    .filter { it.id !in have }
            }
            val qs = pool.shuffled().take(8)
            working = false
            if (qs.size >= 3) {
                // Every created quiz is saved automatically — the player never has to
                // notice a Save button to keep what they made.
                com.learningischange.tidbitstrivia.data.QuizStore.saveCreated(
                    qs, topicT,
                    creatorId = com.learningischange.tidbitstrivia.data.PlayerIdentity.profileId ?: "local",
                    creatorName = com.learningischange.tidbitstrivia.data.PlayerIdentity.profile?.name ?: "",
                    mode = playMode,
                )
                saved = com.learningischange.tidbitstrivia.data.QuizStore.all()
                onPlay(qs, topicT)
            } else error = "Couldn't build a good quiz for “$topicT”. Try a broader subject."
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
        Text("Play it as", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(com.learningischange.tidbitstrivia.data.SavedQuiz.PLAYABLE_MODES, key = { it }) { m ->
                FilterChip(
                    selected = playMode == m,
                    onClick = { playMode = m },
                    label = { Text(com.learningischange.tidbitstrivia.data.SavedQuiz.modeLabel(m)) },
                )
            }
        }

        Text("Need a spark?", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(suggestions, key = { it }) { s -> AssistChip(onClick = { topic = s; generate(s) }, label = { Text(s) }) }
        }

        // Every created quiz is kept. The empty line teaches the mechanic on first
        // run instead of leaving a blank wall (universal-feature-states).
        Text("Your quizzes", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        if (saved.isEmpty()) {
            Text(
                "Quizzes you make are saved here automatically, ready to replay.",
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            )
        } else {
            saved.forEach { quiz ->
                SavedQuizRow(
                    quiz = quiz,
                    onPlay = {
                        // A quiz can legitimately come up short (an older corpus, a
                        // set this build lacks), so say so rather than padding it.
                        val r = com.learningischange.tidbitstrivia.data.QuizStore.resolveForPlay(quiz)
                        // A quiz saved as Survival must replay as Survival — the mode
                        // was recorded and then ignored before this.
                        if (r.isPlayable) { playMode = com.learningischange.tidbitstrivia.data.SavedQuiz.playableMode(quiz.mode); onPlay(r.questions, quiz.title) }
                        else error = "This quiz needs questions your version doesn't have yet. Try creating it again from “${quiz.topic}”."
                    },
                    onDelete = {
                        com.learningischange.tidbitstrivia.data.QuizStore.delete(quiz.id)
                        saved = com.learningischange.tidbitstrivia.data.QuizStore.all()
                    },
                    onShare = {
                        scope.launch {
                            // Publish, THEN hand the link to the system chooser. A
                            // share that silently does nothing is worse than one that
                            // admits it failed.
                            val url = runCatching {
                                val uid = com.learningischange.tidbitstrivia.net.FirebaseNet.ensureAuth()
                                val stamped = quiz.copy(creatorId = uid)
                                com.learningischange.tidbitstrivia.net.FirebaseNet
                                    .publishQuiz(stamped.id, stamped.toJson())
                                // Persist the stamped owner locally too, or a later
                                // re-share fails the `by === auth.uid` rule.
                                com.learningischange.tidbitstrivia.data.QuizStore.save(stamped)
                                com.learningischange.tidbitstrivia.data.quizShareUrl(stamped.id)
                            }.getOrNull()
                            if (url == null) {
                                error = "Couldn't share that just now. Check your connection and try again."
                            } else {
                                val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                                    type = "text/plain"
                                    putExtra(android.content.Intent.EXTRA_SUBJECT, quiz.title)
                                    putExtra(android.content.Intent.EXTRA_TEXT, "${quiz.title} — a Tidbits quiz\n$url")
                                }
                                ctx.startActivity(android.content.Intent.createChooser(send, "Share quiz"))
                            }
                        }
                    },
                )
            }
        }
    }
}

/** One row on the Create tab's quiz shelf. Delete lives behind an overflow icon so
 *  the row's primary tap target stays "play this". */
@Composable
private fun SavedQuizRow(
    quiz: com.learningischange.tidbitstrivia.data.SavedQuiz,
    onPlay: () -> Unit,
    onDelete: () -> Unit,
    onShare: () -> Unit = {},
) {
    var confirming by remember { mutableStateOf(false) }
    ChunkyCard(onClick = onPlay) {
        Row(
            Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f)) {
                Text(quiz.title, fontWeight = FontWeight.Bold, fontSize = 18.sp, maxLines = 1)
                Text(
                    "${quiz.questionCount} questions",
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    fontSize = 14.sp,
                )
            }
            IconButton(onClick = onShare) {
                Icon(Icons.Filled.Share, contentDescription = "Share quiz")
            }
            IconButton(onClick = { confirming = true }) {
                Icon(Icons.Filled.Delete, contentDescription = "Delete quiz")
            }
            Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = Pops.grape)
        }
    }
    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text("Delete “${quiz.title}”?") },
            text = { Text("This can't be undone.") },
            confirmButton = { TextButton(onClick = { confirming = false; onDelete() }) { Text("Delete") } },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text("Cancel") } },
        )
    }
}

// ---- Reusable chunky card ----

@Composable
internal fun ChunkyCard(modifier: Modifier = Modifier, fill: Color = MaterialTheme.colorScheme.surface, onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    // On TV the focused card is the chrome (see TvFocus.kt); tvFocus is a no-op
    // on phones and tablets, so this one line serves every form factor.
    val base = modifier
        .fillMaxWidth()
        .then(if (onClick != null) Modifier.tvFocus(shape) else Modifier)
        .then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)
    Surface(shape = shape, color = fill, border = BorderStroke(2.5.dp, Ink), modifier = base) { content() }
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
                                    d.myDone && d.oppDone -> Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text(
                                            if (d.myScore > d.oppScore) "Won ${d.myScore}-${d.oppScore}"
                                            else if (d.myScore < d.oppScore) "Lost ${d.myScore}-${d.oppScore}"
                                            else "Tied ${d.myScore}-${d.oppScore}",
                                            fontWeight = FontWeight.Bold, color = if (d.myScore > d.oppScore) Pops.coral else soft)
                                        if (d.oppUid.isNotEmpty()) TextButton(onClick = {
                                            scope.launch {
                                                val qs = buildDuelSet()
                                                if (qs.size >= 3) { com.learningischange.tidbitstrivia.data.Duels.challenge(d.oppUid, d.oppName, qs); inbox = com.learningischange.tidbitstrivia.data.Duels.inbox(); mine = com.learningischange.tidbitstrivia.data.Duels.mine() }
                                            }
                                        }) { Text("Rematch", fontSize = 13.sp, color = MaterialTheme.colorScheme.primary) }
                                    }
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
