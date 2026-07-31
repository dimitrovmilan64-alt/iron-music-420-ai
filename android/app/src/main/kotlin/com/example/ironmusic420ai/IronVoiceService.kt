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
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
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
import kotlin.math.sqrt

class IronVoiceService : Service(), RecognitionListener, TextToSpeech.OnInitListener {
    companion object {
        const val ACTION_START = "com.example.ironmusic420ai.START_IRON_VOICE"
        const val ACTION_STOP = "com.example.ironmusic420ai.STOP_IRON_VOICE"

        @Volatile
        var isRunning = false
            private set

        private const val CHANNEL_ID = "iron_voice_service"
        private const val NOTIFICATION_ID = 2420
        private const val WAKE_SAMPLE_RATE = 16_000
        private const val WAKE_CALIBRATION_FRAMES = 8
        private const val WAKE_REQUIRED_FRAMES = 2
        private const val WAKE_MIN_RMS = 700.0
        private const val WAKE_NOISE_MULTIPLIER = 3.0
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
    private var foregroundStarted = false
    private var wakeAudioRecord: AudioRecord? = null
    private var wakeMonitorThread: Thread? = null

    @Volatile
    private var wakeMonitorActive = false

    private val beginSpeechRecognition = Runnable {
        startListening()
    }
    private val beginWakeMonitoring = Runnable {
        startWakeMonitoring()
    }
    private val recognitionTimeout = Runnable {
        if (!isListening || isSpeaking) return@Runnable
        isListening = false
        recognizer?.cancel()
        if (voiceState == VoiceState.WAITING_FOR_COMMAND) {
            voiceState = VoiceState.WAITING_FOR_WAKE
            speak("Не чух команда.") {
                scheduleWakeMonitoring(450)
            }
        } else {
            scheduleWakeMonitoring(450)
        }
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

        if (!foregroundStarted) {
            startAsForeground("Iron е активен • кажи „Хей, Iron“")
            foregroundStarted = true
        }
        initializeRecognizer()
        scheduleWakeMonitoring(350)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacksAndMessages(null)
        stopWakeMonitoring()
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        isListening = false
        isSpeaking = false
        foregroundStarted = false
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
        handler.removeCallbacks(beginSpeechRecognition)
        handler.removeCallbacks(recognitionTimeout)
        if (!isRunning || isSpeaking || isListening) return
        stopWakeMonitoring()
        initializeRecognizer()
        val currentRecognizer = recognizer ?: run {
            if (voiceState == VoiceState.WAITING_FOR_WAKE) {
                scheduleWakeMonitoring(1_500)
            }
            return
        }

        val recognitionIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "bg-BG")
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "bg-BG")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                putStringArrayListExtra(
                    RecognizerIntent.EXTRA_BIASING_STRINGS,
                    arrayListOf("Хей, Iron", "Хей, Айрън", "Iron", "Айрън"),
                )
            }
        }

        try {
            isListening = true
            currentRecognizer.startListening(recognitionIntent)
            handler.postDelayed(
                recognitionTimeout,
                if (voiceState == VoiceState.WAITING_FOR_COMMAND) 9_000 else 7_000,
            )
        } catch (_: Exception) {
            isListening = false
            resetRecognizer()
            if (voiceState == VoiceState.WAITING_FOR_COMMAND) {
                voiceState = VoiceState.WAITING_FOR_WAKE
                speak("Не успях да включа микрофона.") {
                    scheduleWakeMonitoring(1_200)
                }
            } else {
                scheduleWakeMonitoring(1_200)
            }
        }
    }

    private fun scheduleCommandListening(delayMillis: Long = 250) {
        handler.removeCallbacks(beginSpeechRecognition)
        if (
            isRunning &&
            !isSpeaking &&
            voiceState == VoiceState.WAITING_FOR_COMMAND
        ) {
            handler.postDelayed(beginSpeechRecognition, delayMillis)
        }
    }

    private fun scheduleWakeMonitoring(delayMillis: Long = 500) {
        handler.removeCallbacks(beginWakeMonitoring)
        if (
            isRunning &&
            !isSpeaking &&
            voiceState == VoiceState.WAITING_FOR_WAKE &&
            !wakeMonitorActive
        ) {
            handler.postDelayed(beginWakeMonitoring, delayMillis)
        }
    }

    private fun startWakeMonitoring() {
        handler.removeCallbacks(beginWakeMonitoring)
        if (
            !isRunning ||
            isSpeaking ||
            isListening ||
            wakeMonitorActive ||
            voiceState != VoiceState.WAITING_FOR_WAKE
        ) {
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            stopSelf()
            return
        }

        val minimumBufferSize = AudioRecord.getMinBufferSize(
            WAKE_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minimumBufferSize <= 0) {
            scheduleWakeMonitoring(2_000)
            return
        }

        val recorder = try {
            AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(WAKE_SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(maxOf(minimumBufferSize * 2, 4_096))
                .build()
        } catch (_: Exception) {
            scheduleWakeMonitoring(2_000)
            return
        }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            scheduleWakeMonitoring(2_000)
            return
        }

        try {
            recorder.startRecording()
        } catch (_: Exception) {
            recorder.release()
            scheduleWakeMonitoring(2_000)
            return
        }

        wakeAudioRecord = recorder
        wakeMonitorActive = true
        val samples = ShortArray(maxOf(512, minimumBufferSize / 2))
        wakeMonitorThread = Thread(
            {
                var calibrationFrames = 0
                var loudFrames = 0
                var noiseFloor = 250.0
                var speechDetected = false
                try {
                    while (isRunning && wakeMonitorActive) {
                        val sampleCount = recorder.read(
                            samples,
                            0,
                            samples.size,
                            AudioRecord.READ_BLOCKING,
                        )
                        if (sampleCount <= 0) continue

                        var squareSum = 0.0
                        for (index in 0 until sampleCount) {
                            val sample = samples[index].toDouble()
                            squareSum += sample * sample
                        }
                        val rms = sqrt(squareSum / sampleCount)
                        if (calibrationFrames < WAKE_CALIBRATION_FRAMES) {
                            noiseFloor = (noiseFloor * 0.75) + (rms * 0.25)
                            calibrationFrames += 1
                            continue
                        }

                        val trigger = maxOf(
                            WAKE_MIN_RMS,
                            noiseFloor * WAKE_NOISE_MULTIPLIER,
                        )
                        if (rms >= trigger) {
                            loudFrames += 1
                        } else {
                            loudFrames = 0
                            noiseFloor = ((noiseFloor * 0.96) + (rms * 0.04))
                                .coerceIn(120.0, 4_000.0)
                        }

                        if (loudFrames >= WAKE_REQUIRED_FRAMES) {
                            speechDetected = true
                            wakeMonitorActive = false
                            break
                        }
                    }
                } catch (_: Exception) {
                    // The main thread performs cleanup and restarts the monitor if needed.
                } finally {
                    handler.post {
                        if (wakeAudioRecord === recorder) {
                            stopWakeMonitoring()
                        }
                        if (
                            speechDetected &&
                            isRunning &&
                            !isSpeaking &&
                            voiceState == VoiceState.WAITING_FOR_WAKE
                        ) {
                            startListening()
                        } else if (isRunning) {
                            scheduleWakeMonitoring(1_200)
                        }
                    }
                }
            },
            "IronWakeMonitor",
        ).apply {
            isDaemon = true
            start()
        }
    }

    private fun stopWakeMonitoring() {
        wakeMonitorActive = false
        val recorder = wakeAudioRecord
        wakeAudioRecord = null
        try {
            if (recorder?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                recorder.stop()
            }
        } catch (_: Exception) {
            // The recorder may already have been stopped by Android.
        }
        recorder?.release()
        wakeMonitorThread = null
    }

    private fun resetRecognizer() {
        recognizer?.destroy()
        recognizer = null
        initializeRecognizer()
    }

    private fun processRecognition(results: Bundle?, isFinal: Boolean) {
        if (isSpeaking) return
        val phrases = results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            .orEmpty()
            .map(::normalize)
            .filter { it.isNotBlank() }
        if (phrases.isEmpty()) {
            if (isFinal) {
                if (voiceState == VoiceState.WAITING_FOR_COMMAND) {
                    voiceState = VoiceState.WAITING_FOR_WAKE
                    speak("Не чух команда.") {
                        scheduleWakeMonitoring(450)
                    }
                } else {
                    scheduleWakeMonitoring()
                }
            }
            return
        }

        if (voiceState == VoiceState.WAITING_FOR_WAKE) {
            val wakePhrase = phrases.firstOrNull(::containsWakePhrase)
            if (wakePhrase == null) {
                if (isFinal) scheduleWakeMonitoring(450)
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
                    scheduleCommandListening(250)
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
            scheduleWakeMonitoring(450)
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
        return wakePhrases.any(value::contains) ||
            value.split(' ').any(wakeWords::contains)
    }

    private fun commandAfterWakePhrase(value: String): String {
        for (wakePhrase in wakePhrases) {
            val index = value.indexOf(wakePhrase)
            if (index >= 0) {
                return value.substring(index + wakePhrase.length).trim()
            }
        }
        for (wakeWord in wakeWords) {
            val match = Regex("(^| )${Regex.escape(wakeWord)}(?= |$)")
                .find(value) ?: continue
            return value.substring(match.range.last + 1).trim()
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

    private val wakeWords = setOf(
        "iron",
        "айрън",
        "айрон",
        "айран",
        "ирон",
    )

    private fun speak(text: String, onFinished: () -> Unit) {
        handler.removeCallbacks(beginSpeechRecognition)
        handler.removeCallbacks(beginWakeMonitoring)
        handler.removeCallbacks(recognitionTimeout)
        stopWakeMonitoring()
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
        // Keep the recognizer marked busy until onResults/onError arrives.
    }

    override fun onError(error: Int) {
        handler.removeCallbacks(recognitionTimeout)
        isListening = false
        if (isSpeaking) return
        if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
            stopSelf()
            return
        }
        if (
            voiceState == VoiceState.WAITING_FOR_COMMAND &&
            (error == SpeechRecognizer.ERROR_NO_MATCH ||
                error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT)
        ) {
            voiceState = VoiceState.WAITING_FOR_WAKE
            speak("Не чух команда.") {
                scheduleWakeMonitoring(450)
            }
            return
        }
        if (
            error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY ||
            error == SpeechRecognizer.ERROR_AUDIO ||
            error == SpeechRecognizer.ERROR_CLIENT ||
            error == SpeechRecognizer.ERROR_SERVER_DISCONNECTED
        ) {
            resetRecognizer()
        }
        if (voiceState == VoiceState.WAITING_FOR_COMMAND) {
            voiceState = VoiceState.WAITING_FOR_WAKE
        }
        scheduleWakeMonitoring(
            when (error) {
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> 1_200
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> 700
                SpeechRecognizer.ERROR_AUDIO,
                SpeechRecognizer.ERROR_CLIENT,
                SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                SpeechRecognizer.ERROR_SERVER,
                SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> 2_000
                SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> 10_000
                else -> 1_500
            },
        )
    }

    override fun onResults(results: Bundle?) {
        handler.removeCallbacks(recognitionTimeout)
        isListening = false
        processRecognition(results, isFinal = true)
    }

    override fun onPartialResults(partialResults: Bundle?) {
        processRecognition(partialResults, isFinal = false)
    }

    override fun onEvent(eventType: Int, params: Bundle?) = Unit
}
