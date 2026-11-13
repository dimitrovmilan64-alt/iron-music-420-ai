package com.example.ironmusic420ai

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.KeywordSpotter
import com.k2fsa.sherpa.onnx.KeywordSpotterConfig
import com.k2fsa.sherpa.onnx.OnlineModelConfig
import com.k2fsa.sherpa.onnx.OnlineStream
import com.k2fsa.sherpa.onnx.OnlineTransducerModelConfig
import java.io.File
import kotlin.math.sqrt

/**
 * Foreground-safe keyword spotter. Runs ONNX on a single background thread,
 * never on the main thread, and backs off when AudioRecord fails.
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
    }

    companion object {
        const val MODEL_DIR_NAME = "sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
        const val MODEL_URL =
            "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2"
        const val EXPECTED_ARCHIVE_BYTES = 32_885_699L
        private const val SAMPLE_RATE = 16_000
        private const val FRAME_SAMPLES = 1_600
        private const val MIN_RMS = 0.006f
        private const val LOG_TAG = "HeyIronV2"

        fun modelDir(context: Context): File =
            File(File(context.filesDir, "hey_iron"), MODEL_DIR_NAME)

        fun isModelReady(context: Context): Boolean {
            val dir = modelDir(context)
            val required = listOf(
                "encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx",
                "decoder-epoch-13-avg-2-chunk-16-left-64.onnx",
                "joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx",
                "tokens.txt",
                "keywords.txt",
            )
            return required.all { File(dir, it).isFile && File(dir, it).length() > 0L }
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

    private var spotter: KeywordSpotter? = null
    private var recorder: AudioRecord? = null
    private var worker: Thread? = null

    fun isRunning(): Boolean = running

    @Synchronized
    fun start(): Boolean {
        if (running) return true
        if (!isModelReady(context)) {
            listener.onError("Офлайн моделът за „Хей Айрън“ липсва.")
            return false
        }
        val engine = try {
            KeywordSpotter(config = createConfig())
        } catch (error: Throwable) {
            Log.e(LOG_TAG, "engine_failed", error)
            listener.onError("Моделът не можа да се зареди на този телефон.")
            return false
        }
        spotter = engine
        running = true
        startWorker(engine)
        listener.onListeningChanged(true)
        return true
    }

    @Synchronized
    fun stop() {
        running = false
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
        handler.post { listener.onListeningChanged(false) }
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
            maxActivePaths = 2,
            keywordsFile = "$dir/keywords.txt",
            keywordsScore = 1.5f,
            keywordsThreshold = 0.25f,
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

    private fun startWorker(engine: KeywordSpotter) {
        val thread = Thread({
            var stream: OnlineStream? = null
            var rec: AudioRecord? = null
            var backoffMs = 80L
            var lastHeartbeat = 0L
            try {
                stream = engine.createStream()
                if (stream.ptr == 0L) {
                    postError("Неуспешно отваряне на потока за „Хей Айрън“.")
                    return@Thread
                }
                rec = createRecorder()
                if (rec == null) {
                    postError("Микрофонът не можа да бъде стартиран.")
                    return@Thread
                }
                recorder = rec
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
                    val now = SystemClock.elapsedRealtime()
                    wakeGuard.observeFrame(voiced = rms >= MIN_RMS, nowMillis = now)
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
                        beep()
                        handler.post { listener.onDetected(detectedKeyword) }
                        break
                    }
                }
            } catch (error: Exception) {
                if (running) {
                    Log.w(LOG_TAG, "worker_failed", error)
                    postError("Слушането беше прекъснато.")
                }
            } finally {
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
