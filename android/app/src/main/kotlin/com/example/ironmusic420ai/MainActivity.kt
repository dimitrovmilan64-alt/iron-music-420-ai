package com.example.ironmusic420ai

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.AlarmClock
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val MAX_CHAT_SPEECH_RELEASE_CHECKS = 30
        private const val CHAT_SPEECH_RELEASE_CHECK_MS = 100L
        private const val CHAT_SPEECH_STOP_TIMEOUT_MS = 2_500L
    }

    private val channelName = "iron_music_420/automations"
    private var pendingFlashResult: MethodChannel.Result? = null
    private var pendingFlashEnabled = false
    private var pendingVoiceResult: MethodChannel.Result? = null
    private var pendingIronSection: Int? = null
    private var pendingStudioPrompt = ""
    private var pendingStudioOutputType = ""
    private var pendingStudioAutoGenerate = false
    private var automationChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val cameraManager by lazy {
        getSystemService(Context.CAMERA_SERVICE) as CameraManager
    }
    private var torchCallbackRegistered = false
    private val torchCallback = object : CameraManager.TorchCallback() {
        override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
            FlashlightController.updateFromSystem(cameraManager, cameraId, enabled)
        }

        override fun onTorchModeUnavailable(cameraId: String) {
            FlashlightController.updateFromSystem(cameraManager, cameraId, false)
        }
    }
    private var chatSpeechRecognizer: SpeechRecognizer? = null
    private var pendingChatSpeechResult: MethodChannel.Result? = null
    private var chatSpeechLastPartial = ""
    private var chatSpeechStopRequested = false
    private var chatSpeechReleaseChecks = 0
    private val chatSpeechAttemptTracker = RecognitionAttemptTracker()
    private var restoreIronVoiceAfterChatSpeech = false
    private val beginChatSpeechRecognition = Runnable {
        launchChatSpeechRecognizerWhenReady()
    }
    private val chatSpeechTimeout = Runnable {
        if (chatSpeechLastPartial.isNotBlank()) {
            finishChatSpeech(text = chatSpeechLastPartial)
        } else if (shouldRetryChatSpeech(SpeechRecognizer.ERROR_SPEECH_TIMEOUT)) {
            retryChatSpeechRecognition(SpeechRecognizer.ERROR_SPEECH_TIMEOUT)
        } else {
            finishChatSpeech(
                errorCode = "CHAT_SPEECH_TIMEOUT",
                errorMessage = "Не чух реч навреме. Натисни микрофона и говори след сигнала.",
            )
        }
    }
    private val chatSpeechStopTimeout = Runnable {
        if (pendingChatSpeechResult == null || !chatSpeechStopRequested) {
            return@Runnable
        }
        if (chatSpeechLastPartial.isNotBlank()) {
            finishChatSpeech(text = chatSpeechLastPartial)
        } else {
            finishChatSpeech(
                errorCode = "CHAT_SPEECH_NO_MATCH",
                errorMessage = "Не чух ясни думи. Натисни микрофона и говори след сигнала.",
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        captureIronSection(intent)
        automationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        automationChannel?.setMethodCallHandler { call, result ->
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
                    "consumeStudioVoiceRequest" -> {
                        if (pendingStudioPrompt.isBlank()) {
                            result.success(null)
                        } else {
                            result.success(
                                mapOf(
                                    "prompt" to pendingStudioPrompt,
                                    "outputType" to pendingStudioOutputType,
                                    "autoGenerate" to pendingStudioAutoGenerate,
                                ),
                            )
                            pendingStudioPrompt = ""
                            pendingStudioOutputType = ""
                            pendingStudioAutoGenerate = false
                        }
                    }
                    "syncGeminiApiKey" -> {
                        syncGeminiApiKey(
                            call.argument<String>("apiKey").orEmpty(),
                            result,
                        )
                    }
                    "syncAiProviderSettings" -> {
                        syncAiProviderSettings(
                            geminiApiKey = call.argument<String>("geminiApiKey").orEmpty(),
                            backupApiKey = call.argument<String>("backupApiKey").orEmpty(),
                            backupBaseUrl = call.argument<String>("backupBaseUrl").orEmpty(),
                            backupModel = call.argument<String>("backupModel").orEmpty(),
                            result = result,
                        )
                    }
                    "startChatSpeechRecognition" -> {
                        startChatSpeechRecognition(result)
                    }
                    "stopChatSpeechRecognition" -> {
                        stopChatSpeechRecognition(result)
                    }
                    "cancelChatSpeechRecognition" -> {
                        cancelChatSpeechRecognition(result)
                    }
                    "pauseIronVoiceCapture" -> {
                        pauseIronVoiceCapture(result)
                    }
                    "resumeIronVoiceCapture" -> {
                        resumeIronVoiceCapture(result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onStart() {
        super.onStart()
        if (torchCallbackRegistered) return
        try {
            cameraManager.registerTorchCallback(torchCallback, mainHandler)
            torchCallbackRegistered = true
        } catch (_: Exception) {
            // Explicit torch actions still report a useful error to Flutter.
        }
    }

    override fun onStop() {
        if (torchCallbackRegistered) {
            try {
                cameraManager.unregisterTorchCallback(torchCallback)
            } catch (_: Exception) {
                // The camera service may already have removed the callback.
            }
            torchCallbackRegistered = false
        }
        super.onStop()
    }

    private fun startChatSpeechRecognition(result: MethodChannel.Result) {
        if (pendingChatSpeechResult != null) {
            result.error(
                "CHAT_SPEECH_BUSY",
                "Микрофонът вече слуша.",
                null,
            )
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error(
                "CHAT_SPEECH_UNAVAILABLE",
                "На телефона няма активна Android услуга за разпознаване на реч.",
                null,
            )
            return
        }

        pendingChatSpeechResult = result
        if (
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                4203,
            )
            return
        }
        prepareChatSpeechRecognition()
    }

    private fun prepareChatSpeechRecognition() {
        chatSpeechAttemptTracker.resetOperation()
        chatSpeechReleaseChecks = 0
        restoreIronVoiceAfterChatSpeech = IronVoiceService.isRunning
        if (restoreIronVoiceAfterChatSpeech) {
            startService(
                Intent(this, IronVoiceService::class.java).apply {
                    action = IronVoiceService.ACTION_PAUSE_WAKE
                },
            )
        }

        val releaseDelay = if (restoreIronVoiceAfterChatSpeech) 100L else 80L
        mainHandler.removeCallbacks(beginChatSpeechRecognition)
        mainHandler.postDelayed(beginChatSpeechRecognition, releaseDelay)
    }

    private fun launchChatSpeechRecognizerWhenReady() {
        if (pendingChatSpeechResult == null) return
        if (isFinishing || isDestroyed) {
            finishChatSpeech(
                errorCode = "CHAT_SPEECH_CANCELLED",
                errorMessage = "Гласовото разпознаване беше прекратено.",
            )
            return
        }

        if (IronVoiceService.isMicrophoneCaptureActive()) {
            if (chatSpeechReleaseChecks < MAX_CHAT_SPEECH_RELEASE_CHECKS) {
                chatSpeechReleaseChecks++
                mainHandler.postDelayed(
                    beginChatSpeechRecognition,
                    CHAT_SPEECH_RELEASE_CHECK_MS,
                )
                return
            }
            finishChatSpeech(
                errorCode = "CHAT_SPEECH_BUSY",
                errorMessage = "Микрофонът не се освободи навреме. Опитай отново.",
            )
            return
        }

        launchChatSpeechRecognizer()
    }

    private fun launchChatSpeechRecognizer() {
        if (pendingChatSpeechResult == null || isFinishing || isDestroyed) {
            finishChatSpeech(
                errorCode = "CHAT_SPEECH_CANCELLED",
                errorMessage = "Гласовото разпознаване беше прекратено.",
            )
            return
        }

        chatSpeechLastPartial = ""
        chatSpeechStopRequested = false
        val recognizer = try {
            SpeechRecognizer.createSpeechRecognizer(this)
        } catch (error: Exception) {
            finishChatSpeech(
                errorCode = "CHAT_SPEECH_START_ERROR",
                errorMessage = error.localizedMessage
                    ?: "Android не успя да създаде гласовия разпознавател.",
            )
            return
        }
        val attemptGeneration = chatSpeechAttemptTracker.beginAttempt()
        chatSpeechRecognizer = recognizer
        recognizer.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                if (!isCurrentChatSpeechAttempt(recognizer, attemptGeneration)) return
                automationChannel?.invokeMethod(
                    "chatSpeechStatus",
                    mapOf("status" to "ready"),
                )
            }

            override fun onBeginningOfSpeech() {
                if (!isCurrentChatSpeechAttempt(recognizer, attemptGeneration)) return
                automationChannel?.invokeMethod(
                    "chatSpeechStatus",
                    mapOf("status" to "speaking"),
                )
            }

            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() = Unit

            override fun onError(error: Int) {
                if (!isCurrentChatSpeechAttempt(recognizer, attemptGeneration)) return
                if (
                    (chatSpeechStopRequested ||
                        error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                        error == SpeechRecognizer.ERROR_NO_MATCH) &&
                    chatSpeechLastPartial.isNotBlank()
                ) {
                    finishChatSpeech(text = chatSpeechLastPartial)
                    return
                }

                if (shouldRetryChatSpeech(error)) {
                    retryChatSpeechRecognition(error)
                    return
                }

                val errorCode: String
                val message: String
                when (error) {
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
                    SpeechRecognizer.ERROR_NO_MATCH -> {
                        errorCode = "CHAT_SPEECH_NO_MATCH"
                        message = "Не чух ясни думи. Натисни микрофона и говори след сигнала."
                    }
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> {
                        errorCode = "CHAT_SPEECH_BUSY"
                        message = "Микрофонът още се освобождава. Опитай отново след секунда."
                    }
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                        errorCode = "CHAT_SPEECH_PERMISSION"
                        message = "Разреши достъп до микрофона за Iron Music 420 AI."
                    }
                    SpeechRecognizer.ERROR_NETWORK,
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                    SpeechRecognizer.ERROR_SERVER -> {
                        errorCode = "CHAT_SPEECH_NETWORK"
                        message = "Android разпознаването на реч няма връзка. Провери Google Speech Services и интернета."
                    }
                    SpeechRecognizer.ERROR_AUDIO -> {
                        errorCode = "CHAT_SPEECH_AUDIO"
                        message = "Android не успя да отвори микрофона."
                    }
                    SpeechRecognizer.ERROR_CLIENT -> {
                        errorCode = if (chatSpeechStopRequested) {
                            "CHAT_SPEECH_CANCELLED"
                        } else {
                            "CHAT_SPEECH_CLIENT"
                        }
                        message = if (chatSpeechStopRequested) {
                            "Гласовото разпознаване беше прекратено."
                        } else {
                            "Android прекрати гласовото разпознаване."
                        }
                    }
                    else -> {
                        errorCode = "CHAT_SPEECH_ERROR"
                        message = "Гласовото разпознаване върна грешка $error."
                    }
                }
                finishChatSpeech(
                    errorCode = errorCode,
                    errorMessage = message,
                )
            }

            override fun onResults(results: Bundle?) {
                if (!isCurrentChatSpeechAttempt(recognizer, attemptGeneration)) return
                val text = bestRecognitionText(results)
                    .ifBlank { chatSpeechLastPartial }
                if (text.isBlank()) {
                    if (shouldRetryChatSpeech(SpeechRecognizer.ERROR_NO_MATCH)) {
                        retryChatSpeechRecognition(SpeechRecognizer.ERROR_NO_MATCH)
                    } else {
                        finishChatSpeech(
                            errorCode = "CHAT_SPEECH_NO_MATCH",
                            errorMessage = "Не чух ясни думи. Натисни микрофона и говори след сигнала.",
                        )
                    }
                } else {
                    finishChatSpeech(text = text)
                }
            }

            override fun onPartialResults(partialResults: Bundle?) {
                if (!isCurrentChatSpeechAttempt(recognizer, attemptGeneration)) return
                val text = bestRecognitionText(partialResults)
                if (text.isBlank()) return
                chatSpeechLastPartial = text
                automationChannel?.invokeMethod(
                    "chatSpeechPartial",
                    mapOf("text" to text),
                )
            }

            override fun onEvent(eventType: Int, params: Bundle?) = Unit
        })

        val recognitionIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "bg-BG")
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "bg-BG")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS,
                1_200L,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                2_500L,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                4_000L,
            )
        }

        try {
            recognizer.startListening(recognitionIntent)
            mainHandler.postDelayed(chatSpeechTimeout, 45_000L)
        } catch (error: Exception) {
            finishChatSpeech(
                errorCode = "CHAT_SPEECH_START_ERROR",
                errorMessage = error.localizedMessage
                    ?: "Android не успя да стартира микрофона.",
            )
        }
    }

    private fun isCurrentChatSpeechAttempt(
        recognizer: SpeechRecognizer,
        generation: Int,
    ): Boolean =
        pendingChatSpeechResult != null &&
            chatSpeechRecognizer === recognizer &&
            chatSpeechAttemptTracker.isCurrent(generation)

    private fun bestRecognitionText(results: Bundle?): String {
        return results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            .orEmpty()
            .trim()
    }

    private fun shouldRetryChatSpeech(error: Int): Boolean {
        if (
            !chatSpeechAttemptTracker.canRetry() ||
            chatSpeechStopRequested ||
            pendingChatSpeechResult == null
        ) {
            return false
        }
        return error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
            error == SpeechRecognizer.ERROR_NO_MATCH ||
            error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY ||
            error == SpeechRecognizer.ERROR_AUDIO ||
            error == SpeechRecognizer.ERROR_CLIENT
    }

    private fun retryChatSpeechRecognition(error: Int) {
        if (!chatSpeechAttemptTracker.recordRetry()) return
        chatSpeechReleaseChecks = 0
        chatSpeechLastPartial = ""
        releaseChatSpeechRecognizer()
        automationChannel?.invokeMethod(
            "chatSpeechStatus",
            mapOf("status" to "retrying"),
        )
        val delay = when (error) {
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
            SpeechRecognizer.ERROR_AUDIO,
            SpeechRecognizer.ERROR_CLIENT -> 700L
            else -> 450L
        }
        mainHandler.postDelayed(beginChatSpeechRecognition, delay)
    }

    private fun releaseChatSpeechRecognizer() {
        mainHandler.removeCallbacks(chatSpeechTimeout)
        mainHandler.removeCallbacks(chatSpeechStopTimeout)
        chatSpeechAttemptTracker.invalidateAttempt()
        val recognizer = chatSpeechRecognizer
        chatSpeechRecognizer = null
        try {
            recognizer?.cancel()
        } catch (_: Exception) {
            // Recognition may already be complete.
        }
        try {
            recognizer?.destroy()
        } catch (_: Exception) {
            // Recognition may already be destroyed.
        }
    }

    private fun stopChatSpeechRecognition(result: MethodChannel.Result) {
        val recognizer = chatSpeechRecognizer
        if (pendingChatSpeechResult == null) {
            result.success(false)
            return
        }
        if (recognizer == null) {
            chatSpeechStopRequested = true
            finishChatSpeech(
                errorCode = "CHAT_SPEECH_CANCELLED",
                errorMessage = "Гласовото разпознаване беше прекратено.",
            )
            result.success(true)
            return
        }
        chatSpeechStopRequested = true
        try {
            recognizer.stopListening()
            mainHandler.removeCallbacks(chatSpeechStopTimeout)
            mainHandler.postDelayed(
                chatSpeechStopTimeout,
                CHAT_SPEECH_STOP_TIMEOUT_MS,
            )
            result.success(true)
        } catch (error: Exception) {
            finishChatSpeech(
                errorCode = "CHAT_SPEECH_STOP_ERROR",
                errorMessage = error.localizedMessage
                    ?: "Микрофонът не можа да бъде спрян.",
            )
            result.error(
                "CHAT_SPEECH_STOP_ERROR",
                error.localizedMessage ?: "Микрофонът не можа да бъде спрян.",
                null,
            )
        }
    }

    private fun cancelChatSpeechRecognition(result: MethodChannel.Result) {
        if (pendingChatSpeechResult == null) {
            result.success(false)
            return
        }
        chatSpeechStopRequested = true
        try {
            chatSpeechRecognizer?.cancel()
        } catch (_: Exception) {
            // Recognizer may already have stopped.
        }
        finishChatSpeech(
            errorCode = "CHAT_SPEECH_CANCELLED",
            errorMessage = "Гласовото разпознаване беше прекратено.",
        )
        result.success(true)
    }

    private fun finishChatSpeech(
        text: String? = null,
        errorCode: String? = null,
        errorMessage: String? = null,
    ) {
        val pendingResult = pendingChatSpeechResult ?: return
        pendingChatSpeechResult = null
        mainHandler.removeCallbacks(beginChatSpeechRecognition)
        mainHandler.removeCallbacks(chatSpeechTimeout)
        mainHandler.removeCallbacks(chatSpeechStopTimeout)
        releaseChatSpeechRecognizer()

        if (errorCode == null) {
            pendingResult.success(text.orEmpty().trim())
        } else {
            pendingResult.error(errorCode, errorMessage, null)
        }
        automationChannel?.invokeMethod(
            "chatSpeechStatus",
            mapOf("status" to "done"),
        )

        val shouldRestore = restoreIronVoiceAfterChatSpeech
        restoreIronVoiceAfterChatSpeech = false
        chatSpeechLastPartial = ""
        chatSpeechStopRequested = false
        chatSpeechReleaseChecks = 0
        if (shouldRestore &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            startService(
                Intent(this, IronVoiceService::class.java).apply {
                    action = IronVoiceService.ACTION_RESUME_WAKE
                },
            )
        }
    }

    private fun pauseIronVoiceCapture(result: MethodChannel.Result) {
        val active = IronVoiceService.isRunning
        if (active) {
            startService(
                Intent(this, IronVoiceService::class.java).apply {
                    action = IronVoiceService.ACTION_PAUSE_WAKE
                },
            )
        }
        result.success(active)
    }

    private fun resumeIronVoiceCapture(result: MethodChannel.Result) {
        if (
            IronVoiceService.isRunning &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            startService(
                Intent(this, IronVoiceService::class.java).apply {
                    action = IronVoiceService.ACTION_RESUME_WAKE
                },
            )
        }
        result.success(true)
    }

    private fun syncGeminiApiKey(
        apiKey: String,
        result: MethodChannel.Result,
    ) {
        val editor = getSharedPreferences(
            GeminiVoiceRouter.PREFS_NAME,
            Context.MODE_PRIVATE,
        ).edit()
        val cleanKey = apiKey.trim()
        if (cleanKey.isEmpty()) {
            editor.remove(GeminiVoiceRouter.KEY_GEMINI_API_KEY)
        } else {
            editor.putString(GeminiVoiceRouter.KEY_GEMINI_API_KEY, cleanKey)
        }
        editor.apply()
        result.success(true)
    }

    private fun syncAiProviderSettings(
        geminiApiKey: String,
        backupApiKey: String,
        backupBaseUrl: String,
        backupModel: String,
        result: MethodChannel.Result,
    ) {
        val editor = getSharedPreferences(
            GeminiVoiceRouter.PREFS_NAME,
            Context.MODE_PRIVATE,
        ).edit()

        val cleanGeminiKey = geminiApiKey.trim()
        val cleanBackupKey = backupApiKey.trim()
        val cleanBaseUrl = backupBaseUrl.trim().ifBlank {
            GeminiVoiceRouter.DEFAULT_BACKUP_BASE_URL
        }
        val cleanModel = backupModel.trim().ifBlank {
            GeminiVoiceRouter.DEFAULT_BACKUP_MODEL
        }

        if (cleanGeminiKey.isEmpty()) {
            editor.remove(GeminiVoiceRouter.KEY_GEMINI_API_KEY)
        } else {
            editor.putString(GeminiVoiceRouter.KEY_GEMINI_API_KEY, cleanGeminiKey)
        }
        if (cleanBackupKey.isEmpty()) {
            editor.remove(GeminiVoiceRouter.KEY_BACKUP_API_KEY)
        } else {
            editor.putString(GeminiVoiceRouter.KEY_BACKUP_API_KEY, cleanBackupKey)
        }
        editor.putString(GeminiVoiceRouter.KEY_BACKUP_BASE_URL, cleanBaseUrl)
        editor.putString(GeminiVoiceRouter.KEY_BACKUP_MODEL, cleanModel)
        editor.apply()
        result.success(true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIronSection(intent)
    }

    override fun onPostResume() {
        super.onPostResume()
        restoreIronVoiceIfEnabled()
    }

    private fun restoreIronVoiceIfEnabled() {
        if (IronVoiceService.isRunning) return
        val enabled = getSharedPreferences(
            IronVoiceService.VOICE_PREFS,
            Context.MODE_PRIVATE,
        ).getBoolean(IronVoiceService.KEY_VOICE_ENABLED, true)
        if (!enabled) return
        if (
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        try {
            ContextCompat.startForegroundService(
                this,
                Intent(this, IronVoiceService::class.java).apply {
                    action = IronVoiceService.ACTION_START
                },
            )
        } catch (_: Exception) {
            // The visible toggle can retry and surface an Android error.
        }
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(beginChatSpeechRecognition)
        mainHandler.removeCallbacks(chatSpeechTimeout)
        mainHandler.removeCallbacks(chatSpeechStopTimeout)
        val pendingSpeechResult = pendingChatSpeechResult
        pendingChatSpeechResult = null
        releaseChatSpeechRecognizer()

        pendingSpeechResult?.error(
            "CHAT_SPEECH_CANCELLED",
            "Гласовото разпознаване беше прекратено.",
            null,
        )
        pendingVoiceResult?.error(
            "IRON_VOICE_CANCELLED",
            "Стартирането на Iron беше прекратено.",
            null,
        )
        pendingVoiceResult = null

        if (
            restoreIronVoiceAfterChatSpeech &&
            IronVoiceService.isRunning &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            startService(
                Intent(this, IronVoiceService::class.java).apply {
                    action = IronVoiceService.ACTION_RESUME_WAKE
                },
            )
        }
        restoreIronVoiceAfterChatSpeech = false
        automationChannel?.setMethodCallHandler(null)
        automationChannel = null
        super.onDestroy()
    }

    private fun captureIronSection(intent: Intent?) {
        val section = intent?.getIntExtra("iron_section", -1) ?: -1
        if (section in 0..4) {
            pendingIronSection = section
        }

        val studioPrompt = intent?.getStringExtra("iron_studio_prompt").orEmpty().trim()
        if (studioPrompt.isNotEmpty()) {
            pendingStudioPrompt = studioPrompt
            pendingStudioOutputType =
                intent?.getStringExtra("iron_studio_output_type").orEmpty().trim()
            pendingStudioAutoGenerate =
                intent?.getBooleanExtra("iron_studio_auto_generate", false) == true
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
                "youtube_autoplay_status" -> {
                    result.success(YoutubeAutoPlayAccessibilityService.isEnabled(this))
                }
                "youtube_autoplay_settings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(
                        "В Достъпност отвори „Iron: пускане в YouTube“ и го включи."
                    )
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
                "flash_status" -> result.success(FlashlightController.isEnabled())
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
                    getSharedPreferences(IronVoiceService.VOICE_PREFS, Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean(IronVoiceService.KEY_VOICE_ENABLED, false)
                        .apply()
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
        getSharedPreferences(IronVoiceService.VOICE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(IronVoiceService.KEY_VOICE_ENABLED, true)
            .apply()
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
        FlashlightController.setEnabled(this, enabled)
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
            4203 -> {
                if (
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO,
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    prepareChatSpeechRecognition()
                } else {
                    finishChatSpeech(
                        errorCode = "CHAT_SPEECH_PERMISSION",
                        errorMessage = "Разреши достъп до микрофона за Iron Music 420 AI.",
                    )
                }
            }
        }
    }
}
