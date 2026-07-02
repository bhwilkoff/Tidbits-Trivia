package com.learningischange.tidbitstrivia.data

import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Play vs CPU — the online-multiplayer v0 (Decision 038,
 * docs/ONLINE-MULTIPLAYER-PLAYBOOK.md §5). Mirror of BotOpponent.swift and
 * js/bots.js — keep the three in lockstep.
 *
 * HONESTY RULE (learning-orientation, non-negotiable): a bot is always
 * visibly labeled CPU. Never present a bot as a human.
 */
data class BotProfile(
    val id: String,
    val name: String,
    val baseSkill: Double,
    val categorySkill: Map<String, Double>,
    val speedMean: Double,
    val speedSigma: Double,
)

data class BotAnswer(val botId: String, val choiceIndex: Int?, val seconds: Double?) {
    val answered: Boolean get() = choiceIndex != null
}

object Bots {
    val rookie = BotProfile("rookie", "Rookie Rae", 0.55,
        mapOf("sports" to 0.15, "film" to 0.10, "science" to -0.12), 6.5, 0.45)
    val regular = BotProfile("regular", "Trivia Tina", 0.70,
        mapOf("history" to 0.10, "arts" to 0.08, "sports" to -0.10), 5.5, 0.40)
    val ace = BotProfile("ace", "Ace Botsworth", 0.85,
        mapOf("science" to 0.10, "geography" to 0.08, "music" to -0.08), 4.0, 0.35)

    /** Adapts to the player's recent accuracy so solo-vs-CPU stays a fair fight. */
    fun house(playerAccuracy: Double) = BotProfile(
        "house", "The House", playerAccuracy.coerceIn(0.35, 0.90), emptyMap(), 5.0, 0.40)

    fun byId(id: String, playerAccuracy: Double): BotProfile = when (id) {
        "rookie" -> rookie; "regular" -> regular; "ace" -> ace
        else -> house(playerAccuracy)
    }

    fun difficultyAdj(difficulty: Int): Double =
        if (difficulty <= 2) 0.15 else if (difficulty >= 4) -0.20 else 0.0

    /** Resolve what this bot does with this question, inside `window` seconds. */
    fun resolve(bot: BotProfile, categoryId: String, difficulty: Int,
                correctIndex: Int, optionCount: Int, window: Double): BotAnswer {
        val p = (bot.baseSkill + (bot.categorySkill[categoryId] ?: 0.0) + difficultyAdj(difficulty))
            .coerceIn(0.02, 0.98)
        if (Random.nextDouble() < 0.05) return BotAnswer(bot.id, null, null)  // freeze
        val correct = Random.nextDouble() < p
        var t = exp(ln(bot.speedMean) + gaussian() * bot.speedSigma)
        if (correct) t *= 0.85   // knowing feels fast
        t = t.coerceIn(0.8, maxOf(1.0, window - 0.5))
        val choice = if (correct) correctIndex
        else (0 until maxOf(optionCount, 2)).filter { it != correctIndex }.random()
        return BotAnswer(bot.id, choice, t)
    }

    private fun gaussian(): Double {   // Box–Muller
        val u1 = Random.nextDouble(Double.MIN_VALUE, 1.0)
        val u2 = Random.nextDouble()
        return sqrt(-2 * ln(u1)) * cos(2 * Math.PI * u2)
    }
}
