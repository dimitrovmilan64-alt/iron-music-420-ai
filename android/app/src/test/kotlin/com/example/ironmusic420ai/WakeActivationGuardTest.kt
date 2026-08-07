package com.example.ironmusic420ai

import org.junit.Assert.assertEquals
import org.junit.Test

class WakeActivationGuardTest {
    @Test
    fun noiseGapResetsTheRequiredConsecutiveVoiceFrames() {
        val guard = WakeActivationGuard(requiredVoicedFrames = 3, cooldownMillis = 4_000)

        guard.observeFrame(true)
        guard.observeFrame(true)
        guard.observeFrame(false)
        guard.observeFrame(true)

        assertEquals(WakeActivationGuard.Decision.LOW_SIGNAL, guard.evaluate(10_000))

        guard.observeFrame(true)
        guard.observeFrame(true)
        assertEquals(WakeActivationGuard.Decision.ACCEPT, guard.evaluate(10_100))
    }

    @Test
    fun acceptedWakePhraseCannotImmediatelyRetrigger() {
        val guard = WakeActivationGuard(requiredVoicedFrames = 2, cooldownMillis = 4_000)

        guard.observeFrame(true)
        guard.observeFrame(true)
        assertEquals(WakeActivationGuard.Decision.ACCEPT, guard.evaluate(20_000))

        guard.resetSignal()
        guard.observeFrame(true)
        guard.observeFrame(true)
        assertEquals(WakeActivationGuard.Decision.COOLDOWN, guard.evaluate(22_500))
        assertEquals(WakeActivationGuard.Decision.ACCEPT, guard.evaluate(24_100))
    }
}
