package com.example.ironmusic420ai

import org.junit.Assert.assertEquals
import org.junit.Test

class WakeActivationGuardTest {
    @Test
    fun trailingSilenceDoesNotEraseAConfirmedWakePhrase() {
        val guard = WakeActivationGuard(
            requiredVoicedFrames = 2,
            signalHoldMillis = 1_500,
            cooldownMillis = 4_000,
        )

        guard.observeFrame(voiced = true, nowMillis = 100)
        guard.observeFrame(voiced = true, nowMillis = 200)
        guard.observeFrame(voiced = false, nowMillis = 300)
        guard.observeFrame(voiced = false, nowMillis = 400)

        assertEquals(WakeActivationGuard.Decision.ACCEPT, guard.evaluate(500))
    }

    @Test
    fun oldVoiceCannotValidateALaterNoiseTrigger() {
        val guard = WakeActivationGuard(
            requiredVoicedFrames = 2,
            signalHoldMillis = 1_500,
            cooldownMillis = 4_000,
        )

        guard.observeFrame(voiced = true, nowMillis = 100)
        guard.observeFrame(voiced = true, nowMillis = 200)
        guard.observeFrame(voiced = false, nowMillis = 300)

        assertEquals(WakeActivationGuard.Decision.LOW_SIGNAL, guard.evaluate(1_701))
    }

    @Test
    fun acceptedWakePhraseCannotImmediatelyRetrigger() {
        val guard = WakeActivationGuard(
            requiredVoicedFrames = 2,
            signalHoldMillis = 1_500,
            cooldownMillis = 4_000,
        )

        guard.observeFrame(voiced = true, nowMillis = 19_800)
        guard.observeFrame(voiced = true, nowMillis = 19_900)
        assertEquals(WakeActivationGuard.Decision.ACCEPT, guard.evaluate(20_000))

        guard.observeFrame(voiced = true, nowMillis = 22_300)
        guard.observeFrame(voiced = true, nowMillis = 22_400)
        assertEquals(WakeActivationGuard.Decision.COOLDOWN, guard.evaluate(22_500))

        guard.observeFrame(voiced = true, nowMillis = 23_900)
        guard.observeFrame(voiced = true, nowMillis = 24_000)
        assertEquals(WakeActivationGuard.Decision.ACCEPT, guard.evaluate(24_100))
    }
}
