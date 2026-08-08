package com.example.ironmusic420ai

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.util.Log

/**
 * Single source of truth for torch selection and state.
 *
 * Realme devices expose several camera IDs. The first ID is not guaranteed to
 * own the flash, so every caller must use the same flash-capable back camera.
 */
object FlashlightController {
    private const val LOG_TAG = "IronFlashlight"

    @Volatile
    private var selectedCameraId: String? = null

    @Volatile
    private var torchEnabled = false

    fun isEnabled(): Boolean = torchEnabled

    fun setEnabled(context: Context, enabled: Boolean) {
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = findFlashCameraId(cameraManager)
        selectedCameraId = cameraId
        cameraManager.setTorchMode(cameraId, enabled)
        torchEnabled = enabled
        Log.i(LOG_TAG, "torch_set enabled=$enabled cameraId=$cameraId")
    }

    fun updateFromSystem(
        cameraManager: CameraManager,
        cameraId: String,
        enabled: Boolean,
    ) {
        val targetCameraId = selectedCameraId ?: try {
            findFlashCameraId(cameraManager)
        } catch (_: Exception) {
            return
        }
        if (cameraId != targetCameraId) return

        selectedCameraId = cameraId
        torchEnabled = enabled
        Log.i(LOG_TAG, "torch_state enabled=$enabled cameraId=$cameraId")
    }

    internal fun findFlashCameraId(cameraManager: CameraManager): String {
        val flashCameraIds = cameraManager.cameraIdList.filter { cameraId ->
            isFlashCamera(cameraManager, cameraId)
        }

        return flashCameraIds.firstOrNull { cameraId ->
            cameraManager.getCameraCharacteristics(cameraId)
                .get(CameraCharacteristics.LENS_FACING) ==
                CameraCharacteristics.LENS_FACING_BACK
        } ?: flashCameraIds.firstOrNull()
        ?: throw IllegalStateException("Телефонът няма достъпна светкавица.")
    }

    private fun isFlashCamera(
        cameraManager: CameraManager,
        cameraId: String,
    ): Boolean {
        return try {
            cameraManager.getCameraCharacteristics(cameraId)
                .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        } catch (_: Exception) {
            false
        }
    }
}
