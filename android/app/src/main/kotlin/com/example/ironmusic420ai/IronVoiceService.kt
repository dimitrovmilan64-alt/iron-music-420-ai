package com.example.ironmusic420ai

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.SearchManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
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
import android.util.Log
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
        const val ACTION_PAUSE_WAKE = "com.example.ironmusic420ai.PAUSE_IRON_WAKE"
        const val ACTION_RESUME_WAKE = "com.example.ironmusic420ai.RESUME_IRON_WAKE"
        const val VOICE_PREFS = "iron_voice_preferences"
        const val KEY_VOICE_ENABLED = "voice_enabled"

        @Volatile
        var isRunning = false
            private set

        private const val CHANNEL_ID = "iron_voice_service_silent_v3"
        private const val NOTIFICATION_ID = 2420
        private const val WAKE_SAMPLE_RATE = 16_000
        private const val WAKE_FRAME_SAMPLES = 1_600
        private const val WAKE_MIN_RMS = 0.006f
        private const val MIN_WAKE_VOICED_FRAMES = 2
        private const val COMMAND_TIMEOUT_MS = 30_000L
        private const val MIN_SPEECH_WATCHDOG_MS = 5_000L
        private const val MAX_SPEECH_WATCHDOG_MS = 135_000L
        private const val LOG_TAG = "IronVoice"
        private const val MODEL_DIR =
            "sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"

        fun isMicrophoneCaptureActive(): Boolean =
            VoiceCaptureRegistry.isAnyCaptureActive()
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
    private val captureOwner = Any()

    @Volatile
    private var serviceActive = false

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
    private var activeUtteranceId: String? = null
    private var foregroundStarted = false
    private var voiceState = VoiceState.WAITING_FOR_WAKE
    private var afterSpeech: (() -> Unit)? = null
    private var ignoreNextRecognitionError = false
    private var capturePauseCount = 0
    private var aiRequestGeneration = 0

    @Volatile
    private var pausedForChatSpeech = false

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
    private val finishSpeechWatchdog = Runnable {
        if (!isSpeaking) return@Runnable
        try {
            textToSpeech?.stop()
        } catch (_: Exception) {
            // The callback below still releases the voice state.
        }
        finishSpeech()
    }
    private val clearRecognitionCancellation = Runnable {
        if (!ignoreNextRecognitionError) return@Runnable
        ignoreNextRecognitionError = false
        setSpeechCaptureActive(false)
        try {
            recognizer?.destroy()
        } catch (_: Exception) {
            // A recognizer that does not return a cancel callback must be replaced.
        }
        recognizer = null
        if (!pausedForChatSpeech && serviceActive) initializeRecognizer()
    }
    private val recognitionTimeout = Runnable {
        if (!isListening || isSpeaking) return@Runnable
        isListening = false
        expectRecognitionCancellation()
        try {
            recognizer?.cancel()
        } catch (_: Exception) {
            consumeExpectedRecognitionCancellation()
            setSpeechCaptureActive(false)
            resetRecognizer()
        }
        endConversation()
        voiceState = VoiceState.WAITING_FOR_WAKE
        updateNotification("Iron чака „Hey Iron“")
        scheduleWakeWordListening(450)
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        textToSpeech = try {
            TextToSpeech(this, this)
        } catch (_: Exception) {
            null
        }
        serviceActive = true
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                getSharedPreferences(VOICE_PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(KEY_VOICE_ENABLED, false)
                    .apply()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_PAUSE_WAKE -> {
                pauseForChatSpeech()
                return START_STICKY
            }
            ACTION_RESUME_WAKE -> {
                resumeAfterChatSpeech()
                return START_STICKY
            }
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
        serviceActive = false
        isRunning = false
        aiRequestGeneration++
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

        val recognizerToDestroy = recognizer
        recognizer = null
        try {
            recognizerToDestroy?.cancel()
        } catch (_: Exception) {
            // Continue releasing the rest of the service.
        }
        try {
            recognizerToDestroy?.destroy()
        } catch (_: Exception) {
            // Continue releasing the rest of the service.
        }
        setSpeechCaptureActive(false)
        if (thread?.isAlive != true) setWakeCaptureActive(false)
        activeUtteranceId = null
        val ttsToDestroy = textToSpeech
        textToSpeech = null
        try {
            ttsToDestroy?.stop()
        } catch (_: Exception) {
            // Continue releasing the foreground service.
        }
        try {
            ttsToDestroy?.shutdown()
        } catch (_: Exception) {
            // Continue releasing the foreground service.
        }
        isListening = false
        isSpeaking = false
        isAiProcessing = false
        foregroundStarted = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun pauseForChatSpeech() {
        capturePauseCount++
        if (pausedForChatSpeech) return
        pausedForChatSpeech = true
        aiRequestGeneration++
        handler.removeCallbacks(beginWakeWordListening)
        handler.removeCallbacks(beginSpeechRecognition)
        handler.removeCallbacks(recognitionTimeout)
        handler.removeCallbacks(finishSpeechWatchdog)
        afterSpeech = null
        activeUtteranceId = null
        isAiProcessing = false
        val currentRecognizer = recognizer
        recognizer = null
        try {
            currentRecognizer?.cancel()
        } catch (_: Exception) {
            // The recognizer may already be stopping.
        }
        try {
            currentRecognizer?.destroy()
        } catch (_: Exception) {
            // Destroy guarantees that chat dictation can acquire the microphone.
        }
        isListening = false
        setSpeechCaptureActive(false)
        ignoreNextRecognitionError = false
        handler.removeCallbacks(clearRecognitionCancellation)
        if (isSpeaking) {
            try {
                textToSpeech?.stop()
            } catch (_: Exception) {
                // TTS may already be complete.
            }
        }
        isSpeaking = false
        voiceState = VoiceState.WAITING_FOR_WAKE
        stopWakeWordListening()
        updateNotification("Iron е активен • диктовка в приложението")
    }

    private fun resumeAfterChatSpeech() {
        if (!pausedForChatSpeech) return
        if (capturePauseCount > 0) capturePauseCount--
        if (capturePauseCount > 0) return
        pausedForChatSpeech = false
        if (!serviceActive) return
        voiceState = VoiceState.WAITING_FOR_WAKE
        updateNotification("Iron е готов • кажи „Hey Iron“")
        scheduleWakeWordListening(650)
    }

    private fun initializeRecognizer() {
        if (recognizer != null) return
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            updateNotification("На телефона няма услуга за гласово разпознаване")
            return
        }

        recognizer = try {
            SpeechRecognizer.createSpeechRecognizer(this).also {
                it.setRecognitionListener(this)
            }
        } catch (_: Exception) {
            updateNotification("Гласовият разпознавател не може да бъде стартиран")
            null
        }
    }

    private fun expectRecognitionCancellation() {
        ignoreNextRecognitionError = true
        handler.removeCallbacks(clearRecognitionCancellation)
        handler.postDelayed(clearRecognitionCancellation, 1_000L)
    }

    private fun consumeExpectedRecognitionCancellation(): Boolean {
        if (!ignoreNextRecognitionError) return false
        ignoreNextRecognitionError = false
        handler.removeCallbacks(clearRecognitionCancellation)
        return true
    }

    private fun setWakeCaptureActive(active: Boolean) {
        VoiceCaptureRegistry.setWakeActive(captureOwner, active)
    }

    private fun setSpeechCaptureActive(active: Boolean) {
        VoiceCaptureRegistry.setSpeechActive(captureOwner, active)
    }

    private fun isSpeechCaptureActive(): Boolean =
        VoiceCaptureRegistry.isSpeechActive(captureOwner)

    private fun initializeWakeEngineAsync() {
        if (keywordSpotter != null) {
            scheduleWakeWordListening(100)
            return
        }
        if (wakeEngineLoading || !serviceActive) return

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
                    if (!serviceActive) {
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
            keywordsScore = 1.5f,
            keywordsThreshold = 0.25f,
            numTrailingBlanks = 1,
        )
    }

    private fun scheduleWakeWordListening(delayMillis: Long = 500) {
        handler.removeCallbacks(beginWakeWordListening)
        if (
            serviceActive &&
            !pausedForChatSpeech &&
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
            !serviceActive ||
            pausedForChatSpeech ||
            isSpeaking ||
            isListening ||
            wakeWordActive ||
            wakeThread?.isAlive == true ||
            voiceState != VoiceState.WAITING_FOR_WAKE
        ) {
            return
        }

        if (VoiceCaptureRegistry.isAnyCaptureActive()) {
            scheduleWakeWordListening(180)
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
        setWakeCaptureActive(true)
        updateNotification("Iron чака „Hey Iron“ • ${recorderHandle.sourceName}")

        val worker = Thread(
            {
                var detected = false
                var signalConfirmed = false
                var voicedFrameCount = 0
                var detectedKeyword = ""
                val buffer = ShortArray(WAKE_FRAME_SAMPLES)

                try {
                    while (serviceActive && wakeWordActive) {
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

                        val rms = sqrt(squareSum / count).toFloat()
                        voicedFrameCount = if (rms >= WAKE_MIN_RMS) {
                            (voicedFrameCount + 1).coerceAtMost(10)
                        } else {
                            (voicedFrameCount - 1).coerceAtLeast(0)
                        }
                        if (!signalConfirmed && voicedFrameCount >= MIN_WAKE_VOICED_FRAMES) {
                            signalConfirmed = true
                            handler.post {
                                if (serviceActive && wakeWordActive) {
                                    updateNotification(
                                        "Микрофонът работи • кажи „Hey Iron“",
                                    )
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
                                if (voicedFrameCount < MIN_WAKE_VOICED_FRAMES) {
                                    Log.i(LOG_TAG, "wake_ignored reason=low_signal")
                                    continue
                                }
                                detectedKeyword = keyword
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
                    setWakeCaptureActive(false)
                    if (!serviceActive) {
                        try {
                            spotter.release()
                        } catch (_: Exception) {
                            // The service may have released the engine after joining this thread.
                        }
                        if (keywordSpotter === spotter) keywordSpotter = null
                    }

                    val finishedThread = Thread.currentThread()
                    handler.post {
                        if (wakeAudioRecord === recorder) wakeAudioRecord = null
                        if (keywordStream === stream) keywordStream = null
                        if (wakeThread === finishedThread) wakeThread = null
                        wakeWordActive = false

                        if (
                            detected &&
                            serviceActive &&
                            !pausedForChatSpeech &&
                            !isSpeaking &&
                            voiceState == VoiceState.WAITING_FOR_WAKE
                        ) {
                            Log.i(LOG_TAG, "wake_detected keyword=$detectedKeyword")
                            onWakeWordDetected()
                        } else if (serviceActive && !pausedForChatSpeech) {
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
            !serviceActive ||
            pausedForChatSpeech ||
            isSpeaking ||
            voiceState != VoiceState.WAITING_FOR_WAKE
        ) {
            return
        }

        beginConversation()
        voiceState = VoiceState.WAITING_FOR_COMMAND
        updateNotification("„Hey Iron“ е разпознат • разговорът започна")
        speak("Слушам") {
            scheduleCommandListening(260)
        }
    }

    private fun startListening() {
        handler.removeCallbacks(beginSpeechRecognition)
        handler.removeCallbacks(recognitionTimeout)
        if (
            !serviceActive ||
            pausedForChatSpeech ||
            isSpeaking ||
            isListening ||
            voiceState != VoiceState.WAITING_FOR_COMMAND
        ) {
            return
        }

        if (ignoreNextRecognitionError) {
            scheduleCommandListening(120)
            return
        }

        if (VoiceCaptureRegistry.isAnyCaptureActive()) {
            scheduleCommandListening(120)
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
                3_500L,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                5_500L,
            )
        }

        try {
            isListening = true
            setSpeechCaptureActive(true)
            updateNotification("Iron слуша командата")
            Log.i(LOG_TAG, "speech_start")
            currentRecognizer.startListening(recognitionIntent)
            handler.postDelayed(recognitionTimeout, COMMAND_TIMEOUT_MS)
        } catch (_: Exception) {
            isListening = false
            setSpeechCaptureActive(false)
            voiceState = VoiceState.WAITING_FOR_WAKE
            resetRecognizer()
            speak("Не успях да включа микрофона.") {
                scheduleWakeWordListening(1_200)
            }
        }
    }

    private fun beginConversation() {
        aiRouter.resetConversation()
    }

    private fun endConversation() {
        aiRouter.resetConversation()
    }

    private fun continueConversationOrWake(delayMillis: Long = 650) {
        // ColorOS/Realme emits an audible system cue every time Android's
        // SpeechRecognizer starts or stops. Keep commands one-shot and return
        // to the silent offline wake-word recorder after each answer.
        endConversation()
        voiceState = VoiceState.WAITING_FOR_WAKE
        updateNotification("Iron чака „Hey Iron“")
        scheduleWakeWordListening(delayMillis)
    }

    private fun isStopConversationCommand(command: String): Boolean {
        return command == "стоп" ||
            command == "край" ||
            command.contains("спри разговора") ||
            command.contains("приключи разговора") ||
            command.contains("стига толкова") ||
            command.contains("чао айрън")
    }

    private fun scheduleCommandListening(delayMillis: Long = 250) {
        handler.removeCallbacks(beginSpeechRecognition)
        if (
            serviceActive &&
            !pausedForChatSpeech &&
            !isSpeaking &&
            !isAiProcessing &&
            voiceState == VoiceState.WAITING_FOR_COMMAND
        ) {
            handler.postDelayed(beginSpeechRecognition, delayMillis)
        }
    }

    private fun resetRecognizer() {
        val recognizerToDestroy = recognizer
        recognizer = null
        try {
            recognizerToDestroy?.destroy()
        } catch (_: Exception) {
            // A replacement recognizer can still be created.
        }
        setSpeechCaptureActive(false)
        if (serviceActive && !pausedForChatSpeech) initializeRecognizer()
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
                endConversation()
                voiceState = VoiceState.WAITING_FOR_WAKE
                updateNotification("Iron чака „Hey Iron“")
                scheduleWakeWordListening(450)
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
        val originalCommand = command.trim()
        val normalizedCommand = normalize(originalCommand)

        if (isStopConversationCommand(normalizedCommand)) {
            endConversation()
            speak("Добре.") {
                voiceState = VoiceState.WAITING_FOR_WAKE
                scheduleWakeWordListening(450)
            }
            return
        }

        val localCommand = LocalVoiceCommandParser.parse(originalCommand)
        if (localCommand != null) {
            Log.i(LOG_TAG, "command_route source=local action=${localCommand.action}")
            val reply = executeLocalVoiceCommand(localCommand)
            speak(reply) {
                continueConversationOrWake(650)
            }
            return
        }

        if (!aiRouter.hasApiKey()) {
            val localReply = executeCommand(normalizedCommand)
            val reply = if (localReply == "Не разбрах командата. Опитай пак.") {
                "За свободния AI режим отвори приложението и добави Gemini или резервен AI ключ."
            } else {
                localReply
            }
            speak(reply) {
                continueConversationOrWake(650)
            }
            return
        }

        isAiProcessing = true
        val requestGeneration = ++aiRequestGeneration
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
                    if (
                        !serviceActive ||
                        pausedForChatSpeech ||
                        requestGeneration != aiRequestGeneration
                    ) {
                        return@post
                    }

                    val decision = result.getOrNull()
                    if (decision != null) {
                        val reply = executeAiDecision(decision)
                        speak(reply) {
                            continueConversationOrWake(650)
                        }
                        return@post
                    }

                    val localReply = executeCommand(normalizedCommand)
                    val error = result.exceptionOrNull()
                    val reply = when {
                        localReply != "Не разбрах командата. Опитай пак." -> localReply
                        error is GeminiVoiceRouter.MissingApiKeyException ->
                            "За свободния AI режим отвори приложението и добави Gemini или резервен AI ключ."
                        error is GeminiVoiceRouter.AiUnavailableException ->
                            error.message ?: "AI временно не отговаря. Опитай пак."
                        else -> "AI временно не отговаря. Опитай пак."
                    }
                    speak(reply) {
                        continueConversationOrWake(900)
                    }
                }
            },
            "IronAiRouter",
        ).apply {
            isDaemon = true
            start()
        }
    }

    private fun executeLocalVoiceCommand(command: LocalVoiceCommand): String {
        return when (command.action) {
            "studio_generate" -> {
                openIronStudioRequest(
                    prompt = command.argument,
                    outputType = command.studioOutputType,
                )
                command.reply.ifBlank { "Отварям Рап студио." }
            }
            "clarify" -> command.reply.ifBlank { "Кажи какво точно да направя." }
            else -> executeAiDecision(
                GeminiVoiceRouter.Decision(
                    action = command.action,
                    argument = command.argument,
                    reply = command.reply,
                ),
            )
        }
    }

    private fun executeAiDecision(decision: GeminiVoiceRouter.Decision): String {
        return try {
            Log.i(LOG_TAG, "command_execute action=${decision.action}")
            when (decision.action) {
                "reply" -> decision.reply
                "youtube" -> {
                    launchPackage("com.google.android.youtube")
                    decision.reply.ifBlank { "Отварям YouTube." }
                }
                "youtube_search" -> {
                    val query = decision.argument.ifBlank { return "Какво да търся в YouTube?" }
                    openYouTubeSearch(query)
                    decision.reply.ifBlank { "Търся в YouTube." }
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

        FlashlightController.setEnabled(this, enabled)
    }

    private fun openYouTubeSearch(query: String) {
        val cleanQuery = query.trim()
        if (cleanQuery.isBlank()) throw IllegalArgumentException("Missing YouTube query")

        Log.i(LOG_TAG, "youtube_search queryLength=${cleanQuery.length}")
        val appSearchIntent = Intent(Intent.ACTION_SEARCH).apply {
            setPackage("com.google.android.youtube")
            putExtra(SearchManager.QUERY, cleanQuery)
        }
        if (appSearchIntent.resolveActivity(packageManager) != null) {
            launch(appSearchIntent)
            return
        }

        val resultsUri = Uri.parse(
            "https://www.youtube.com/results?search_query=${Uri.encode(cleanQuery)}",
        )
        val deepLinkIntent = Intent(Intent.ACTION_VIEW, resultsUri).apply {
            setPackage("com.google.android.youtube")
        }
        if (deepLinkIntent.resolveActivity(packageManager) == null) {
            deepLinkIntent.setPackage(null)
        }
        launch(deepLinkIntent)
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

    private fun openIronStudioRequest(prompt: String, outputType: String) {
        launch(
            Intent(this, MainActivity::class.java).apply {
                putExtra("iron_section", 1)
                putExtra("iron_studio_prompt", prompt.trim())
                putExtra("iron_studio_output_type", outputType.trim())
                putExtra("iron_studio_auto_generate", true)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
        )
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
        handler.removeCallbacks(finishSpeechWatchdog)
        stopWakeWordListening()
        val wasListening = isListening || isSpeechCaptureActive()
        isListening = false
        isSpeaking = true
        if (wasListening) {
            expectRecognitionCancellation()
            try {
                recognizer?.cancel()
            } catch (_: Exception) {
                setSpeechCaptureActive(false)
            }
        }
        val utteranceId = "iron_${System.currentTimeMillis()}"
        activeUtteranceId = utteranceId
        afterSpeech = onFinished

        if (!ttsReady || text.isBlank()) {
            handler.postDelayed(
                {
                    finishSpeech(utteranceId)
                },
                250,
            )
            return
        }

        val result = textToSpeech?.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            utteranceId,
        ) ?: TextToSpeech.ERROR
        if (result == TextToSpeech.ERROR) {
            finishSpeech(utteranceId)
            return
        }

        val watchdogDelay = (MIN_SPEECH_WATCHDOG_MS + text.length * 80L)
            .coerceAtMost(MAX_SPEECH_WATCHDOG_MS)
        handler.postDelayed(finishSpeechWatchdog, watchdogDelay)
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) return

        val tts = textToSpeech ?: return
        tts.setOnUtteranceProgressListener(
            object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit

                override fun onDone(utteranceId: String?) {
                    finishSpeech(utteranceId)
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    finishSpeech(utteranceId)
                }

                override fun onStop(utteranceId: String?, interrupted: Boolean) {
                    finishSpeech(utteranceId)
                }
            },
        )
        val languageStatus = tts.setLanguage(Locale("bg", "BG"))
        if (
            languageStatus == TextToSpeech.LANG_MISSING_DATA ||
            languageStatus == TextToSpeech.LANG_NOT_SUPPORTED
        ) {
            tts.setLanguage(Locale.getDefault())
        }
        tts.setSpeechRate(0.92f)
        tts.setPitch(0.92f)
        ttsReady = true
    }

    private fun finishSpeech(utteranceId: String? = null) {
        handler.post {
            if (utteranceId != null && utteranceId != activeUtteranceId) {
                return@post
            }
            handler.removeCallbacks(finishSpeechWatchdog)
            isSpeaking = false
            activeUtteranceId = null
            val callback = afterSpeech
            afterSpeech = null
            callback?.invoke()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java)
        manager.deleteNotificationChannel("iron_voice_service")

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Iron гласов режим",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Постоянен безшумен режим за офлайн „Hey Iron“."
            setSound(null, null)
            enableVibration(false)
            enableLights(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }

        manager.createNotificationChannel(channel)
    }

    private fun startAsForeground(status: String) {
        if (status.isBlank()) return
        val notification = buildNotification()
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
        if (!serviceActive || !foregroundStarted || status.isBlank()) return
        // The foreground notification intentionally stays unchanged. Rebuilding it
        // for every microphone state caused repeated alerts on some Android skins.
    }

    private fun buildNotification(): Notification {
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
            .setContentText("Iron е активен • готов за „Hey Iron“")
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setWhen(0)
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
        setSpeechCaptureActive(false)
        if (consumeExpectedRecognitionCancellation()) return
        Log.i(LOG_TAG, "speech_error code=$error")
        if (!serviceActive) return
        if (pausedForChatSpeech) return
        if (isSpeaking) return

        if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
            stopSelf()
            return
        }

        val isTransientRecognizerError =
            error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY ||
                error == SpeechRecognizer.ERROR_AUDIO ||
                error == SpeechRecognizer.ERROR_CLIENT ||
                error == SpeechRecognizer.ERROR_SERVER ||
                error == SpeechRecognizer.ERROR_SERVER_DISCONNECTED
        if (isTransientRecognizerError) {
            resetRecognizer()
        }

        if (
            error == SpeechRecognizer.ERROR_NO_MATCH ||
            error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
        ) {
            endConversation()
            voiceState = VoiceState.WAITING_FOR_WAKE
            updateNotification("Iron чака „Hey Iron“")
            scheduleWakeWordListening(450)
            return
        }

        endConversation()
        voiceState = VoiceState.WAITING_FOR_WAKE
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
        setSpeechCaptureActive(false)
        if (consumeExpectedRecognitionCancellation()) return
        if (!serviceActive) return
        if (pausedForChatSpeech) return
        processRecognition(results, isFinal = true)
    }

    override fun onPartialResults(partialResults: Bundle?) {
        if (!serviceActive || ignoreNextRecognitionError || pausedForChatSpeech) return
        processRecognition(partialResults, isFinal = false)
    }

    override fun onEvent(eventType: Int, params: Bundle?) = Unit
}
