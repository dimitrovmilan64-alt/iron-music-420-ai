package com.example.ironmusic420ai

internal class VoicePromptGuard(
    private val duplicateWindowMillis: Long,
    private val greetingWindowMillis: Long,
) {
    enum class Decision {
        FORWARD,
        BARE_WAKE_PHRASE,
        DUPLICATE,
    }

    private var lastCanonicalPrompt = ""
    private var lastForwardedAtMillis = Long.MIN_VALUE

    fun evaluate(normalizedPrompt: String, nowMillis: Long): Decision {
        val cleanPrompt = normalizedPrompt.trim()
        if (cleanPrompt in bareWakePhrases) {
            return Decision.BARE_WAKE_PHRASE
        }

        val canonicalPrompt = if (cleanPrompt in greetingOnlyPhrases) {
            GREETING_CANONICAL
        } else {
            cleanPrompt
        }
        val duplicateWindow = if (canonicalPrompt == GREETING_CANONICAL) {
            greetingWindowMillis
        } else {
            duplicateWindowMillis
        }

        if (
            canonicalPrompt.isNotEmpty() &&
            canonicalPrompt == lastCanonicalPrompt &&
            nowMillis - lastForwardedAtMillis < duplicateWindow
        ) {
            return Decision.DUPLICATE
        }

        lastCanonicalPrompt = canonicalPrompt
        lastForwardedAtMillis = nowMillis
        return Decision.FORWARD
    }

    private companion object {
        const val GREETING_CANONICAL = "__greeting__"

        val bareWakePhrases = setOf(
            "iron",
            "айрън",
            "айрон",
            "ирон",
            "аирън",
            "айран",
            "hey iron",
            "hey айрън",
            "hey аирън",
            "хей iron",
            "хей айрън",
            "хей аирън",
            "хей айрон",
            "хей ирон",
            "слушам",
            "аз съм iron",
            "аз съм айрън",
            "iron music 420 ai",
        )

        val greetingOnlyPhrases = setOf(
            "здравей",
            "здравейте",
            "здрасти",
            "привет",
            "привети",
            "здравей iron",
            "здравей айрън",
            "здрасти iron",
            "здрасти айрън",
            "привет iron",
            "привет айрън",
        )
    }
}
