package com.example.ironmusic420ai

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecognitionAttemptTrackerTest {
    @Test
    fun staleAttemptCannotBecomeCurrentAfterRetry() {
        val tracker = RecognitionAttemptTracker()
        tracker.resetOperation()
        val firstAttempt = tracker.beginAttempt()

        assertTrue(tracker.isCurrent(firstAttempt))
        assertTrue(tracker.recordRetry())
        tracker.invalidateAttempt()
        val secondAttempt = tracker.beginAttempt()

        assertFalse(tracker.isCurrent(firstAttempt))
        assertTrue(tracker.isCurrent(secondAttempt))
    }

    @Test
    fun operationAllowsExactlyOneRetry() {
        val tracker = RecognitionAttemptTracker()

        assertTrue(tracker.canRetry())
        assertTrue(tracker.recordRetry())
        assertFalse(tracker.canRetry())
        assertFalse(tracker.recordRetry())

        tracker.resetOperation()
        assertTrue(tracker.canRetry())
    }
}
