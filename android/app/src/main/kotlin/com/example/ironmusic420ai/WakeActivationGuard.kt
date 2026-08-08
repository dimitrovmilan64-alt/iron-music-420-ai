package com.example.ironmusic420ai

internal class WakeActivationGuard(
    private val requiredVoicedFrames: Int,
    private val signalHoldMillis: Long,
    private val cooldownMillis: Long,
) {
    enum class Decision {
        ACCEPT,
        LOW_SIGNAL,
        COOLDOWN,
    }

    private var consecutiveVoicedFrames = 0
    private var signalValidUntilMillis: Long? = null
    private var lastAcceptedAtMillis: Long? = null

    val voicedFrames: Int
        get() = consecutiveVoicedFrames

    fun resetSignal() {
        consecutiveVoicedFrames = 0
        signalValidUntilMillis = null
    }

    fun observeFrame(voiced: Boolean, nowMillis: Long) {
        consecutiveVoicedFrames = if (voiced) {
            (consecutiveVoicedFrames + 1).coerceAtMost(requiredVoicedFrames + 2)
        } else {
            0
        }

        if (consecutiveVoicedFrames >= requiredVoicedFrames) {
            signalValidUntilMillis = nowMillis + signalHoldMillis
        }
    }

    fun evaluate(nowMillis: Long): Decision {
        val signalValidUntil = signalValidUntilMillis
        if (signalValidUntil == null || nowMillis > signalValidUntil) {
            return Decision.LOW_SIGNAL
        }

        val lastAccepted = lastAcceptedAtMillis
        if (lastAccepted != null && nowMillis - lastAccepted < cooldownMillis) {
            resetSignal()
            return Decision.COOLDOWN
        }

        lastAcceptedAtMillis = nowMillis
        resetSignal()
        return Decision.ACCEPT
    }
}
