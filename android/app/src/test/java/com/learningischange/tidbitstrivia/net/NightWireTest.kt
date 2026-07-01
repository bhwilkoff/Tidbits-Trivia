package com.learningischange.tidbitstrivia.net

import kotlinx.serialization.encodeToString
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Cross-platform wire compatibility: Apple's NightPlayer/NightPlan use strict
 * synthesized Codable and THROW on missing keys, so Android must emit the
 * default-valued fields too (encodeDefaults=true). These assert the bytes an
 * iPhone joiner decodes actually contain them.
 */
class NightWireTest {
    @Test fun rosterEmitsDefaultPlayerFields() {
        val msg = NightMessage(NightKind.roster, players = listOf(NightPlayer(seat = 0, name = "Host", isHost = true)))
        val json = Night.json.encodeToString(msg)
        assertTrue("score must be emitted: $json", json.contains("\"score\""))
        assertTrue("answered must be emitted: $json", json.contains("\"answered\""))
        assertTrue("isHost must be emitted: $json", json.contains("\"isHost\""))
    }

    @Test fun nightPlanEmitsTeams() {
        val plan = NightPlan(rounds = listOf(NightRound("classic", 5)))
        val msg = NightMessage(NightKind.night, plan = plan, questionIds = listOf("a"))
        val json = Night.json.encodeToString(msg)
        assertTrue("teams must be emitted: $json", json.contains("\"teams\""))
    }
}
