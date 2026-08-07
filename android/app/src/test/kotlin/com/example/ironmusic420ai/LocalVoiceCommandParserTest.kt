package com.example.ironmusic420ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LocalVoiceCommandParserTest {
    @Test
    fun youtubeSongRequestBecomesSearchWithTheRequestedSong() {
        val command = LocalVoiceCommandParser.parse(
            "Отвори YouTube и пусни Eminem Lose Yourself",
        )

        assertEquals("youtube_search", command?.action)
        assertEquals("eminem lose yourself", command?.argument)
    }

    @Test
    fun youtubeSuffixKeepsOnlyTheSearchQuery() {
        val command = LocalVoiceCommandParser.parse(
            "Пусни Linkin Park Numb в YouTube",
        )

        assertEquals("youtube_search", command?.action)
        assertEquals("linkin park numb", command?.argument)
    }

    @Test
    fun explicitSongRequestWorksWithoutCloudAi() {
        val command = LocalVoiceCommandParser.parse(
            "Пусни песента Lose Yourself на Eminem",
        )

        assertEquals("youtube_search", command?.action)
        assertEquals("lose yourself на eminem", command?.argument)
    }

    @Test
    fun plainYoutubeRequestStillOpensTheHomePage() {
        val command = LocalVoiceCommandParser.parse("Отвори YouTube")

        assertEquals("youtube", command?.action)
        assertEquals("", command?.argument)
    }

    @Test
    fun incidentalYoutubeMentionIsLeftForTheAiRouter() {
        assertNull(LocalVoiceCommandParser.parse("Харесвам YouTube много"))
    }

    @Test
    fun explicitFlashOffCannotBeMistakenForFlashOn() {
        val commands = listOf(
            LocalVoiceCommandParser.parse("Изключи фенера"),
            LocalVoiceCommandParser.parse("Изключи фенерчето"),
            LocalVoiceCommandParser.parse("Спри фенерчето"),
        )

        commands.forEach { command ->
            assertEquals("flash_off", command?.action)
        }
    }
}
