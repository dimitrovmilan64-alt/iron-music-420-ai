package com.example.ironmusic420ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class YoutubeResultMatcherTest {
    @Test
    fun bulgarianSongMatchesTheVisibleVideoTitle() {
        val score = YoutubeResultMatcher.score(
            query = "бяла роза",
            candidateText = "БЯЛА РОЗА - Славка Калчева • 39 млн. гледания • преди 8 години",
        )

        assertTrue(score > 0)
    }

    @Test
    fun punctuationDoesNotBreakAnEnglishSongMatch() {
        val score = YoutubeResultMatcher.score(
            query = "eminem lose yourself",
            candidateText = "Eminem – Lose Yourself [Official Video] 1.4B views",
        )

        assertTrue(score > 0)
    }

    @Test
    fun spokenConnectorWordsDoNotBlockTheRequestedSong() {
        val score = YoutubeResultMatcher.score(
            query = "lose yourself на eminem",
            candidateText = "Eminem - Lose Yourself (Official Video)",
        )

        assertTrue(score > 0)
    }

    @Test
    fun searchFieldCannotBecomeTheClickTarget() {
        assertEquals(
            Int.MIN_VALUE,
            YoutubeResultMatcher.score(
                query = "бяла роза",
                candidateText = "бяла роза",
                editable = true,
            ),
        )
    }

    @Test
    fun advertisementAndShortsCardsAreRejected() {
        val values = listOf(
            "Реклама • Бяла роза",
            "Бяла роза #Shorts",
            "Sponsored • Бяла роза",
        )

        values.forEach { candidate ->
            assertEquals(
                Int.MIN_VALUE,
                YoutubeResultMatcher.score("бяла роза", candidate),
            )
        }
    }

    @Test
    fun unrelatedVideoIsRejected() {
        assertEquals(
            Int.MIN_VALUE,
            YoutubeResultMatcher.score(
                query = "бяла роза",
                candidateText = "Червена роза - официално видео",
            ),
        )
    }

    @Test
    fun visibleVideoMetadataIsRequiredBeforeClicking() {
        assertTrue(
            YoutubeResultMatcher.hasMediaEvidence(
                "Бяла роза • 39 млн. гледания • 4:12",
            ),
        )
        assertEquals(
            false,
            YoutubeResultMatcher.hasMediaEvidence("Търси бяла роза"),
        )
    }
}
