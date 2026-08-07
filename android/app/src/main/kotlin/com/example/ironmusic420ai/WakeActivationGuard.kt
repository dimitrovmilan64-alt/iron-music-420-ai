package com.example.ironmusic420ai

internal class WakeActivationGuard(
    private val requiredVoicedFrames: Int,
    private val cooldownMillis: Long,
) {
    enum class Decision {
        ACCEPT,
        LOW_SIGNAL,
        COOLDOWN,
    }

    private var consecutiveVoicedFrames = 0
    private var lastAcceptedAtMillis: Long? = null

    val voicedFrames: Int
        get() = consecutiveVoicedFrames

    fun resetSignal() {
        consecutiveVoicedFrames = 0
    }

    fun observeFrame(voiced: Boolean) {
        consecutiveVoicedFrames = if (voiced) {
            (consecutiveVoicedFrames + 1).coerceAtMost(requiredVoicedFrames + 2)
        } else {
            0
        }
    }

    fun evaluate(nowMillis: Long): Decision {
        if (consecutiveVoicedFrames < requiredVoicedFrames) {
            return Decision.LOW_SIGNAL
        }

        val lastAccepted = lastAcceptedAtMillis
        if (lastAccepted != null && nowMillis - lastAccepted < cooldownMillis) {
            return Decision.COOLDOWN
        }

        lastAcceptedAtMillis = nowMillis
        return Decision.ACCEPT
    }
}
