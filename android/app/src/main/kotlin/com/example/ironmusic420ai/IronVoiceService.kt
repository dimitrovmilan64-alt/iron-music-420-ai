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
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.KeywordSpotter
import com.k2fsa.sherpa.onnx.KeywordSpotterConfig
import com.k2fsa.sherpa.onnx.OnlineModelConfig
import com.k2fsa.sherpa.onnx.OnlineStream
import com.k2fsa.sherpa.onnx.OnlineTransducerModelConfig
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
        private const val WAKE_FRAME_SAMPLES = 1_600
        private const val MODEL_DIR =
            "sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
    }

    private enum class VoiceState {
        WAITING_FOR_WAKE,
        WAITING_FOR_COMMAND,
    }

    private data class RecorderHandle(
        val recorder: AudioRecord,
        val sourceName: String,
    )

    private val handler = Handler(Looper.getMainLooper())
    private val aiRouter by lazy { GeminiVoiceRouter(this) }
    private var recognizer: SpeechRecognizer? = null
    private var keywordSpotter: KeywordSpotter? = null
    private var keywordStream: OnlineStream? = null
    private var wakeAudioRecord: AudioRecord? = null
    private var wakeThread: Thread? = null
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false
    private var isListening = false
    private var isSpeaking = false
    private var foregroundStarted = false
    private var voiceState = VoiceState.WAITING_FOR_WAKE
    private var afterSpeech: (() -> Unit)? = null
    private var followUpListening = false
    private var lastPartialCommand = ""

    @Volatile
    private var wakeWordActive = false

    @Volatile
    private var wakeEngineLoading = false

    @Volatile
    private var isAiProcessing = false

    private val beginSpeechRecognition = Runnable {
        startListening()
    }
    private val beginWakeWordListening = Runnable {
        startWakeWordListening()
    }
    private val recognitionTimeout = Runnable {
        if (!isListening || isSpeaking) return@Runnable
        isListening = false
        recognizer?.cancel()

        val partial = lastPartialCommand.trim()
        lastPartialCommand = ""
        if (partial.isNotBlank()) {
            runVoiceCommand(partial)
            return@Runnable
        }

        voiceState = VoiceState.WAITING_FOR_WAKE
        if (followUpListening) {
            followUpListening = false
            updateNotification("Iron чака „Hey Iron“")
            scheduleWakeWordListening(350)
        } else {
            speak("Не чух какво каза.") {
                scheduleWakeWordListening(450)
            }
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

        if (
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (!foregroundStarted) {
            startAsForeground("Iron зарежда офлайн „Hey Iron“…")
            foregroundStarted = true
        }

        initializeRecognizer()
        initializeWakeEngineAsync()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacksAndMessages(null)
        stopWakeWordListening()

        val thread = wakeThread
        if (thread != null && thread !== Thread.currentThread()) {
            try {
                thread.join(700)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }

        if (thread?.isAlive != true) {
            try {
                keywordSpotter?.release()
            } catch (_: Exception) {
                // Native resources may already be released.
            }
        }
        keywordSpotter = null

        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        isListening = false
        isSpeaking = false
        isAiProcessing = false
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

    private fun initializeWakeEngineAsync() {
        if (keywordSpotter != null) {
            scheduleWakeWordListening(100)
            return
        }
        if (wakeEngineLoading || !isRunning) return

        wakeEngineLoading = true
        updateNotification("Iron зарежда офлайн модела за „Hey Iron“…")

        Thread(
            {
                var engine: KeywordSpotter? = null
                var failed = false
                try {
                    engine = KeywordSpotter(
                        assetManager = assets,
                        config = createKeywordSpotterConfig(),
                    )
                } catch (_: Exception) {
                    failed = true
                }

                handler.post {
                    wakeEngineLoading = false
                    if (!isRunning) {
                        try {
                            engine?.release()
                        } catch (_: Exception) {
                            // Service was stopped while the model was loading.
                        }
                        return@post
                    }

                    if (failed || engine == null) {
                        updateNotification("Липсва офлайн моделът за „Hey Iron“")
                        stopSelf()
                        return@post
                    }

                    keywordSpotter = engine
                    updateNotification("Iron е готов • кажи „Hey Iron“")
                    scheduleWakeWordListening(100)
                }
            },
            "HeyIronModelLoader",
        ).apply {
            isDaemon = true
            start()
        }
    }

    private fun createKeywordSpotterConfig(): KeywordSpotterConfig {
        val modelConfig = OnlineModelConfig(
            transducer = OnlineTransducerModelConfig(
                encoder =
                    "$MODEL_DIR/encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx",
                decoder =
                    "$MODEL_DIR/decoder-epoch-13-avg-2-chunk-16-left-64.onnx",
                joiner =
                    "$MODEL_DIR/joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx",
            ),
            tokens = "$MODEL_DIR/tokens.txt",
            numThreads = 2,
            debug = false,
            provider = "cpu",
        )

        return KeywordSpotterConfig(
            featConfig = FeatureConfig(
                sampleRate = WAKE_SAMPLE_RATE,
                featureDim = 80,
                dither = 0.0f,
            ),
            modelConfig = modelConfig,
            maxActivePaths = 4,
            keywordsFile = "$MODEL_DIR/keywords.txt",
            keywordsScore = 3.5f,
            keywordsThreshold = 0.10f,
            numTrailingBlanks = 1,
        )
    }

    private fun scheduleWakeWordListening(delayMillis: Long = 500) {
        handler.removeCallbacks(beginWakeWordListening)
        if (
            isRunning &&
            !isSpeaking &&
            !isListening &&
            !isAiProcessing &&
            voiceState == VoiceState.WAITING_FOR_WAKE &&
            !wakeWordActive
        ) {
            handler.postDelayed(beginWakeWordListening, delayMillis)
        }
    }

    private fun createRecorder(): RecorderHandle? {
        val minimumBufferSize = AudioRecord.getMinBufferSize(
            WAKE_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minimumBufferSize <= 0) return null

        val bufferSizeBytes = maxOf(
            minimumBufferSize * 2,
            WAKE_FRAME_SAMPLES * 2 * 4,
        )
        val sources = listOf(
            MediaRecorder.AudioSource.MIC to "MIC",
            MediaRecorder.AudioSource.VOICE_RECOGNITION to "VOICE_RECOGNITION",
        )

        for ((source, sourceName) in sources) {
            val recorder = try {
                AudioRecord(
                    source,
                    WAKE_SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSizeBytes,
                )
            } catch (_: Exception) {
                null
            } ?: continue

            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                recorder.release()
                continue
            }

            try {
                recorder.startRecording()
            } catch (_: Exception) {
                recorder.release()
                continue
            }

            if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                return RecorderHandle(recorder, sourceName)
            }

            recorder.release()
        }

        return null
    }

    private fun startWakeWordListening() {
        handler.removeCallbacks(beginWakeWordListening)
        if (
            !isRunning ||
            isSpeaking ||
            isListening ||
            wakeWordActive ||
            wakeThread?.isAlive == true ||
            voiceState != VoiceState.WAITING_FOR_WAKE
        ) {
            return
        }

        if (
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            stopSelf()
            return
        }

        val spotter = keywordSpotter
        if (spotter == null) {
            initializeWakeEngineAsync()
            return
        }

        val stream = try {
            spotter.createStream()
        } catch (_: Exception) {
            scheduleWakeWordListening(2_000)
            return
        }
        if (stream.ptr == 0L) {
            stream.release()
            updateNotification("Неуспешно зареждане на фразата „Hey Iron“")
            scheduleWakeWordListening(2_000)
            return
        }

        val recorderHandle = createRecorder()
        if (recorderHandle == null) {
            stream.release()
            updateNotification("Микрофонът не може да бъде стартиран")
            scheduleWakeWordListening(2_000)
            return
        }

        val recorder = recorderHandle.recorder
        keywordStream = stream
        wakeAudioRecord = recorder
        wakeWordActive = true
        updateNotification("Iron чака „Hey Iron“ • ${recorderHandle.sourceName}")

        val worker = Thread(
            {
                var detected = false
                var signalConfirmed = false
                val buffer = ShortArray(WAKE_FRAME_SAMPLES)

                try {
                    while (isRunning && wakeWordActive) {
                        val count = recorder.read(
                            buffer,
                            0,
                            buffer.size,
                            AudioRecord.READ_BLOCKING,
                        )
                        if (count <= 0) continue

                        var squareSum = 0.0
                        val samples = FloatArray(count) { index ->
                            val sample = buffer[index] / 32768.0f
                            squareSum += sample * sample
                            sample
                        }

                        if (!signalConfirmed) {
                            val rms = sqrt(squareSum / count).toFloat()
                            if (rms >= 0.003f) {
                                signalConfirmed = true
                                handler.post {
                                    if (isRunning && wakeWordActive) {
                                        updateNotification(
                                            "Микрофонът работи • кажи „Hey Iron“",
                                        )
                                    }
                                }
                            }
                        }

                        stream.acceptWaveform(
                            samples,
                            sampleRate = WAKE_SAMPLE_RATE,
                        )

                        while (wakeWordActive && spotter.isReady(stream)) {
                            spotter.decode(stream)
                            val keyword = spotter.getResult(stream).keyword
                            if (keyword.isNotBlank()) {
                                spotter.reset(stream)
                                detected = true
                                wakeWordActive = false
                                break
                            }
                        }
                    }
                } catch (_: Exception) {
                    // Android can interrupt AudioRecord when audio focus changes.
                } finally {
                    try {
                        if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                            recorder.stop()
                        }
                    } catch (_: Exception) {
                        // Recorder may already be stopped.
                    }
                    recorder.release()

                    try {
                        stream.release()
                    } catch (_: Exception) {
                        // Stream may already be released after a native failure.
                    }

                    val finishedThread = Thread.currentThread()
                    handler.post {
                        if (wakeAudioRecord === recorder) wakeAudioRecord = null
                        if (keywordStream === stream) keywordStream = null
                        if (wakeThread === finishedThread) wakeThread = null
                        wakeWordActive = false

                        if (
                            detected &&
                            isRunning &&
                            !isSpeaking &&
                            voiceState == VoiceState.WAITING_FOR_WAKE
                        ) {
                            onWakeWordDetected()
                        } else if (isRunning) {
                            scheduleWakeWordListening(800)
                        }
                    }
                }
            },
            "HeyIronKeywordSpotter",
        ).apply {
            isDaemon = true
        }

        wakeThread = worker
        worker.start()
    }

    private fun stopWakeWordListening() {
        handler.removeCallbacks(beginWakeWordListening)
        wakeWordActive = false

        val recorder = wakeAudioRecord
        wakeAudioRecord = null
        try {
            if (recorder?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                recorder.stop()
            }
        } catch (_: Exception) {
            // Stopping AudioRecord unblocks the worker thread.
        }

        wakeThread?.interrupt()
    }

    private fun onWakeWordDetected() {
        if (
            !isRunning ||
            isSpeaking ||
            voiceState != VoiceState.WAITING_FOR_WAKE
        ) {
            return
        }

        followUpListening = false
        lastPartialCommand = ""
        voiceState = VoiceState.WAITING_FOR_COMMAND
        updateNotification("„Hey Iron“ е разпознат • слушам те")
        speak("Слушам") {
            scheduleCommandListening(220)
        }
    }

    private fun startListening() {
        handler.removeCallbacks(beginSpeechRecognition)
        handler.removeCallbacks(recognitionTimeout)
        if (
            !isRunning ||
            isSpeaking ||
            isListening ||
            voiceState != VoiceState.WAITING_FOR_COMMAND
        ) {
            return
        }

        stopWakeWordListening()
        initializeRecognizer()
        val currentRecognizer = recognizer ?: run {
            voiceState = VoiceState.WAITING_FOR_WAKE
            scheduleWakeWordListening(1_500)
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
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS,
                1_500L,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                2_800L,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                4_500L,
            )
        }

        try {
            lastPartialCommand = ""
            isListening = true
            updateNotification(
                if (followUpListening) {
                    "Iron е в разговор • говори спокойно"
                } else {
                    "Iron слуша • можеш да говориш по-дълго"
                },
            )
            currentRecognizer.startListening(recognitionIntent)
            handler.postDelayed(recognitionTimeout, 35_000)
        } catch (_: Exception) {
            isListening = false
            voiceState = VoiceState.WAITING_FOR_WAKE
            resetRecognizer()
            speak("Не успях да включа микрофона.") {
                scheduleWakeWordListening(1_200)
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

    private fun resetRecognizer() {
        recognizer?.destroy()
        recognizer = null
        initializeRecognizer()
    }

    private fun processRecognition(results: Bundle?, isFinal: Boolean) {
        if (isSpeaking || voiceState != VoiceState.WAITING_FOR_COMMAND) return

        val phrases = results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            .orEmpty()
            .map { it.trim() }
            .filter { it.isNotBlank() }

        if (phrases.isEmpty()) {
            if (isFinal) {
                isListening = false
                voiceState = VoiceState.WAITING_FOR_WAKE
                if (followUpListening) {
                    followUpListening = false
                    scheduleWakeWordListening(350)
                } else {
                    speak("Не чух какво каза.") {
                        scheduleWakeWordListening(450)
                    }
                }
            }
            return
        }

        lastPartialCommand = phrases.first()
        if (isFinal) {
            isListening = false
            val finalCommand = lastPartialCommand
            lastPartialCommand = ""
            runVoiceCommand(finalCommand)
        }
    }

    private fun runVoiceCommand(command: String) {
        val originalCommand = command.trim()
        val normalizedCommand = normalize(originalCommand)

        if (
            normalizedCommand == "стоп" ||
            normalizedCommand == "край" ||
            normalizedCommand == "стига" ||
            normalizedCommand.contains("спри разговора") ||
            normalizedCommand.contains("това е всичко")
        ) {
            followUpListening = false
            voiceState = VoiceState.WAITING_FOR_WAKE
            speak("Добре.") {
                scheduleWakeWordListening(350)
            }
            return
        }

        if (
            normalizedCommand == "нова тема" ||
            normalizedCommand.contains("започни нов разговор")
        ) {
            aiRouter.clearConversation()
            finishVoiceTurn(
                reply = "Добре, започваме начисто. Кажи.",
                continueConversation = true,
            )
            return
        }

        if (!aiRouter.hasApiKey()) {
            val localReply = executeCommand(normalizedCommand)
            val reply = if (localReply == "Не разбрах командата. Опитай пак.") {
                "За свободния AI режим отвори приложението и запази Gemini API ключа."
            } else {
                localReply
            }
            finishVoiceTurn(reply, continueConversation = false)
            return
        }

        voiceState = VoiceState.WAITING_FOR_WAKE
        isAiProcessing = true
        updateNotification("Iron мисли с AI…")

        Thread(
            {
                val result = try {
                    Result.success(aiRouter.route(originalCommand))
                } catch (error: Exception) {
                    Result.failure(error)
                }

                handler.post {
                    isAiProcessing = false
                    if (!isRunning) return@post

                    val decision = result.getOrNull()
                    if (decision != null) {
                        val reply = executeAiDecision(decision)
                        finishVoiceTurn(
                            reply = reply,
                            continueConversation = decision.action == "reply",
                        )
                        return@post
                    }

                    val localReply = executeCommand(normalizedCommand)
                    val error = result.exceptionOrNull()
                    val reply = when {
                        localReply != "Не разбрах командата. Опитай пак." -> localReply
                        error is GeminiVoiceRouter.MissingApiKeyException ->
                            "За свободния AI режим отвори приложението и запази Gemini API ключа."
                        error is GeminiVoiceRouter.AiUnavailableException ->
                            error.message ?: "AI временно не отговаря. Опитай пак."
                        else -> "AI временно не отговаря. Опитай пак."
                    }
                    finishVoiceTurn(reply, continueConversation = false)
                }
            },
            "IronAiRouter",
        ).apply {
            isDaemon = true
            start()
        }
    }

    private fun finishVoiceTurn(
        reply: String,
        continueConversation: Boolean,
    ) {
        val spokenReply = reply.ifBlank { "Готово." }
        followUpListening = continueConversation

        if (continueConversation) {
            voiceState = VoiceState.WAITING_FOR_COMMAND
            updateNotification("Iron отговаря • после можеш да продължиш")
            speak(spokenReply) {
                if (!isRunning) return@speak
                voiceState = VoiceState.WAITING_FOR_COMMAND
                updateNotification("Iron е в разговор • говори спокойно")
                scheduleCommandListening(650)
            }
        } else {
            voiceState = VoiceState.WAITING_FOR_WAKE
            speak(spokenReply) {
                scheduleWakeWordListening(450)
            }
        }
    }

    private fun executeAiDecision(decision: GeminiVoiceRouter.Decision): String {
        return try {
            when (decision.action) {
                "reply" -> decision.reply
                "youtube" -> {
                    launchPackage("com.google.android.youtube")
                    decision.reply.ifBlank { "Отварям YouTube." }
                }
                "youtube_search" -> {
                    val query = decision.argument.ifBlank { return "Какво да търся в YouTube?" }
                    launch(
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("https://www.youtube.com/results?search_query=${Uri.encode(query)}"),
                        ),
                    )
                    decision.reply.ifBlank { "Търся в YouTube." }
                }
                "spotify" -> {
                    launchPackageOrUri(
                        packageName = "com.spotify.music",
                        fallbackUri = "https://open.spotify.com",
                    )
                    decision.reply.ifBlank { "Отварям Spotify." }
                }
                "spotify_search" -> {
                    val query = decision.argument.ifBlank { return "Какво да търся в Spotify?" }
                    val spotifyIntent = Intent(
                        Intent.ACTION_VIEW,
                        Uri.parse("spotify:search:${Uri.encode(query)}"),
                    ).apply {
                        setPackage("com.spotify.music")
                    }
                    if (spotifyIntent.resolveActivity(packageManager) != null) {
                        launch(spotifyIntent)
                    } else {
                        launch(
                            Intent(
                                Intent.ACTION_VIEW,
                                Uri.parse("https://open.spotify.com/search/${Uri.encode(query)}"),
                            ),
                        )
                    }
                    decision.reply.ifBlank { "Търся в Spotify." }
                }
                "chrome" -> {
                    launchPackage("com.android.chrome")
                    decision.reply.ifBlank { "Отварям браузъра." }
                }
                "web_search" -> {
                    val query = decision.argument.ifBlank { return "Какво да потърся?" }
                    launch(
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("https://www.google.com/search?q=${Uri.encode(query)}"),
                        ).apply {
                            setPackage("com.android.chrome")
                        },
                    )
                    decision.reply.ifBlank { "Търся в интернет." }
                }
                "camera" -> {
                    launch(Intent("android.media.action.IMAGE_CAPTURE"))
                    decision.reply.ifBlank { "Отварям камерата." }
                }
                "gallery" -> {
                    launch(
                        Intent(Intent.ACTION_PICK).apply {
                            type = "image/*"
                        },
                    )
                    decision.reply.ifBlank { "Отварям снимките." }
                }
                "maps" -> {
                    openMaps("")
                    decision.reply.ifBlank { "Отварям картите." }
                }
                "maps_search" -> {
                    val query = decision.argument.ifBlank { return "Кое място да потърся?" }
                    openMaps(query)
                    decision.reply.ifBlank { "Търся мястото в картите." }
                }
                "alarms" -> {
                    launch(Intent(AlarmClock.ACTION_SHOW_ALARMS))
                    decision.reply.ifBlank { "Отварям алармите." }
                }
                "set_alarm" -> {
                    setAlarm(decision.argument)
                    decision.reply.ifBlank { "Алармата е подготвена." }
                }
                "set_timer" -> {
                    setTimer(decision.argument)
                    decision.reply.ifBlank { "Таймерът е стартиран." }
                }
                "calendar" -> {
                    launch(
                        Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_APP_CALENDAR)
                        },
                    )
                    decision.reply.ifBlank { "Отварям календара." }
                }
                "dialer" -> {
                    launch(Intent(Intent.ACTION_DIAL))
                    decision.reply.ifBlank { "Отварям телефона." }
                }
                "dial_number" -> {
                    val number = decision.argument.filter { it.isDigit() || it == '+' }
                    if (number.isBlank()) return "Не разбрах телефонния номер."
                    launch(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")))
                    decision.reply.ifBlank { "Подготвям номера за набиране." }
                }
                "contacts" -> {
                    launch(
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("content://contacts/people"),
                        ),
                    )
                    decision.reply.ifBlank { "Отварям контактите." }
                }
                "email" -> {
                    launch(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")))
                    decision.reply.ifBlank { "Отварям имейла." }
                }
                "messages" -> {
                    launch(
                        Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_APP_MESSAGING)
                        },
                    )
                    decision.reply.ifBlank { "Отварям съобщенията." }
                }
                "calculator" -> {
                    launch(
                        Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_APP_CALCULATOR)
                        },
                    )
                    decision.reply.ifBlank { "Отварям калкулатора." }
                }
                "play_store" -> {
                    val query = decision.argument.ifBlank { return "Кое приложение да потърся?" }
                    launch(
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("market://search?q=${Uri.encode(query)}"),
                        ),
                    )
                    decision.reply.ifBlank { "Търся приложението." }
                }
                "bluetooth" -> {
                    launch(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                    decision.reply.ifBlank { "Отварям Bluetooth." }
                }
                "wifi" -> {
                    launch(Intent(Settings.ACTION_WIFI_SETTINGS))
                    decision.reply.ifBlank { "Отварям Wi-Fi." }
                }
                "settings" -> {
                    launch(Intent(Settings.ACTION_SETTINGS))
                    decision.reply.ifBlank { "Отварям настройките." }
                }
                "flash_on" -> {
                    setFlashlight(true)
                    decision.reply.ifBlank { "Фенерчето е включено." }
                }
                "flash_off" -> {
                    setFlashlight(false)
                    decision.reply.ifBlank { "Фенерчето е изключено." }
                }
                "volume_up" -> {
                    adjustVolume(AudioManager.ADJUST_RAISE)
                    decision.reply.ifBlank { "Звукът е увеличен." }
                }
                "volume_down" -> {
                    adjustVolume(AudioManager.ADJUST_LOWER)
                    decision.reply.ifBlank { "Звукът е намален." }
                }
                "music_mode" -> {
                    sendAutomateCommand("music_mode_420")
                    decision.reply.ifBlank { "Музикалният режим е включен." }
                }
                "night_mode" -> {
                    adjustVolume(AudioManager.ADJUST_LOWER)
                    adjustVolume(AudioManager.ADJUST_LOWER)
                    decision.reply.ifBlank { "Нощният режим е включен." }
                }
                "studio" -> {
                    openIronSection(1)
                    decision.reply.ifBlank { "Отварям Rap Studio." }
                }
                "chat" -> {
                    openIronSection(3)
                    decision.reply.ifBlank { "Отварям AI чата." }
                }
                "songs" -> {
                    openIronSection(2)
                    decision.reply.ifBlank { "Отварям песните." }
                }
                "home" -> {
                    openIronSection(0)
                    decision.reply.ifBlank { "Отварям началния екран." }
                }
                "automate" -> {
                    val macro = decision.argument.trim()
                    if (macro.isBlank()) return "Кажи името на Automate командата."
                    sendAutomateCommand(macro)
                    decision.reply.ifBlank { "Командата е изпратена." }
                }
                else -> decision.reply.ifBlank { "Не разбрах. Опитай пак." }
            }
        } catch (_: SecurityException) {
            "Липсва нужно разрешение за това действие."
        } catch (_: Exception) {
            "Това действие не е достъпно на телефона."
        }
    }

    private fun launchPackageOrUri(
        packageName: String,
        fallbackUri: String,
    ) {
        val packageIntent = packageManager.getLaunchIntentForPackage(packageName)
        if (packageIntent != null) {
            launch(packageIntent)
        } else {
            launch(Intent(Intent.ACTION_VIEW, Uri.parse(fallbackUri)))
        }
    }

    private fun setAlarm(argument: String) {
        val parts = argument.split("|", limit = 2)
        val timeParts = parts.firstOrNull().orEmpty().split(":", limit = 2)
        val hour = timeParts.getOrNull(0)?.toIntOrNull()
            ?: throw IllegalArgumentException("Missing alarm hour")
        val minute = timeParts.getOrNull(1)?.toIntOrNull()
            ?: throw IllegalArgumentException("Missing alarm minute")
        val label = parts.getOrNull(1).orEmpty().trim()

        launch(
            Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour.coerceIn(0, 23))
                putExtra(AlarmClock.EXTRA_MINUTES, minute.coerceIn(0, 59))
                if (label.isNotBlank()) {
                    putExtra(AlarmClock.EXTRA_MESSAGE, label.take(100))
                }
                putExtra(AlarmClock.EXTRA_SKIP_UI, false)
            },
        )
    }

    private fun setTimer(argument: String) {
        val parts = argument.split("|", limit = 2)
        val seconds = parts.firstOrNull()?.trim()?.toIntOrNull()
            ?: throw IllegalArgumentException("Missing timer duration")
        val label = parts.getOrNull(1).orEmpty().trim()

        launch(
            Intent(AlarmClock.ACTION_SET_TIMER).apply {
                putExtra(AlarmClock.EXTRA_LENGTH, seconds.coerceIn(1, 86_400))
                if (label.isNotBlank()) {
                    putExtra(AlarmClock.EXTRA_MESSAGE, label.take(100))
                }
                putExtra(AlarmClock.EXTRA_SKIP_UI, false)
            },
        )
    }

    private fun openMaps(query: String) {
        val encoded = Uri.encode(query)
        val intent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse(if (query.isBlank()) "geo:0,0?q=" else "geo:0,0?q=$encoded"),
        ).apply {
            setPackage("com.google.android.apps.maps")
        }
        if (intent.resolveActivity(packageManager) == null) {
            intent.setPackage(null)
        }
        launch(intent)
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
        } catch (_: SecurityException) {
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
        if (
            ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) !=
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

    private fun normalize(value: String): String {
        return value
            .lowercase(Locale("bg", "BG"))
            .replace(Regex("[^a-zа-я0-9+\\- ]", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun speak(text: String, onFinished: () -> Unit) {
        handler.removeCallbacks(beginSpeechRecognition)
        handler.removeCallbacks(beginWakeWordListening)
        handler.removeCallbacks(recognitionTimeout)
        stopWakeWordListening()
        isListening = false
        isSpeaking = true
        recognizer?.cancel()
        afterSpeech = onFinished

        if (!ttsReady) {
            handler.postDelayed(
                {
                    isSpeaking = false
                    afterSpeech?.invoke()
                    afterSpeech = null
                },
                250,
            )
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
            description = "Показва, когато Iron слуша офлайн за „Hey Iron“."
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
        if (!isRunning || !foregroundStarted) return

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

    override fun onBeginningOfSpeech() {
        handler.removeCallbacks(recognitionTimeout)
        handler.postDelayed(recognitionTimeout, 35_000)
        updateNotification("Iron те слуша • довърши спокойно")
    }
    override fun onRmsChanged(rmsdB: Float) = Unit
    override fun onBufferReceived(buffer: ByteArray?) = Unit

    override fun onEndOfSpeech() {
        updateNotification("Iron обработва казаното…")
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
            error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY ||
            error == SpeechRecognizer.ERROR_AUDIO ||
            error == SpeechRecognizer.ERROR_CLIENT ||
            error == SpeechRecognizer.ERROR_SERVER_DISCONNECTED
        ) {
            resetRecognizer()
        }

        val partial = lastPartialCommand.trim()
        lastPartialCommand = ""
        if (
            partial.isNotBlank() &&
            (error == SpeechRecognizer.ERROR_NO_MATCH ||
                error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT)
        ) {
            runVoiceCommand(partial)
            return
        }

        voiceState = VoiceState.WAITING_FOR_WAKE

        if (
            error == SpeechRecognizer.ERROR_NO_MATCH ||
            error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
        ) {
            if (followUpListening) {
                followUpListening = false
                updateNotification("Iron чака „Hey Iron“")
                scheduleWakeWordListening(350)
            } else {
                speak("Не чух какво каза.") {
                    scheduleWakeWordListening(450)
                }
            }
            return
        }

        followUpListening = false
        scheduleWakeWordListening(
            when (error) {
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> 1_200
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
        if (lastPartialCommand.isNotBlank()) {
            handler.removeCallbacks(recognitionTimeout)
            handler.postDelayed(recognitionTimeout, 16_000)
        }
    }

    override fun onEvent(eventType: Int, params: Bundle?) = Unit
}
