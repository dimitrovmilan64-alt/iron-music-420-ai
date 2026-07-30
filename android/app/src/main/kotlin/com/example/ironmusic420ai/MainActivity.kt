package com.example.ironmusic420ai

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.provider.AlarmClock
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "iron_music_420/automations"
    private var pendingFlashResult: MethodChannel.Result? = null
    private var pendingFlashEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "execute") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val action = call.argument<String>("action").orEmpty()
                val command = call.argument<String>("command").orEmpty()
                executeAction(action, command, result)
            }
    }

    private fun executeAction(
        action: String,
        command: String,
        result: MethodChannel.Result
    ) {
        try {
            when (action) {
                "youtube" -> openPackageOrUrl(
                    "com.google.android.youtube",
                    "https://www.youtube.com",
                    "YouTube е отворен.",
                    result
                )
                "chrome" -> openPackageOrUrl(
                    "com.android.chrome",
                    "https://www.google.com",
                    "Браузърът е отворен.",
                    result
                )
                "camera" -> {
                    startActivity(Intent("android.media.action.IMAGE_CAPTURE"))
                    result.success("Камерата е отворена.")
                }
                "maps" -> {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q="))
                    intent.setPackage("com.google.android.apps.maps")
                    if (intent.resolveActivity(packageManager) == null) {
                        intent.setPackage(null)
                    }
                    startActivity(intent)
                    result.success("Картите са отворени.")
                }
                "settings" -> {
                    startActivity(Intent(Settings.ACTION_SETTINGS))
                    result.success("Настройките са отворени.")
                }
                "bluetooth" -> {
                    startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                    result.success("Bluetooth настройките са отворени.")
                }
                "wifi" -> {
                    startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                    result.success("Wi‑Fi настройките са отворени.")
                }
                "dialer" -> {
                    startActivity(Intent(Intent.ACTION_DIAL))
                    result.success("Телефонът е отворен.")
                }
                "alarms" -> {
                    startActivity(Intent(AlarmClock.ACTION_SHOW_ALARMS))
                    result.success("Алармите са отворени.")
                }
                "calendar" -> {
                    val intent = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_APP_CALENDAR)
                    }
                    startActivity(intent)
                    result.success("Календарът е отворен.")
                }
                "flash_on" -> setFlashlight(true, result)
                "flash_off" -> setFlashlight(false, result)
                "volume_up" -> {
                    adjustVolume(AudioManager.ADJUST_RAISE)
                    result.success("Звукът е увеличен.")
                }
                "volume_down" -> {
                    adjustVolume(AudioManager.ADJUST_LOWER)
                    result.success("Звукът е намален.")
                }
                "keep_awake_on" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success("Екранът ще остане включен, докато приложението е отворено.")
                }
                "keep_awake_off" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success("Нормалното изгасване на екрана е възстановено.")
                }
                "music_mode" -> {
                    // v2.5.3: Music Mode is controlled only by the user's MacroDroid macro.
                    // This avoids opening Spotify or any web fallback from Iron Music.
                    sendMusicModeBroadcast(result)
                }
                "studio_mode" -> {
                    adjustVolume(AudioManager.ADJUST_RAISE)
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success("Studio Mode е активиран.")
                }
                "night_mode" -> {
                    adjustVolume(AudioManager.ADJUST_LOWER)
                    adjustVolume(AudioManager.ADJUST_LOWER)
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                    result.success("Night Mode: звукът е намален и настройките за „Не безпокой“ са отворени.")
                }
                "open_macrodroid" -> openPackageOrUrl(
                    "com.arlosoft.macrodroid",
                    "https://play.google.com/store/apps/details?id=com.arlosoft.macrodroid",
                    "MacroDroid е отворен.",
                    result
                )
                "macrodroid_broadcast" -> sendMacroDroidCommand(command, result)
                else -> result.error(
                    "UNKNOWN_ACTION",
                    "Непозната автоматизация.",
                    null
                )
            }
        } catch (error: Exception) {
            result.error(
                "AUTOMATION_ERROR",
                error.localizedMessage ?: "Действието не е достъпно.",
                null
            )
        }
    }

    private fun adjustVolume(direction: Int) {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.adjustStreamVolume(
            AudioManager.STREAM_MUSIC,
            direction,
            AudioManager.FLAG_SHOW_UI
        )
    }

    private fun sendMacroDroidCommand(
        command: String,
        result: MethodChannel.Result
    ) {
        if (command.isBlank()) {
            result.error(
                "EMPTY_COMMAND",
                "Въведи име на MacroDroid командата.",
                null
            )
            return
        }
        val intent = Intent("com.ironmusic420ai.MACRODROID_COMMAND").apply {
            setPackage("com.arlosoft.macrodroid")
            putExtra("command", command)
            putExtra("source", "Iron Music 420 AI")
        }
        sendBroadcast(intent)
        result.success("Командата „$command“ е изпратена към MacroDroid.")
    }

    private fun sendMusicModeBroadcast(result: MethodChannel.Result) {
        val intent = Intent("com.ironmusic420ai.MACRODROID_COMMAND").apply {
            putExtra("command", "music_mode_420")
        }
        sendBroadcast(intent)
        result.success("Music Mode е изпратен към MacroDroid.")
    }

    private fun setFlashlight(enabled: Boolean, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            pendingFlashResult = result
            pendingFlashEnabled = enabled
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                4201
            )
            return
        }
        toggleFlash(enabled, result)
    }

    private fun toggleFlash(enabled: Boolean, result: MethodChannel.Result) {
        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = cameraManager.cameraIdList.firstOrNull()
            ?: throw IllegalStateException("Телефонът няма достъпна светкавица.")
        cameraManager.setTorchMode(cameraId, enabled)
        result.success(
            if (enabled) "Фенерчето е включено."
            else "Фенерчето е изключено."
        )
    }

    private fun openPackageOrUrl(
        packageName: String,
        fallbackUrl: String,
        successMessage: String,
        result: MethodChannel.Result
    ) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        if (launchIntent != null) {
            startActivity(launchIntent)
        } else {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(fallbackUrl)))
        }
        result.success(successMessage)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 4201) return
        val result = pendingFlashResult ?: return
        pendingFlashResult = null
        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            try {
                toggleFlash(pendingFlashEnabled, result)
            } catch (error: Exception) {
                result.error("FLASH_ERROR", error.localizedMessage, null)
            }
        } else {
            result.error(
                "CAMERA_PERMISSION",
                "Разреши достъп до камерата, за да работи фенерчето.",
                null
            )
        }
    }
}
