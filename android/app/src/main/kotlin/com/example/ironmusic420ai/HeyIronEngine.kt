package com.example.ironmusic420ai

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.KeywordSpotter
import com.k2fsa.sherpa.onnx.KeywordSpotterConfig
import com.k2fsa.sherpa.onnx.OnlineModelConfig
import com.k2fsa.sherpa.onnx.OnlineStream
import com.k2fsa.sherpa.onnx.OnlineTransducerModelConfig
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.sqrt

/**
 * Foreground-safe keyword spotter. Runs ONNX on a single background thread,
 * never on the main thread, and backs off when AudioRecord fails.
 * start() returns only after the microphone is actually recording.
 */
class HeyIronEngine(
    private val context: Context,
    private val listener: Listener,
) {
    interface Listener {
        fun onHeartbeat()
        fun onDetected(keyword: String)
        fun onError(message: String)
        fun onListeningChanged(listening: Boolean)
        fun onMicLevel(rms: Float)
    }

    companion object {
        const val MODEL_DIR_NAME = "sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
        const val ASSET_MODEL_DIR = "hey_iron"
        const val MODEL_URL =
            "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2"
        const val EXPECTED_ARCHIVE_BYTES = 32_885_699L
        const val SAMPLE_RATE = 16_000
        private const val FRAME_SAMPLES = 1_600
        private const val MIN_RMS = 0.006f
        private const val LOG_TAG = "HeyIronV2"
        private const val START_TIMEOUT_MS = 3_000L
        private const val MIC_EMIT_INTERVAL_MS = 80L

        val REQUIRED_FILES = listOf(
            "encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx",
            "decoder-epoch-13-avg-2-chunk-16-left-64.onnx",
            "joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx",
            "tokens.txt",
            "keywords.txt",
        )

        fun modelDir(context: Context): File =
            File(File(context.filesDir, "hey_iron"), MODEL_DIR_NAME)

        fun isModelReady(context: Context): Boolean {
            val dir = modelDir(context)
            return REQUIRED_FILES.all { File(dir, it).isFile && File(dir, it).length() > 0L }
        }

        fun hasMicPermission(context: Context): Boolean {
            return ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED
        }

        /**
         * Copies the small bundled keyword model from APK assets into the app
         * files directory. Returns null on success, or a Bulgarian error.
         */
        fun installBundledModel(context: Context, overwriteKeywords: Boolean = true): String? {
            val dest = modelDir(context)
            try {
                dest.mkdirs()
            } catch (error: Exception) {
                return "Не можах да създам папката за модела: ${error.message}"
            }
            for (name in REQUIRED_FILES) {
                val out = File(dest, name)
                val already = out.isFile && out.length() > 0L
                if (already && (name != "keywords.txt" || !overwriteKeywords)) {
                    continue
                }
                try {
                    context.assets.open("$ASSET_MODEL_DIR/$name").use { input ->
                        out.outputStream().use { input.copyTo(it) }
                    }
                } catch (error: Exception) {
                    return "Вграденият файл „$name“ липсва или не можа да се копира: ${error.message}"
                }
                if (!out.isFile || out.length() == 0L) {
                    return "Файлът „$name“ е празен след копирането от приложението."
                }
            }
            return if (isModelReady(context)) {
                null
            } else {
                val missing = REQUIRED_FILES.filter {
                    val file = File(dest, it)
                    !file.isFile || file.length() <= 0L
                }
                "Моделът е непълен. Липсват: ${missing.joinToString()}"
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val wakeGuard = WakeActivationGuard(
        requiredVoicedFrames = 2,
        signalHoldMillis = 1_500L,
        cooldownMillis = 4_000L,
    )

    @Volatile
    private var running = false

    @Volatile
    var lastError: String? = null
        private set

    @Volatile
    var lastRms: Float = 0f
        private set

    @Volatile
    var lastDetectedKeyword: String? = null
        private set

    @Volatile
    var lastDetectedAtMillis: Long = 0L
        private set

    @Volatile
    var isRecording: Boolean = false
        private set

    private var spotter: KeywordSpotter? = null
    private var recorder: AudioRecord? = null
    private var worker: Thread? = null
    private var startLatch: CountDownLatch? = null

    fun isRunning(): Boolean = running

    fun isListening(): Boolean = running && isRecording

    @Synchronized
    fun start(): Boolean {
        if (running && isRecording) return true
        if (running) {
            stopLocked()
        }
        lastError = null
        isRecording = false
        lastRms = 0f
        if (!hasMicPermission(context)) {
            val message = "Нужно е разрешение за микрофона."
            lastError = message
            listener.onError(message)
            return false
        }
        // Always refresh keywords.txt so a newer APK can lower the
        // threshold or add pronunciations without a reinstall of the model.
        val installError = installBundledModel(context, overwriteKeywords = true)
        if (installError != null && !isModelReady(context)) {
            lastError = installError
            listener.onError(installError)
            return false
        }
        if (!isModelReady(context)) {
            val message = "Офлайн моделът за „Хей Айрън“ липсва. Натисни „Опитай отново“."
            lastError = message
            listener.onError(message)
            return false
        }
        val engine = try {
            KeywordSpotter(config = createConfig())
        } catch (error: Throwable) {
            Log.e(LOG_TAG, "engine_failed", error)
            val detail = listOfNotNull(error::class.java.simpleName, error.message)
                .joinToString(": ")
                .ifBlank { "неизвестна грешка" }
            val message = "Моделът не можа да се зареди на този телефон. $detail"
            lastError = message
            listener.onError(message)
            return false
        }
        spotter = engine
        val latch = CountDownLatch(1)
        startLatch = latch
        running = true
        startWorker(engine)
        val started = try {
            latch.await(START_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            false
        }
        if (!started || !isRecording) {
            val message = lastError ?: "Микрофонът не можа да бъде стартиран."
            lastError = message
            stopLocked()
            listener.onError(message)
            return false
        }
        listener.onListeningChanged(true)
        return true
    }

    @Synchronized
    fun stop() {
        stopLocked()
    }

    private fun stopLocked() {
        running = false
        startLatch?.countDown()
        startLatch = null
        val rec = recorder
        recorder = null
        try {
            if (rec?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                rec.stop()
            }
        } catch (_: Exception) {
        }
        worker?.interrupt()
        val thread = worker
        if (thread != null && thread !== Thread.currentThread()) {
            try {
                thread.join(800)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
        worker = null
        try {
            rec?.release()
        } catch (_: Exception) {
        }
        try {
            spotter?.release()
        } catch (_: Exception) {
        }
        spotter = null
        isRecording = false
        lastRms = 0f
        handler.post { listener.onListeningChanged(false) }
    }

    fun testMic(durationMs: Int = 800): Map<String, Any?> {
        if (!hasMicPermission(context)) {
            return mapOf(
                "ok" to false,
                "granted" to false,
                "rms" to 0.0,
                "peak" to 0.0,
                "listening" to isListening(),
                "error" to "Нужно е разрешение за микрофона.",
            )
        }
        if (isListening()) {
            return mapOf(
                "ok" to true,
                "granted" to true,
                "rms" to lastRms.toDouble(),
                "peak" to lastRms.toDouble(),
                "listening" to true,
                "error" to null,
            )
        }
        val rec = createRecorder()
            ?: return mapOf(
                "ok" to false,
                "granted" to true,
                "rms" to 0.0,
                "peak" to 0.0,
                "listening" to false,
                "error" to "Микрофонът не можа да бъде стартиран.",
            )
        val buffer = ShortArray(FRAME_SAMPLES)
        var squareSum = 0.0
        var samples = 0
        var peak = 0.0
        val deadline = SystemClock.elapsedRealtime() + durationMs.coerceIn(200, 3_000)
        try {
            while (SystemClock.elapsedRealtime() < deadline) {
                val count = try {
                    rec.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                } catch (_: Exception) {
                    -1
                }
                if (count <= 0) break
                var square = 0.0
                for (index in 0 until count) {
                    val sample = buffer[index] / 32768.0
                    square += sample * sample
                }
                squareSum += square
                samples += count
                val rms = sqrt(square / count)
                if (rms > peak) peak = rms
            }
        } finally {
            try {
                if (rec.recordingState == AudioRecord.RECORDSTATE_RECORDING) rec.stop()
            } catch (_: Exception) {
            }
            try {
                rec.release()
            } catch (_: Exception) {
            }
        }
        if (samples <= 0) {
            return mapOf(
                "ok" to false,
                "granted" to true,
                "rms" to 0.0,
                "peak" to 0.0,
                "listening" to false,
                "error" to "Микрофонът не върна звук.",
            )
        }
        val rms = sqrt(squareSum / samples)
        lastRms = rms.toFloat()
        return mapOf(
            "ok" to true,
            "granted" to true,
            "rms" to rms,
            "peak" to peak,
            "listening" to false,
            "error" to null,
        )
    }

    private fun createConfig(): KeywordSpotterConfig {
        val dir = modelDir(context).absolutePath
        val modelConfig = OnlineModelConfig(
            transducer = OnlineTransducerModelConfig(
                encoder = "$dir/encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx",
                decoder = "$dir/decoder-epoch-13-avg-2-chunk-16-left-64.onnx",
                joiner = "$dir/joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx",
            ),
            tokens = "$dir/tokens.txt",
            numThreads = 1,
            debug = false,
            provider = "cpu",
        )
        return KeywordSpotterConfig(
            featConfig = FeatureConfig(
                sampleRate = SAMPLE_RATE,
                featureDim = 80,
                dither = 0.0f,
            ),
            modelConfig = modelConfig,
            maxActivePaths = 4,
            keywordsFile = "$dir/keywords.txt",
            keywordsScore = 2.5f,
            keywordsThreshold = 0.10f,
            numTrailingBlanks = 1,
        )
    }

    private fun createRecorder(): AudioRecord? {
        val min = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (min <= 0) return null
        val bufferSize = maxOf(min * 4, FRAME_SAMPLES * 2 * 8)
        val sources = listOf(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            MediaRecorder.AudioSource.MIC,
        )
        for (source in sources) {
            val rec = try {
                AudioRecord(
                    source,
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize,
                )
            } catch (_: Exception) {
                null
            } ?: continue
            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                rec.release()
                continue
            }
            try {
                rec.startRecording()
            } catch (_: Exception) {
                rec.release()
                continue
            }
            if (rec.recordingState == AudioRecord.RECORDSTATE_RECORDING) return rec
            rec.release()
        }
        return null
    }

    private fun signalStart(recording: Boolean, error: String?) {
        if (error != null) lastError = error
        isRecording = recording
        startLatch?.countDown()
    }

    private fun startWorker(engine: KeywordSpotter) {
        val thread = Thread({
            var stream: OnlineStream? = null
            var rec: AudioRecord? = null
            var backoffMs = 80L
            var lastHeartbeat = 0L
            var lastMicEmit = 0L
            try {
                stream = engine.createStream()
                if (stream.ptr == 0L) {
                    signalStart(false, "Неуспешно отваряне на потока за „Хей Айрън“.")
                    return@Thread
                }
                rec = createRecorder()
                if (rec == null) {
                    signalStart(false, "Микрофонът не можа да бъде стартиран.")
                    return@Thread
                }
                recorder = rec
                signalStart(true, null)
                val buffer = ShortArray(FRAME_SAMPLES)
                wakeGuard.resetSignal()
                while (running) {
                    val count = try {
                        rec.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                    } catch (_: Exception) {
                        -1
                    }
                    if (!running) break
                    if (count <= 0) {
                        try {
                            Thread.sleep(backoffMs)
                        } catch (_: InterruptedException) {
                            break
                        }
                        backoffMs = minOf(2_000L, backoffMs * 2)
                        continue
                    }
                    backoffMs = 80L

                    var square = 0.0
                    val samples = FloatArray(count) { index ->
                        val sample = buffer[index] / 32768.0f
                        square += sample * sample
                        sample
                    }
                    val rms = sqrt(square / count).toFloat()
                    lastRms = rms
                    val now = SystemClock.elapsedRealtime()
                    wakeGuard.observeFrame(voiced = rms >= MIN_RMS, nowMillis = now)
                    if (now - lastMicEmit >= MIC_EMIT_INTERVAL_MS) {
                        lastMicEmit = now
                        handler.post { listener.onMicLevel(rms) }
                    }
                    if (now - lastHeartbeat >= 2_500L) {
                        lastHeartbeat = now
                        handler.post { listener.onHeartbeat() }
                    }

                    stream.acceptWaveform(samples, sampleRate = SAMPLE_RATE)
                    var detectedKeyword = ""
                    while (running && engine.isReady(stream)) {
                        engine.decode(stream)
                        val keyword = engine.getResult(stream).keyword
                        if (keyword.isBlank()) continue
                        engine.reset(stream)
                        when (wakeGuard.evaluate(SystemClock.elapsedRealtime())) {
                            WakeActivationGuard.Decision.ACCEPT -> {
                                detectedKeyword = keyword
                            }
                            else -> Unit
                        }
                        if (detectedKeyword.isNotEmpty()) break
                    }
                    if (detectedKeyword.isNotEmpty()) {
                        running = false
                        lastDetectedKeyword = detectedKeyword
                        lastDetectedAtMillis = System.currentTimeMillis()
                        beep()
                        handler.post { listener.onDetected(detectedKeyword) }
                        break
                    }
                }
            } catch (error: Exception) {
                if (running) {
                    Log.w(LOG_TAG, "worker_failed", error)
                    if (startLatch?.count == 1L) {
                        signalStart(false, "Слушането беше прекъснато.")
                    }
                    postError("Слушането беше прекъснато.")
                }
            } finally {
                isRecording = false
                try {
                    rec?.let {
                        if (it.recordingState == AudioRecord.RECORDSTATE_RECORDING) it.stop()
                        it.release()
                    }
                } catch (_: Exception) {
                }
                if (recorder === rec) recorder = null
                try {
                    stream?.release()
                } catch (_: Exception) {
                }
                startLatch?.countDown()
            }
        }, "HeyIronV2")
        thread.isDaemon = true
        worker = thread
        thread.start()
    }

    private fun beep() {
        try {
            val tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 60)
            tone.startTone(ToneGenerator.TONE_PROP_BEEP, 160)
            handler.postDelayed({
                try {
                    tone.release()
                } catch (_: Exception) {
                }
            }, 250)
        } catch (_: Exception) {
        }
    }

    private fun postError(message: String) {
        handler.post { listener.onError(message) }
    }
}
