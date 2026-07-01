package com.learningischange.tidbitstrivia.net

import com.learningischange.tidbitstrivia.data.Corpus
import com.learningischange.tidbitstrivia.data.Question
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Trivia Night — the TRANSPORT-AGNOSTIC wire core (see docs/CROSS-PLATFORM-MULTIPLAYER.md).
 * Mirrors the Apple `Night`/`NightMessage` contract (Decision 033) so the same
 * host-paced, everyone-plays state machine runs over ANY link — mDNS+TCP today,
 * Wi-Fi Aware or BLE later, GitHub for remote. This file is pure value logic
 * (no sockets, no NSD): messages, room-code → AES key, length+GCM framing.
 *
 * Cross-platform note: the `.night` message ships the plan + a list of question
 * IDS, not full question objects — both apps bundle the same corpus, so each
 * device resolves ids against its own `Corpus`. That shrinks the payload ~100x
 * and removes the need to canonicalize the whole Question across platforms.
 */
object Night {
    const val serviceType = "_tidbits-night._tcp"   // same DNS-SD type Apple advertises
    const val headerBytes = 4
    const val maxMessageBytes = 1 shl 20

    val json = Json { ignoreUnknownKeys = true; encodeDefaults = false }
}

@Serializable
enum class NightKind {
    // joiner -> host
    join, answered, leave,
    // host -> joiner
    welcome, roster, night, begin, reveal, finished,
    unknown,
}

@Serializable
data class NightPlayer(
    val seat: Int,
    val name: String,
    val score: Int = 0,
    val answered: Boolean = false,
    val isHost: Boolean = false,
)

/** One themed round: a question TYPE (GameMode raw value, e.g. "classic") + count. */
@Serializable
data class NightRound(val kind: String, val count: Int)

@Serializable
data class NightPlan(val rounds: List<NightRound>, val teams: List<String> = emptyList()) {
    val totalQuestions: Int get() = rounds.sumOf { it.count }
}

/**
 * Full-question fallback (only sent for ids a peer is missing — corpus drift).
 * The primary path is ids; this canonical shape lets a peer render a question it
 * doesn't have locally without re-canonicalizing every field on the hot path.
 */
@Serializable
data class WireClosest(val answer: Double, val min: Double, val max: Double, val step: Double, val tolerance: Double, val unit: String)
@Serializable
data class WireMatch(val keys: List<String>, val values: List<String>)
@Serializable
data class WireEnum(val groups: List<List<String>>)

@Serializable
data class WireQuestion(
    val id: String,
    val prompt: String,
    val options: List<String> = emptyList(),
    val correctIndex: Int = 0,
    val categoryId: String = "mixed",
    val difficulty: Int = 3,
    val explanation: String = "",
    val sourceTitle: String = "",
    val sourceUrl: String = "",
    val imageUrl: String? = null,
    val closest: WireClosest? = null,
    val ordering: List<String>? = null,
    val matching: WireMatch? = null,
    val accepted: List<String>? = null,
    val enumerate: WireEnum? = null,
    val roundIndex: Int? = null,
)

/** One frame on the wire. `kind` is self-describing; unknown kinds decode to `unknown`. */
@Serializable
data class NightMessage(
    val kind: NightKind,
    val displayName: String? = null,
    val deviceID: String? = null,
    val seat: Int? = null,
    val roomName: String? = null,
    val players: List<NightPlayer>? = null,
    val questionIndex: Int? = null,
    val plan: NightPlan? = null,
    /** The night content, id-based (resolved via Corpus on each device). */
    val questionIds: List<String>? = null,
    /** Full-object fallback for ids a peer lacks locally (usually null). */
    val questions: List<WireQuestion>? = null,
    /** On `.answered`: the joiner's running TOTAL and whether THIS question was right. */
    val score: Int? = null,
    val correct: Boolean? = null,
)

// ---- Question <-> WireQuestion ----

fun Question.toWire(): WireQuestion = WireQuestion(
    id = id, prompt = prompt, options = options, correctIndex = correctIndex,
    categoryId = categoryId, difficulty = difficulty, explanation = explanation,
    sourceTitle = sourceTitle, sourceUrl = sourceUrl, imageUrl = imageUrl,
    closest = closest?.let { WireClosest(it.answer, it.min, it.max, it.step, it.tolerance, it.unit) },
    ordering = ordering,
    matching = matching?.let { WireMatch(it.keys, it.values) },
    accepted = accepted,
    enumerate = enumerate?.let { WireEnum(it.groups) },
    roundIndex = roundIndex,
)

