package com.example.ironmusic420ai

import org.junit.Assert.assertEquals
import org.junit.Test

class VoicePromptGuardTest {
    @Test
    fun assistantNameAloneNeverBecomesAChatPrompt() {
        val guard = VoicePromptGuard(
            duplicateWindowMillis = 12_000,
            greetingWindowMillis = 60_000,
        )

        for (prompt in listOf("iron", "айрън", "аирън", "хей айрън", "слушам")) {
            assertEquals(
                VoicePromptGuard.Decision.BARE_WAKE_PHRASE,
                guard.evaluate(prompt, 1_000),
            )
        }
    }

    @Test
    fun repeatedGreetingsAreCollapsedButNormalConversationContinues() {
        val guard = VoicePromptGuard(
            duplicateWindowMillis = 12_000,
            greetingWindowMillis = 60_000,
        )

        assertEquals(VoicePromptGuard.Decision.FORWARD, guard.evaluate("привет", 1_000))
        assertEquals(VoicePromptGuard.Decision.DUPLICATE, guard.evaluate("здравей", 8_000))
        assertEquals(
            VoicePromptGuard.Decision.FORWARD,
            guard.evaluate("как си днес", 8_100),
        )
        assertEquals(
            VoicePromptGuard.Decision.DUPLICATE,
            guard.evaluate("как си днес", 15_000),
        )
        assertEquals(
            VoicePromptGuard.Decision.FORWARD,
            guard.evaluate("как си днес", 21_000),
        )
    }
}
