package com.example.ironmusic420ai

import java.text.Normalizer
import java.util.Locale

internal object YoutubeResultMatcher {
    private val combiningMarks = Regex("\\p{Mn}+")
    private val separators = Regex("[^\\p{L}\\p{N}]+")
    private val repeatedSpaces = Regex("\\s+")
    private val blockedMarkers = setOf(
        "ad",
        "ads",
        "advertisement",
        "sponsored",
        "shorts",
        "реклама",
        "реклами",
        "спонсорирано",
    )
    private val ignoredQueryTokens = setOf(
        "by",
        "in",
        "on",
        "the",
        "в",
        "и",
        "на",
        "от",
        "за",
    )
    private val mediaMarkers = setOf(
        "ago",
        "minutes",
        "seconds",
        "views",
        "гледания",
        "минути",
        "преди",
        "секунди",
    )
    private val duration = Regex("(?:^|\\s)\\d{1,2}:\\d{2}(?:\\s|$)")

    fun normalize(value: CharSequence?): String =
        Normalizer.normalize(value?.toString().orEmpty(), Normalizer.Form.NFD)
            .replace(combiningMarks, "")
            .lowercase(Locale.ROOT)
            .replace(separators, " ")
            .trim()
            .replace(repeatedSpaces, " ")

    fun score(query: String, candidateText: String, editable: Boolean = false): Int {
        if (editable) return Int.MIN_VALUE
        val normalizedQuery = normalize(query)
        val normalizedCandidate = normalize(candidateText)
        if (normalizedQuery.isBlank() || normalizedCandidate.isBlank()) {
            return Int.MIN_VALUE
        }

        val queryTokens = normalizedQuery
            .split(' ')
            .filter { it.length >= 2 }
            .filterNot(ignoredQueryTokens::contains)
            .distinct()
        if (queryTokens.isEmpty()) return Int.MIN_VALUE

        val candidateTokens = normalizedCandidate.split(' ').toSet()
        if (!queryTokens.all(candidateTokens::contains)) return Int.MIN_VALUE
        if (blockedMarkers.any(candidateTokens::contains)) return Int.MIN_VALUE

        var score = queryTokens.size * 20
        if (normalizedCandidate.contains(normalizedQuery)) score += 60
        if (mediaMarkers.any(candidateTokens::contains)) score += 10
        return score
    }

    fun isSearchFieldFor(query: String, fieldText: String): Boolean {
        val normalizedQuery = normalize(query)
        val normalizedField = normalize(fieldText)
        return normalizedQuery.isNotBlank() &&
            normalizedField.isNotBlank() &&
            normalizedField.contains(normalizedQuery)
    }

    fun isEligibleMediaResult(
        candidateText: String,
        editable: Boolean = false,
    ): Boolean {
        if (editable || !hasMediaEvidence(candidateText)) return false
        val candidateTokens = normalize(candidateText).split(' ').toSet()
        return blockedMarkers.none(candidateTokens::contains)
    }

    fun hasMediaEvidence(candidateText: String): Boolean {
        val candidateTokens = normalize(candidateText).split(' ').toSet()
        if (mediaMarkers.any(candidateTokens::contains)) return true
        return duration.containsMatchIn(candidateText.lowercase(Locale.ROOT))
    }
}