fun WireQuestion.toQuestion(): Question = Question(
    id = id, prompt = prompt, options = options, correctIndex = correctIndex,
    categoryId = categoryId, difficulty = difficulty, explanation = explanation,
    sourceTitle = sourceTitle, sourceUrl = sourceUrl, imageUrl = imageUrl,
    closest = closest?.let { com.learningischange.tidbitstrivia.data.ClosestSpec(it.answer, it.min, it.max, it.step, it.tolerance, it.unit) },
    ordering = ordering,
    matching = matching?.let { com.learningischange.tidbitstrivia.data.MatchSpec(it.keys, it.values) },
    accepted = accepted,
    enumerate = enumerate?.let { com.learningischange.tidbitstrivia.data.EnumSpec(it.groups) },
    roundIndex = roundIndex,
)

/** Resolve an id-based night to local Questions; falls back to any WireQuestions sent. */
fun NightMessage.resolveQuestions(): List<Question> {
    val fallback = questions?.associate { it.id to it.toQuestion() } ?: emptyMap()
    return (questionIds ?: emptyList()).mapNotNull { id -> Corpus.byId(id) ?: fallback[id] }
}

// ---- Room code -> AES key (same derivation Apple uses for its PSK) ----

object RoomCode {
    // Excludes ambiguous glyphs (0/O, 1/I) so a code read across the room is unambiguous.
    private const val alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    const val length = 4

    fun generate(): String {
        val rng = SecureRandom()
        return (0 until length).map { alphabet[rng.nextInt(alphabet.length)] }.joinToString("")
    }

    /** AES-256 key = SHA256("tidbits-night-v1:<CODE>") — byte-identical to Apple's PSK. */
    fun key(code: String): ByteArray =
        MessageDigest.getInstance("SHA-256").digest("tidbits-night-v1:${code.uppercase()}".toByteArray())
}

// ---- Framing + AES-GCM (app-layer confidentiality/auth, since we drop TLS) ----

/**
 * Encode: `4-byte big-endian length + AES-256-GCM(nonce||ciphertext||tag)`.
 * The room-code key both sides derive gates pairing — a wrong code fails the GCM
 * tag, so the frame is rejected (the "only a device that can read the code pairs"
 * guarantee, achieved with native crypto instead of TLS-PSK).
 */
object NightWire {
    private const val NONCE = 12
    private const val TAG_BITS = 128

    fun encode(message: NightMessage, key: ByteArray): ByteArray? {
        val plain = Night.json.encodeToString(message).toByteArray()
        val nonce = ByteArray(NONCE).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
        val sealed = cipher.doFinal(plain)               // ciphertext || 16-byte tag
        val body = nonce + sealed
        if (body.size > Night.maxMessageBytes) return null
        val len = body.size
        return byteArrayOf(
            (len ushr 24).toByte(), (len ushr 16).toByte(), (len ushr 8).toByte(), len.toByte(),
        ) + body
    }
}

/** Reassembles length-prefixed frames from a byte stream and opens each with the key. */
class NightFramer(private val key: ByteArray) {
    private var buffer = ByteArray(0)

    fun ingest(data: ByteArray): List<NightMessage> {
        buffer += data
        val out = mutableListOf<NightMessage>()
        while (buffer.size >= Night.headerBytes) {
            val len = ((buffer[0].toInt() and 0xFF) shl 24) or ((buffer[1].toInt() and 0xFF) shl 16) or
                ((buffer[2].toInt() and 0xFF) shl 8) or (buffer[3].toInt() and 0xFF)
            if (len < 0 || len > Night.maxMessageBytes) { buffer = ByteArray(0); break }  // corrupt — resync
            val total = Night.headerBytes + len
            if (buffer.size < total) break
            val body = buffer.copyOfRange(Night.headerBytes, total)
            buffer = buffer.copyOfRange(total, buffer.size)
            open(body)?.let { out.add(it) }
        }
        return out
    }

    private fun open(body: ByteArray): NightMessage? = try {
        val nonce = body.copyOfRange(0, 12)
        val sealed = body.copyOfRange(12, body.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        Night.json.decodeFromString<NightMessage>(String(cipher.doFinal(sealed)))
    } catch (e: Exception) {
        null   // wrong key (tag fails) or malformed — drop the frame
    }
}
