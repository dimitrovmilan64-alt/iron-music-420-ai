package com.example.ironmusic420ai

import java.util.concurrent.ConcurrentHashMap

internal object VoiceCaptureRegistry {
    private val wakeOwners = ConcurrentHashMap.newKeySet<Any>()
    private val speechOwners = ConcurrentHashMap.newKeySet<Any>()

    fun setWakeActive(owner: Any, active: Boolean) {
        setOwnerActive(wakeOwners, owner, active)
    }

    fun setSpeechActive(owner: Any, active: Boolean) {
        setOwnerActive(speechOwners, owner, active)
    }

    fun isAnyCaptureActive(): Boolean =
        wakeOwners.isNotEmpty() || speechOwners.isNotEmpty()

    fun isWakeActive(owner: Any): Boolean = wakeOwners.contains(owner)

    fun isSpeechActive(owner: Any): Boolean = speechOwners.contains(owner)

    private fun setOwnerActive(
        owners: MutableSet<Any>,
        owner: Any,
        active: Boolean,
    ) {
        if (active) {
            owners.add(owner)
        } else {
            owners.remove(owner)
        }
    }
}
