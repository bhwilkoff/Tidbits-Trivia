package com.learningischange.tidbitstrivia.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.learningischange.tidbitstrivia.data.PlayerIdentity
import com.learningischange.tidbitstrivia.data.Store
import com.learningischange.tidbitstrivia.ui.theme.Pops
import kotlinx.coroutines.launch

/**
 * In-app account deletion (Play's user-data policy; the twin of the iOS/macOS/tvOS
 * requirement that came out of an App Store 5.1.1(v) rejection). Shown whether or not the
 * player ever signed in, because Tidbits provisions a real anonymous account for everyone
 * and that account holds their rating, streak and board rows.
 *
 * One dialog shared by Settings and Profile so the wording and the failure path cannot
 * drift apart. The failure path matters: a delete that quietly does nothing is exactly
 * what review rejects, so an error is shown in place of the success message.
 */
@Composable
fun DeleteAccountConfirm(store: Store, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    var working by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf<String?>(null) }
    var done by remember { mutableStateOf(false) }

    if (done || failed != null) {
        AlertDialog(
            onDismissRequest = onDone,
            title = { Text(if (done) "Account deleted" else "Couldn't delete") },
            text = {
                Text(failed ?: "You're playing as a new anonymous player. Your profile, records and board entries are gone.")
            },
            confirmButton = { TextButton(onClick = onDone) { Text("OK") } },
        )
        return
    }

    AlertDialog(
        onDismissRequest = { if (!working) onDone() },
        title = { Text("Delete your account?") },
        text = {
            Text("Your profile, rating, streak, saved records and leaderboard entries are " +
                 "permanently removed. This can't be undone.")
        },
        confirmButton = {
            if (working) CircularProgressIndicator(Modifier.size(24.dp))
            else TextButton(onClick = {
                working = true
                scope.launch {
                    val ok = PlayerIdentity.deleteAccount(store)
                    working = false
                    if (ok) done = true else failed = PlayerIdentity.deleteError ?: "Please try again."
                }
            }) { Text("Delete", color = Pops.coral) }
        },
        dismissButton = { if (!working) TextButton(onClick = onDone) { Text("Cancel") } },
    )
}
