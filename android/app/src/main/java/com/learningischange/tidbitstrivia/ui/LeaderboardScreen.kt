package com.learningischange.tidbitstrivia.ui

// Wave E: the cross-venue / season leaderboard — reads the static JSON the hourly cron commits
// to tidbitstrivia.com/data/leaderboard (free/cacheable), never RTDB.

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

private const val LB_BASE = "https://tidbitstrivia.com/data/leaderboard"

private data class LbRow(val name: String, val score: Int)

private suspend fun fetchText(url: String): String? =
    withContext(Dispatchers.IO) { runCatching { java.net.URL(url).readText() }.getOrNull() }

private fun parseRows(s: String?): List<LbRow> {
    val arr = runCatching { JSONArray(s ?: "[]") }.getOrNull() ?: return emptyList()
    return (0 until arr.length()).map { val o = arr.getJSONObject(it); LbRow(o.optString("name", "Player"), o.optInt("score")) }
}

@Composable
fun LeaderboardScreen(onBack: () -> Unit) {
    var overall by remember { mutableStateOf<List<LbRow>>(emptyList()) }
    var venues by remember { mutableStateOf<List<Pair<String, List<LbRow>>>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    val ink = MaterialTheme.colorScheme.onSurface
    val soft = ink.copy(alpha = 0.6f)

    LaunchedEffect(Unit) {
        val idx = runCatching { JSONObject(fetchText("$LB_BASE/index.json") ?: "{}") }.getOrNull() ?: JSONObject()
        val season = idx.keys().asSequence().toList().sorted().lastOrNull()
        if (season != null) {
            overall = parseRows(fetchText("$LB_BASE/$season/_overall.json"))
            val arr = idx.optJSONArray(season)
            val vs = mutableListOf<Pair<String, List<LbRow>>>()
            if (arr != null) for (i in 0 until arr.length()) {
                val venue = arr.getString(i)
                val rows = parseRows(fetchText("$LB_BASE/$season/$venue.json"))
                if (rows.isNotEmpty()) vs.add(venue to rows)
            }
            venues = vs
        }
        loading = false
    }

    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
            Text("Leaderboard", fontSize = 28.sp, fontWeight = FontWeight.Black, color = ink)
        }
        when {
            loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            overall.isEmpty() && venues.isEmpty() ->
                Text("No standings yet. Play a live Tidbits night while signed in and you'll climb the board here — it refreshes hourly.",
                    color = soft, modifier = Modifier.padding(top = 24.dp))
            else -> LazyColumn(Modifier.fillMaxSize()) {
                if (overall.isNotEmpty()) {
                    item { SectionHeader("This season · Overall", ink) }
                    itemsIndexed(overall) { i, r -> LbRowView(i, r, ink, soft) }
                }
                venues.forEach { (venue, rows) ->
                    item { SectionHeader(venue, ink) }
                    itemsIndexed(rows) { i, r -> LbRowView(i, r, ink, soft) }
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(text: String, ink: Color) {
    Text(text, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = ink,
        modifier = Modifier.padding(top = 18.dp, bottom = 6.dp))
}

@Composable
private fun LbRowView(i: Int, r: LbRow, ink: Color, soft: Color) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("${i + 1}", fontWeight = FontWeight.Black, color = if (i == 0) ink else soft, modifier = Modifier.width(30.dp))
        Text(r.name, fontWeight = FontWeight.SemiBold, color = ink, modifier = Modifier.weight(1f))
        Text("${r.score}", fontWeight = FontWeight.Black, color = ink)
    }
}
