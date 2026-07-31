package com.example.ironmusic420ai

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.AlarmClock
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.content.ContextCompat
import java.util.Locale

class IronVoiceService : Service(), RecognitionListener, TextToSpeech.OnInitListener {
    companion object {
        const val ACTION_START = "com.example.ironmusic420ai.START_IRON_VOICE"
        const val ACTION_STOP = "com.example.ironmusic420ai.STOP_IRON_VOICE"

        @Volatile
        var isRunning = false
            private set

        private const val CHANNEL_ID = "iron_voice_service"
        private const val NOTIFICATION_ID = 2420
    }

    private enum class VoiceState {
        WAITING_FOR_WAKE,
        WAITING_FOR_COMMAND,
    }

    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false
    private var isListening = false
    private var isSpeaking = false
    private var voiceState = VoiceState.WAITING_FOR_WAKE
    private var afterSpeech: (() -> Unit)? = null

    private val restartListening = Runnable {
        startListening()
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        textToSpeech = TextToSpeech(this, this)
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            stopSelf()
            return START_NOT_STICKY
        }

        startAsForeground("Iron е активен • кажи „Хей, Iron“")
        initializeRecognizer()
        scheduleListening(350)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        isListening = false
        isSpeaking = false
        isRunning = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun initializeRecognizer() {
        if (recognizer != null) return
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            updateNotification("На телефона няма услуга за гласово разпознаване")
            return
        }
        recognizer = SpeechRecognizer.createSpeechRecognizer(this).also {
            it.setRecognitionListener(this)
        }
    }

    private fun startListening() {
        handler.removeCallbacks(restartListening)
        if (!isRunning || isSpeaking || isListening) return
        val currentRecognizer = recognizer ?: return

        val recognitionIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "bg-BG")
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "bg-BG")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS,
                10_000L,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                2_500L,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                2_500L,
            )
        }

        try {
            isListening = true
            currentRecognizer.startListening(recognitionIntent)
            updateNotification(
                if (voiceState == VoiceState.WAITING_FOR_WAKE) {
                    "Iron е активен • кажи „Хей, Iron“"
                } else {
                    "Iron слуша командата"
                },
            )
        } catch (_: Exception) {
            isListening = false
            scheduleListening(2_000)
        }
    }

    private fun scheduleListening(delayMillis: Long = 1_500) {
        handler.removeCallbacks(restartListening)
        if (isRunning && !isSpeaking) {
            handler.postDelayed(restartListening, delayMillis)
        }
    }

    private fun processRecognition(results: Bundle?, isFinal: Boolean) {
        if (isSpeaking) return
        val phrases = results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            .orEmpty()
            .map(::normalize)
            .filter { it.isNotBlank() }
        if (phrases.isEmpty()) {
            if (isFinal) scheduleListening()
            return
        }

        if (voiceState == VoiceState.WAITING_FOR_WAKE) {
            val wakePhrase = phrases.firstOrNull(::containsWakePhrase)
            if (wakePhrase == null) {
                if (isFinal) scheduleListening(1_500)
                return
            }
            isListening = false
            recognizer?.cancel()
            val inlineCommand = commandAfterWakePhrase(wakePhrase)
            if (inlineCommand.isNotBlank()) {
                runVoiceCommand(inlineCommand)
            } else {
                voiceState = VoiceState.WAITING_FOR_COMMAND
                speak("Слушам") {
                    scheduleListening(250)
                }
            }
            return
        }

        if (isFinal) {
            isListening = false
            runVoiceCommand(phrases.first())
        }
    }

    private fun runVoiceCommand(command: String) {
        voiceState = VoiceState.WAITING_FOR_WAKE
        val reply = executeCommand(normalize(command))
        speak(reply) {
            scheduleListening(450)
        }
    }

    private fun executeCommand(command: String): String {
        return try {
            when {
                command.startsWith("automate ") ||
                    command.startsWith("аутомейт ") ||
                    command.startsWith("макро ") ||
                    command.startsWith("макродроид ") -> {
                    val automateCommand = command
                        .replaceFirst(
                            Regex("^(automate|аутомейт|макро(дроид)?)\\s+"),
                            "",
                        )
                        .trim()
                    if (automateCommand.isBlank()) {
                        "Кажи името на Automate командата."
                    } else {
                        sendAutomateCommand(automateCommand)
                        "Командата е изпратена."
                    }
                }

                command.contains("музика") ||
                    command.contains("music mode") ||
                    command.contains("музикален режим") -> {
                    sendAutomateCommand("music_mode_420")
                    "Музикалният режим е включен."
                }

                command.contains("фенер") &&
                    (command.contains("спри") || command.contains("изключи")) -> {
                    setFlashlight(false)
                    "Фенерчето е изключено."
                }

                command.contains("фенер") -> {
                    setFlashlight(true)
                    "Фенерчето е включено."
                }

                command.contains("увеличи") && command.contains("звук") -> {
                    adjustVolume(AudioManager.ADJUST_RAISE)
                    "Звукът е увеличен."
                }

                command.contains("намали") && command.contains("звук") -> {
                    adjustVolume(AudioManager.ADJUST_LOWER)
                    "Звукът е намален."
                }

                command.contains("youtube") || command.contains("ютуб") -> {
                    launchPackage("com.google.android.youtube")
                    "Отварям YouTube."
                }

                command.contains("камера") -> {
                    launch(Intent("android.media.action.IMAGE_CAPTURE"))
                    "Отварям камерата."
                }

                command.contains("карти") || command.contains("maps") -> {
                    launch(
                        Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=")).apply {
                            setPackage("com.google.android.apps.maps")
                        },
                    )
                    "Отварям картите."
                }

                command.contains("аларм") -> {
                    launch(Intent(AlarmClock.ACTION_SHOW_ALARMS))
                    "Отварям алармите."
                }

                command.contains("календар") -> {
                    launch(
                        Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_APP_CALENDAR)
                        },
                    )
                    "Отварям календара."
                }

                command.contains("телефон") || command.contains("набиране") -> {
                    launch(Intent(Intent.ACTION_DIAL))
                    "Отварям телефона."
                }

                command.contains("bluetooth") || command.contains("блутут") -> {
                    launch(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                    "Отварям Bluetooth."
                }

                command.contains("wi fi") ||
                    command.contains("wifi") ||
                    command.contains("уай фай") -> {
                    launch(Intent(Settings.ACTION_WIFI_SETTINGS))
                    "Отварям Wi‑Fi."
                }

                command.contains("нощен режим") || command.contains("night mode") -> {
                    adjustVolume(AudioManager.ADJUST_LOWER)
                    adjustVolume(AudioManager.ADJUST_LOWER)
                    "Нощният режим е включен."
                }

                command.contains("студио") -> {
                    openIronSection(1)
                    "Отварям Rap Studio."
                }

                command.contains("чат") -> {
                    openIronSection(3)
                    "Отварям чата."
                }

                command.contains("песни") || command.contains("библиотека") -> {
                    openIronSection(2)
                    "Отварям песните."
                }

                command.contains("начало") -> {
                    openIronSection(0)
                    "Отварям началния екран."
                }

                command.contains("настройки") -> {
                    launch(Intent(Settings.ACTION_SETTINGS))
                    "Отварям настройките."
                }

                command.contains("chrome") || command.contains("браузър") -> {
                    launchPackage("com.android.chrome")
                    "Отварям браузъра."
                }

                else -> "Не разбрах командата. Опитай пак."
            }
        } catch (error: SecurityException) {
            "Липсва нужно разрешение за тази команда."
        } catch (_: Exception) {
            "Тази команда не е достъпна на телефона."
        }
    }

    private fun sendAutomateCommand(command: String) {
        sendBroadcast(
            Intent("com.ironmusic420ai.MACRODROID_COMMAND").apply {
                putExtra("command", command)
            },
        )
    }

    private fun adjustVolume(direction: Int) {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.adjustStreamVolume(
            AudioManager.STREAM_MUSIC,
            direction,
            AudioManager.FLAG_SHOW_UI,
        )
    }

    private fun setFlashlight(enabled: Boolean) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("Camera permission is required")
        }
        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
            cameraManager
                .getCameraCharacteristics(id)
                .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        } ?: throw IllegalStateException("No flashlight")
        cameraManager.setTorchMode(cameraId, enabled)
    }

    private fun launchPackage(packageName: String) {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: throw IllegalStateException("App is not installed")
        launch(intent)
    }

    private fun launch(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun openIronSection(section: Int) {
        launch(
            Intent(this, MainActivity::class.java).apply {
                putExtra("iron_section", section)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
        )
    }

    private fun containsWakePhrase(value: String): Boolean {
        return wakePhrases.any(value::contains)
    }

    private fun commandAfterWakePhrase(value: String): String {
        for (wakePhrase in wakePhrases) {
            val index = value.indexOf(wakePhrase)
            if (index >= 0) {
                return value.substring(index + wakePhrase.length).trim()
            }
        }
        return ""
    }

    private fun normalize(value: String): String {
        return value
            .lowercase(Locale("bg", "BG"))
            .replace(Regex("[^a-zа-я0-9+\\- ]", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private val wakePhrases = listOf(
        "хей iron",
        "hey iron",
        "хей айрън",
        "hey айрън",
        "хей айрон",
        "хей ирон",
    )

    private fun speak(text: String, onFinished: () -> Unit) {
        handler.removeCallbacks(restartListening)
        isListening = false
        isSpeaking = true
        recognizer?.cancel()
        afterSpeech = onFinished
        if (!ttsReady) {
            handler.postDelayed({
                isSpeaking = false
                afterSpeech?.invoke()
                afterSpeech = null
            }, 250)
            return
        }

        updateNotification(text)
        textToSpeech?.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            "iron_${System.currentTimeMillis()}",
        )
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) return
        ttsReady = true
        textToSpeech?.language = Locale("bg", "BG")
        textToSpeech?.setSpeechRate(0.92f)
        textToSpeech?.setPitch(0.92f)
        textToSpeech?.setOnUtteranceProgressListener(
            object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit

                override fun onDone(utteranceId: String?) {
                    finishSpeech()
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    finishSpeech()
                }
            },
        )
    }

    private fun finishSpeech() {
        handler.post {
            isSpeaking = false
            val callback = afterSpeech
            afterSpeech = null
            callback?.invoke()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Iron гласов режим",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Показва, когато Iron слуша за „Хей, Iron“."
            setSound(null, null)
            enableVibration(false)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun startAsForeground(status: String) {
        val notification = buildNotification(status)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(status: String) {
        if (!isRunning) return
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(status))
    }

    private fun buildNotification(status: String): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, IronVoiceService::class.java).apply {
                action = ACTION_STOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Iron е активен")
            .setContentText(status)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_pause,
                    "Спри Iron",
                    stopIntent,
                ).build(),
            )
            .build()
    }

    override fun onReadyForSpeech(params: Bundle?) = Unit

    override fun onBeginningOfSpeech() = Unit
    override fun onRmsChanged(rmsdB: Float) = Unit
    override fun onBufferReceived(buffer: ByteArray?) = Unit

    override fun onEndOfSpeech() {
        isListening = false
    }

    override fun onError(error: Int) {
        isListening = false
        if (isSpeaking) return
        if (
            voiceState == VoiceState.WAITING_FOR_COMMAND &&
            (error == SpeechRecognizer.ERROR_NO_MATCH ||
                error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT)
        ) {
            voiceState = VoiceState.WAITING_FOR_WAKE
            speak("Не чух команда.") {
                scheduleListening(450)
            }
            return
        }
        scheduleListening(
            when (error) {
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> 3_000
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> 1_500
                SpeechRecognizer.ERROR_AUDIO,
                SpeechRecognizer.ERROR_CLIENT,
                SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                SpeechRecognizer.ERROR_SERVER -> 4_000
                else -> 2_500
            },
        )
    }

    override fun onResults(results: Bundle?) {
        isListening = false
        processRecognition(results, isFinal = true)
    }

    override fun onPartialResults(partialResults: Bundle?) {
        processRecognition(partialResults, isFinal = false)
    }

    override fun onEvent(eventType: Int, params: Bundle?) = Unit
}
