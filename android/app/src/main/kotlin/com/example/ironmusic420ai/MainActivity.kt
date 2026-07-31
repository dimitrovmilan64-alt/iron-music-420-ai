package com.example.ironmusic420ai

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.AlarmClock
import android.provider.Settings
import android.speech.SpeechRecognizer
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
    private var pendingVoiceResult: MethodChannel.Result? = null
    private var pendingIronSection: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        captureIronSection(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "execute" -> {
                        val action = call.argument<String>("action").orEmpty()
                        val command = call.argument<String>("command").orEmpty()
                        executeAction(action, command, result)
                    }
                    "consumeIronSection" -> {
                        result.success(pendingIronSection)
                        pendingIronSection = null
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIronSection(intent)
    }

    private fun captureIronSection(intent: Intent?) {
        val section = intent?.getIntExtra("iron_section", -1) ?: -1
        if (section in 0..4) {
            pendingIronSection = section
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
                "alarms" -> openAlarms(result)
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
                "music_mode" -> sendMusicModeBroadcast(result)
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
                    result.success(
                        "Night Mode: звукът е намален и настройките за „Не безпокой“ са отворени."
                    )
                }
                "iron_voice_status" -> {
                    result.success(if (IronVoiceService.isRunning) "active" else "inactive")
                }
                "iron_voice_on" -> startIronVoice(result)
                "iron_voice_off" -> {
                    stopService(
                        Intent(this, IronVoiceService::class.java).apply {
                            this.action = IronVoiceService.ACTION_STOP
                        }
                    )
                    result.success("Iron е спрян.")
                }
                "open_automate" -> openPackageOrUrl(
                    "com.llamalab.automate",
                    "market://details?id=com.llamalab.automate",
                    "Automate е отворен.",
                    result
                )
                "macrodroid_broadcast" -> sendAutomationCommand(command, result)
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

    private fun startIronVoice(result: MethodChannel.Result) {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error(
                "SPEECH_RECOGNIZER_UNAVAILABLE",
                "Телефонът няма активна услуга за гласово разпознаване.",
                null
            )
            return
        }

        val missingPermissions = mutableListOf<String>()
        if (
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            missingPermissions.add(Manifest.permission.RECORD_AUDIO)
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            missingPermissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (missingPermissions.isNotEmpty()) {
            pendingVoiceResult = result
            ActivityCompat.requestPermissions(
                this,
                missingPermissions.toTypedArray(),
                4202
            )
            return
        }
        launchIronVoiceService(result)
    }

    private fun launchIronVoiceService(result: MethodChannel.Result) {
        ContextCompat.startForegroundService(
            this,
            Intent(this, IronVoiceService::class.java).apply {
                action = IronVoiceService.ACTION_START
            }
        )
        result.success("Iron е активен офлайн. Кажи „Hey Iron“.")
    }

    private fun sendAutomationCommand(
        command: String,
        result: MethodChannel.Result
    ) {
        if (command.isBlank()) {
            result.error(
                "EMPTY_COMMAND",
                "Въведи име на Automate командата.",
                null
            )
            return
        }
        val intent = Intent("com.ironmusic420ai.MACRODROID_COMMAND").apply {
            putExtra("command", command)
        }
        sendBroadcast(intent)
        result.success("Командата „$command“ е изпратена към Automate.")
    }

    private fun sendMusicModeBroadcast(result: MethodChannel.Result) {
        val intent = Intent("com.ironmusic420ai.MACRODROID_COMMAND").apply {
            putExtra("command", "music_mode_420")
        }
        sendBroadcast(intent)
        result.success("Музикалният режим е изпратен към Automate.")
    }

    private fun openAlarms(result: MethodChannel.Result) {
        val intents = listOf(Intent(AlarmClock.ACTION_SHOW_ALARMS))
        for (intent in intents) {
            try {
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    result.success("Алармите са отворени.")
                    return
                }
            } catch (_: Exception) {
                // Some Android manufacturers block one of the clock intents.
            }
        }
        result.error(
            "ALARMS_UNAVAILABLE",
            "Приложението за часовник не е достъпно.",
            null
        )
    }

    private fun setFlashlight(enabled: Boolean, result: MethodChannel.Result) {
        if (
            ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) !=
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
        when (requestCode) {
            4201 -> {
                val result = pendingFlashResult ?: return
                pendingFlashResult = null
                if (
                    grantResults.isNotEmpty() &&
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
            4202 -> {
                val result = pendingVoiceResult ?: return
                pendingVoiceResult = null
                if (
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    try {
                        launchIronVoiceService(result)
                    } catch (error: Exception) {
                        result.error("IRON_VOICE_ERROR", error.localizedMessage, null)
                    }
                } else {
                    result.error(
                        "MICROPHONE_PERMISSION",
                        "Разреши микрофона, за да работи „Hey Iron“.",
                        null
                    )
                }
            }
        }
    }
}
