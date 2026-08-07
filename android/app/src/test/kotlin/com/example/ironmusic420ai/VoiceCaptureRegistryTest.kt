package com.example.ironmusic420ai

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceCaptureRegistryTest {
    @Test
    fun releasingOldOwnerDoesNotReleaseNewCapture() {
        val oldService = Any()
        val newService = Any()

        try {
            VoiceCaptureRegistry.setWakeActive(oldService, true)
            VoiceCaptureRegistry.setWakeActive(newService, true)
            VoiceCaptureRegistry.setWakeActive(oldService, false)

            assertTrue(VoiceCaptureRegistry.isAnyCaptureActive())
            assertFalse(VoiceCaptureRegistry.isWakeActive(oldService))
            assertTrue(VoiceCaptureRegistry.isWakeActive(newService))
        } finally {
            VoiceCaptureRegistry.setWakeActive(oldService, false)
            VoiceCaptureRegistry.setWakeActive(newService, false)
        }
    }

    @Test
    fun captureIsActiveUntilBothPipelinesReleaseIt() {
        val service = Any()

        try {
            VoiceCaptureRegistry.setWakeActive(service, true)
            VoiceCaptureRegistry.setSpeechActive(service, true)
            VoiceCaptureRegistry.setWakeActive(service, false)

            assertTrue(VoiceCaptureRegistry.isAnyCaptureActive())

            VoiceCaptureRegistry.setSpeechActive(service, false)
            assertFalse(VoiceCaptureRegistry.isAnyCaptureActive())
        } finally {
            VoiceCaptureRegistry.setWakeActive(service, false)
            VoiceCaptureRegistry.setSpeechActive(service, false)
        }
    }
}
