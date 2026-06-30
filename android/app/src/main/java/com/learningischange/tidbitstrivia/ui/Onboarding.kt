package com.learningischange.tidbitstrivia.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.learningischange.tidbitstrivia.ui.theme.Ink
import com.learningischange.tidbitstrivia.ui.theme.Pops
import kotlinx.coroutines.launch

// First-run walkthrough (parity with iOS OnboardingView): three cards —
// play / learn / together. Shown once over Home; `onDone` flips hasOnboarded.
private data class Slide(val emoji: String, val tint: Color, val title: String, val body: String)

private val SLIDES = listOf(
    Slide("🧠", Pops.coral, "All of Wikipedia, as trivia",
        "Thousands of real, sourced questions — built and fact-checked from Wikipedia. They never repeat until you've seen them all."),
    Slide("💡", Pops.yellow, "Learn something every round",
        "Every question ends on the fact, with a link to read more. Miss one and it quietly comes back later, so the game teaches as it tests."),
    Slide("🎉", Pops.blue, "Solo or together",
        "Play your way — keep a daily streak, dig into 16 modes, or host a Trivia Night and pass the phone around the room."),
)

@Composable
fun OnboardingScreen(onDone: () -> Unit) {
    val pager = rememberPagerState(pageCount = { SLIDES.size })
    val scope = rememberCoroutineScope()
    val last = pager.currentPage == SLIDES.lastIndex

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxSize().padding(24.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDone) { Text("Skip") }
            }
            HorizontalPager(state = pager, modifier = Modifier.weight(1f)) { page ->
                val s = SLIDES[page]
                Column(
                    Modifier.fillMaxSize().padding(horizontal = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Box(
                        Modifier.size(132.dp).background(s.tint, CircleShape).border(BorderStroke(3.dp, Ink), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) { Text(s.emoji, fontSize = 64.sp) }
                    Spacer(Modifier.height(32.dp))
                    Text(s.title, fontWeight = FontWeight.Black, fontSize = 28.sp, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(14.dp))
                    Text(s.body, textAlign = TextAlign.Center, fontSize = 16.sp,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
                }
            }
            Row(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalArrangement = Arrangement.Center) {
                repeat(SLIDES.size) { i ->
                    Box(Modifier.padding(4.dp).size(if (i == pager.currentPage) 11.dp else 8.dp)
                        .background(if (i == pager.currentPage) Ink else Ink.copy(alpha = 0.25f), CircleShape))
                }
            }
            Button(
                onClick = { if (last) onDone() else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) } },
                modifier = Modifier.fillMaxWidth().height(54.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Ink, contentColor = Color.White),
            ) { Text(if (last) "Start Playing" else "Next", fontWeight = FontWeight.Bold, fontSize = 17.sp) }
        }
    }
}
