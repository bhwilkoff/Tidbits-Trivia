package com.learningischange.tidbitstrivia.ui

import android.content.Context
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.learningischange.tidbitstrivia.data.ScreenshotHooks
import com.learningischange.tidbitstrivia.net.FirebaseNet
import com.learningischange.tidbitstrivia.ui.theme.Pops
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Decision 060 / macOS-DESIGN A8.8: the host's clip, on an Android joiner.
 *
 * An OFFER. Nothing downloads until this player taps or the host presses Play,
 * and nothing plays until the player taps — phones are in pockets and a bar is
 * loud. The host's cue readies the clip so the tap is instant and positions it
 * where the room is. Mirrors Swift `LiveClipView` and the web's `mountMedia`.
 */
object LiveMediaCache {
    private val files = HashMap<String, File>()

    fun extension(mime: String, kind: String) = when (mime.lowercase()) {
        "audio/mpeg", "audio/mp3" -> "mp3"
        "audio/mp4", "audio/x-m4a", "audio/m4a" -> "m4a"
        "audio/aac" -> "aac"
        "audio/wav", "audio/x-wav" -> "wav"
        "video/mp4" -> "mp4"
        "video/quicktime" -> "mov"
        "video/webm" -> "webm"
        else -> if (kind == "video") "mp4" else "m4a"
    }

    /** A Uri a player can open: a cached file for a `room:` node, the link itself otherwise. */
    suspend fun uriFor(context: Context, code: String, media: FirebaseNet.LiveMedia): Uri {
        if (!media.url.startsWith("room:")) return Uri.parse(media.url)
        val id = media.url.removePrefix("room:")
        files[id]?.takeIf { it.exists() }?.let { return Uri.fromFile(it) }
        val (mime, kind, bytes) = withContext(Dispatchers.IO) { FirebaseNet.liveMedia(code, id) }
            ?: throw IllegalStateException("The host's clip isn't in the room yet.")
        val dir = File(context.cacheDir, "LiveRoomMedia").apply { mkdirs() }
        val f = File(dir, "$id.${extension(mime, kind)}")
        withContext(Dispatchers.IO) { f.writeBytes(bytes) }
        files[id] = f
        return Uri.fromFile(f)
    }
}

@Composable
fun LiveClipCard(media: FirebaseNet.LiveMedia, code: String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var player by remember { mutableStateOf<ExoPlayer?>(null) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var playing by remember { mutableStateOf(false) }
    val isVideo = media.kind == "video"

    suspend fun load(thenPlay: Boolean) {
        val existing = player
        if (existing != null) {
            if (thenPlay) { seekToRoom(existing, media); existing.play(); playing = true }
            return
        }
        if (loading) return
        loading = true; error = null
        try {
            val uri = LiveMediaCache.uriFor(context, code, media)
            val p = ExoPlayer.Builder(context).build().apply {
                setMediaItem(MediaItem.fromUri(uri))
                addListener(object : Player.Listener {
                    override fun onIsPlayingChanged(isPlaying: Boolean) { playing = isPlaying }
                    override fun onPlaybackStateChanged(state: Int) { if (state == Player.STATE_ENDED) { seekTo(0); pause(); playing = false } }
                })
                prepare()
            }
            player = p
            seekToRoom(p, media)
            if (thenPlay) { p.play(); playing = true }
        } catch (e: Exception) {
            error = "Clip unavailable — the room hears it from the host. (${e.message})"
        } finally { loading = false }
    }

    // The host's cue: fetch now so the tap is instant. Never plays on its own.
    LaunchedEffect(media.startedAt) { if (media.startedAt != null && player == null) load(thenPlay = false) }
    // Harness hook: take up the offer without a finger on the glass. No-op in production.
    LaunchedEffect(Unit) { if (ScreenshotHooks.liveTapClip) { delay(2000); load(thenPlay = true) } }
    DisposableEffect(Unit) { onDispose { player?.release(); player = null } }

    val p = player
    when {
        p != null && isVideo -> AndroidView(
            factory = { ctx -> PlayerView(ctx).apply { this.player = p; useController = true } },
            update = { it.player = p },
            modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(14.dp)),
        )
        p != null -> Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant).padding(horizontal = 12.dp, vertical = 8.dp),
        ) {
            IconButton(onClick = { if (playing) { p.pause(); playing = false } else { p.play(); playing = true } }) {
                Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, contentDescription = if (playing) "Pause" else "Play",
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(34.dp))
            }
            Spacer(Modifier.width(10.dp))
            Column {
                Text(media.name ?: "Audio clip", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                Text(if (playing) "Playing" else "Ready", fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
            }
        }
        else -> Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                .background(Pops.blue).clickable(enabled = !loading) { scope.launch { load(thenPlay = true) } }
                .padding(horizontal = 16.dp, vertical = 12.dp),
        ) {
            Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = Color.White, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(12.dp))
            Column {
                Text(if (loading) "Loading the clip" else if (isVideo) "Watch the clip" else "Listen to the clip",
                    color = Color.White, fontWeight = FontWeight.Black, fontSize = 16.sp)
                val size = media.bytes?.let { if (it >= 1_000_000) " · %.1f MB".format(it / 1e6) else " · ${maxOf(1, it / 1000)} KB" } ?: ""
                Text(if (media.startedAt != null) "Playing in the room now — tap to hear it here" else (media.name ?: if (isVideo) "Video" else "Audio") + size,
                    color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
            }
        }
    }
    error?.let { Text(it, color = Pops.coral, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp)) }
}

/** Where the room is in the clip, if the host has started it. */
private fun seekToRoom(p: ExoPlayer, media: FirebaseNet.LiveMedia) {
    val started = media.startedAt ?: return
    val offset = System.currentTimeMillis() - started
    val dur = p.duration
    if (offset > 1000 && dur > 0 && offset < dur - 500) p.seekTo(offset)
}
