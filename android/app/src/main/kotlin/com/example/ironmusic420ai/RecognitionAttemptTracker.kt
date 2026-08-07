package com.example.ironmusic420ai

internal class RecognitionAttemptTracker(
    private val maxRetries: Int = 1,
) {
    private var generation = 0
    private var retryCount = 0

    fun resetOperation() {
        retryCount = 0
        invalidateAttempt()
    }

    fun beginAttempt(): Int {
        generation++
        return generation
    }

    fun invalidateAttempt() {
        generation++
    }

    fun isCurrent(attemptGeneration: Int): Boolean =
        generation == attemptGeneration

    fun canRetry(): Boolean = retryCount < maxRetries

    fun recordRetry(): Boolean {
        if (!canRetry()) return false
        retryCount++
        return true
    }
}
