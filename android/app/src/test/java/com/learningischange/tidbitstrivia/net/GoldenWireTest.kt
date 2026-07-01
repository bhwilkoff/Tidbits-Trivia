package com.learningischange.tidbitstrivia.net

import kotlinx.serialization.decodeFromString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Trivia Night wire golden test — Android side (docs/NIGHT-WIRE-SCHEMA.md).
 * The canonical fixtures live in tools/night-wire/golden (single source, shared
 * with the Apple harness). This test:
 *   1. decodes every golden message fixture and asserts the canonical facts;
 *   2. decodes the AES-GCM frames the Apple harness wrote (apple-*.hex) —
 *      proving Swift-encoded frames open on Kotlin;
 *   3. writes android-*.hex frames for the Apple harness to cross-decode.
 * Run the full loop with tools/night-wire/run_golden.sh.
 */
class GoldenWireTest {

    private val golden: File by lazy {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, "tools/night-wire/golden").isDirectory) dir = dir.parentFile
        requireNotNull(dir?.let { File(it, "tools/night-wire/golden") }) {
            "tools/night-wire/golden not found above ${File("").absolutePath}"
        }
    }
    private val key = RoomCode.key("GOLD")

    private fun fixture(name: String): NightMessage =
        Night.json.decodeFromString(File(golden, "messages/$name.json").readText())

    private fun assertFacts(m: NightMessage, name: String) {
        when (name) {
            "roster" -> {
                assertEquals(NightKind.roster, m.kind)
                assertEquals(2, m.players?.size)
                val host = m.players!![0]
                assertTrue(host.isHost); assertEquals(3, host.score); assertTrue(host.answered)
                assertEquals("Ana", m.players!![1].name); assertEquals(0, m.players!![1].score)
            }
            "night" -> {
                assertEquals(NightKind.night, m.kind)
                assertEquals(2, m.plan?.rounds?.size)
                assertEquals("classic", m.plan!!.rounds[0].kind); assertEquals(2, m.plan!!.rounds[0].count)
                assertEquals("closestCall", m.plan!!.rounds[1].kind); assertEquals(1, m.plan!!.rounds[1].count)
                assertTrue(m.plan!!.teams.isEmpty())
                assertEquals(3, m.questionIds?.size)
                assertEquals(2, m.questions?.size)   // q-gamma is id-only
                assertEquals(2, m.questions!![0].correctIndex)
                assertEquals(4, m.questions!![0].options.size)
                assertEquals("https://upload.wikimedia.org/einstein.jpg", m.questions!![0].imageUrl)
                assertEquals(6371.0, m.questions!![1].closest?.answer)
                assertEquals("km", m.questions!![1].closest?.unit)
                assertEquals(1500.0, m.questions!![1].toQuestion().closest?.tolerance)
            }
            "welcome" -> {
                assertEquals(NightKind.welcome, m.kind)
                assertEquals(1, m.seat); assertEquals("Tidbits GOLD", m.roomName)
            }
            "answered" -> {
                assertEquals(NightKind.answered, m.kind)
                assertEquals(5, m.score); assertEquals(true, m.correct)
            }
            else -> throw AssertionError("unexpected fixture $name — add its facts here")
        }
    }

    @Test fun goldenMessagesDecode() {
        for (name in listOf("roster", "night", "welcome", "answered")) assertFacts(fixture(name), name)
    }

    @Test fun futureKindIsDroppedNotCrashed() {
        // Known cross-platform delta (NIGHT-WIRE-SCHEMA.md): Apple decodes an
        // unknown kind to .unknown; Kotlin's enum decode throws, so NightFramer
        // drops the WHOLE frame. Both ignore the message — new kinds must never
        // require acknowledgment. This pins the Kotlin half of that contract.
        val raw = File(golden, "messages/future-kind.json").readText()
        val decoded = runCatching { Night.json.decodeFromString<NightMessage>(raw) }
        assertTrue("unknown kind should fail Kotlin decode (frame drop)", decoded.isFailure)
    }

    @Test fun appleFramesOpen() {
        val frames = File(golden, "frames").listFiles { f -> f.name.startsWith("apple-") && f.extension == "hex" }
        assertNotNull("run tools/night-wire/run_golden.sh (apple pass 1 writes these)", frames)
        assertTrue("no apple frames found — run the apple harness first", frames!!.isNotEmpty())
        for (f in frames.sortedBy { it.name }) {
            val name = f.nameWithoutExtension.removePrefix("apple-")
            val bytes = f.readText().trim().chunked(2).map { it.toInt(16).toByte() }.toByteArray()
            val msgs = NightFramer(key).ingest(bytes)
            assertEquals("apple frame $name must open as exactly one message", 1, msgs.size)
            assertFacts(msgs[0], name)
        }
    }

    @Test fun writeAndroidFramesAndRoundTrip() {
        for (name in listOf("roster", "night", "welcome", "answered")) {
            val m = fixture(name)
            val frame = NightWire.encode(m, key) ?: throw AssertionError("encode $name returned null")
            val back = NightFramer(key).ingest(frame)
            assertEquals("$name must round-trip through NightFramer", 1, back.size)
            assertFacts(back[0], name)
            File(golden, "frames/android-$name.hex").writeText(frame.joinToString("") { "%02x".format(it) })
        }
    }
}
