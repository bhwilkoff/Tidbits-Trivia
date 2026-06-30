package com.learningischange.tidbitstrivia.ui

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.data.Store
import com.learningischange.tidbitstrivia.ui.theme.Ink
import com.learningischange.tidbitstrivia.ui.theme.Pops

// Full Settings (parity with iOS SettingsView): feedback / gameplay /
// appearance / data / about. Reached from the Home gear.
@Composable
fun SettingsScreen(store: Store, dynamicColor: Boolean, onDynamicColor: (Boolean) -> Unit) {
    val context = LocalContext.current
    var haptics by remember { mutableStateOf(store.hapticsEnabled()) }
    var review by remember { mutableStateOf(store.reviewEnabled()) }
    var dyn by remember { mutableStateOf(dynamicColor) }
    var confirmReset by remember { mutableStateOf(false) }
    var resetSeenDone by remember { mutableStateOf(false) }
    val version = remember {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: "—"
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Settings", fontSize = 30.sp, fontWeight = FontWeight.Black)

        Section("Feedback")
        ToggleRow("Haptics", "Buzz on correct and wrong answers.", haptics) { haptics = it; store.setHapticsEnabled(it) }

        Section("Gameplay")
        ToggleRow("Review questions", "Re-ask questions you've missed, spaced out, so they stick. Off = only new questions.", review) { review = it; store.setReviewEnabled(it) }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Section("Appearance")
            ToggleRow("Use system colors", "Tint the app with your wallpaper palette (Material You).", dyn) { dyn = it; onDynamicColor(it) }
        }

        Section("Data")
        ActionRow("Reset Seen Questions", if (resetSeenDone) "Done — every question is back in rotation." else "Re-open the whole question bank from the start.") {
            store.resetSeen(); resetSeenDone = true
        }
        ActionRow("Reset All Records", "Erase every score, streak, and stat. Can't be undone.", destructive = true) { confirmReset = true }

        Section("About")
        SettingsCard {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Version", fontWeight = FontWeight.Bold); Text(version, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                }
                Text("Questions from Wikipedia", color = Pops.blue, fontWeight = FontWeight.Bold,
                    modifier = Modifier.clickable {
                        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.wikipedia.org"))) }
                    })
                Text("Content from Wikipedia, available under CC BY-SA. Tidbits is a learning game — every question is a door to learn more.",
                    fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
        Spacer(Modifier.height(24.dp))
    }

    if (confirmReset) {
        AlertDialog(
            onDismissRequest = { confirmReset = false },
            title = { Text("Reset all records?") },
            text = { Text("This erases every score, streak, calibration, and stat. It can't be undone.") },
            confirmButton = { TextButton(onClick = { store.resetAllRecords(); confirmReset = false }) { Text("Reset", color = Pops.coral) } },
            dismissButton = { TextButton(onClick = { confirmReset = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun Section(title: String) =
    Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 6.dp))

@Composable
private fun ToggleRow(title: String, blurb: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    SettingsCard {
        Row(Modifier.padding(16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f)) {
                Text(title, fontWeight = FontWeight.Bold)
                Text(blurb, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), fontSize = 13.sp)
            }
            Switch(checked = checked, onCheckedChange = onChange)
        }
    }
}

@Composable
private fun ActionRow(title: String, blurb: String, destructive: Boolean = false, onClick: () -> Unit) {
    SettingsCard(onClick = onClick) {
        Row(Modifier.padding(16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title, fontWeight = FontWeight.Bold, color = if (destructive) Pops.coral else MaterialTheme.colorScheme.onSurface)
                Text(blurb, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), fontSize = 13.sp)
            }
        }
    }
}

@Composable
private fun SettingsCard(onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val m = Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)
    Surface(shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.surface, border = BorderStroke(2.5.dp, Ink), modifier = m) { content() }
}
