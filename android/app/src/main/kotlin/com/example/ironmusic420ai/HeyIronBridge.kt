package com.example.ironmusic420ai

import android.app.Activity
import android.os.Build
import androidx.core.app.ActivityCompat
import android.content.pm.PackageManager
import android.Manifest
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

class HeyIronBridge(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, HeyIronEngine.Listener {

    companion object {
        const val METHOD_CHANNEL = "iron_music_420/hey_iron"
        const val EVENT_CHANNEL = "iron_music_420/hey_iron_events"
        private const val LOG_TAG = "HeyIronV2"
        const val MIC_PERMISSION_REQUEST = 4204
                private val KEYWORDS = """
            HH EY1 AY1 ER0 N :3.0 #0.05 @HEY_IRON_1_1
            HH EY1 AY1 R AH0 N :3.0 #0.05 @HEY_IRON_BG
            HH EY1 AY1 R AH1 N :3.0 #0.05 @HEY_IRON_BG_STRESS
            HH EY1 AY1 R N :3.0 #0.05 @HEY_IRON_BG_FAST
            HH EH1 Y AY1 R AH0 N :3.0 #0.05 @HEY_IRON_BG_EH
            HH EH1 AY1 R AH0 N :3.0 #0.05 @HEY_IRON_BG_EH_SHORT
            HH EY1 AY1 R AO0 N :3.0 #0.05 @HEY_IRON_BG_O
            HH EY1 AY1 R OW0 N :3.0 #0.05 @HEY_IRON_BG_OW
            HH AY1 AY1 ER0 N :3.0 #0.05 @HI_IRON
            HH AY1 R AH0 N :3.0 #0.05 @HI_IRON_BG
            HH AY1 AY1 R AH0 N :3.0 #0.05 @HI_IRON_BG2
            EY1 AY1 ER0 N :3.0 #0.05 @AY_IRON
            AY1 AY1 ER0 N :3.0 #0.05 @AY_IRON_SHORT
            AY1 R AH0 N :3.0 #0.05 @AY_IRON_BG
            EY1 AY1 R AH0 N :3.0 #0.05 @AY_IRON_OPEN
            HH EY1 R AH0 N :3.0 #0.05 @HEY_IRON_REDUCED
""".trimIndent()

        /**
         * Resolves an archive entry into [dest], flattening to the basename so the
         * model files land where [HeyIronEngine] expects them. Rejects absolute
         * paths, `..` segments, and anything that would canonicalize outside [dest].
         */
        internal fun resolvedArchiveFile(dest: File, entryName: String): File? {
            val targetDir = dest.canonicalFile
            val normalized = entryName.replace("\\", "/")
            if (normalized.isEmpty() ||
                normalized.startsWith("/") ||
                Regex("^[A-Za-z]:").containsMatchIn(normalized)
            ) {
                return null
            }
            val parts = normalized.split('/').filter { it.isNotEmpty() && it != "." }
            if (parts.isEmpty() || parts.any { it == ".." }) {
                return null
            }
            val prefix = targetDir.path + File.separator
            val candidate = File(targetDir, parts.joinToString(File.separator)).canonicalFile
            if (candidate.path != targetDir.path && !candidate.path.startsWith(prefix)) {
                return null
            }
            val flattened = File(targetDir, parts.last()).canonicalFile
            if (!flattened.path.startsWith(prefix)) {
                return null
            }
            return flattened
        }
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private val engine = HeyIronEngine(activity, this)
    @Volatile
    private var downloading = false
    private var pendingMicCallback: ((Boolean) -> Unit)? = null
    private var pendingDetectedKeyword: String? = null

    fun attach(messenger: BinaryMessenger) {
        IronDebugLog.init(activity)
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    fun detach() {
        engine.stop()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(statusMap())
            "downloadModel", "prepareModel" -> {
                Thread({
                    val payload = prepareModelOnWorker()
                    activity.runOnUiThread { result.success(payload) }
                }, "HeyIronPrepare").start()
            }
            "start" -> {
                // The in-app engine must own the mic exclusively. Stop the
                // background service first so two AudioRecord clients cannot
                // race on Android 14/15.
                ensureMicPermission { granted ->
                    if (!granted) {
                        result.success(
                            mapOf(
                                "ok" to false,
                                "error" to "Нужно е разрешение за микрофона. Разреши го от настройките на телефона.",
                            ),
                        )
                        return@ensureMicPermission
                    }
                    Thread({
                        stopBackgroundService()
                        try {
                            Thread.sleep(200)
                        } catch (_: InterruptedException) {
                            Thread.currentThread().interrupt()
                        }
                        val started = try {
                            engine.start()
                        } catch (error: Exception) {
                            Log.e(LOG_TAG, "start_failed", error)
                            false
                        }
                        val error = if (started) {
                            null
                        } else {
                            engine.lastError ?: "Слушането не можа да стартира."
                        }
                        activity.runOnUiThread {
                            result.success(mapOf("ok" to started, "error" to error))
                        }
                    }, "HeyIronStart").start()
                }
            }
            "stop" -> {
                engine.stop()
                stopBackgroundService()
                result.success(true)
            }
            "stopEngine" -> {
                engine.stop()
                result.success(true)
            }
            "startBackground" -> {
                engine.stop()
                ensureMicPermission { granted ->
                    if (!granted) {
                        result.error(
                            "BACKGROUND",
                            "Нужно е разрешение за микрофона.",
                            null,
                        )
                        return@ensureMicPermission
                    }
                    try {
                        startBackgroundService()
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("BACKGROUND", error.message, null)
                    }
                }
            }
            "testMic" -> {
                ensureMicPermission { granted ->
                    if (!granted) {
                        result.success(
                            mapOf(
                                "ok" to false,
                                "granted" to false,
                                "rms" to 0.0,
                                "peak" to 0.0,
                                "error" to "Нужно е разрешение за микрофона. Разреши го от настройките на телефона.",
                            ),
                        )
                        return@ensureMicPermission
                    }
                    Thread({
                        val payload = try {
                            engine.testMic()
                        } catch (error: Exception) {
                            Log.e(LOG_TAG, "test_mic_failed", error)
                            mapOf(
                                "ok" to false,
                                "granted" to true,
                                "rms" to 0.0,
                                "peak" to 0.0,
                                "error" to (error.message ?: "Тестът на микрофона не успя."),
                            )
                        }
                        activity.runOnUiThread { result.success(payload) }
                    }, "HeyIronTestMic").start()
                }
            }
            "deviceInfo" -> result.success(
                "${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"
            )
            "debugLog" -> {
                IronDebugLog.init(activity)
                val tag = call.argument<String>("tag") ?: "dart"
                val message = call.argument<String>("message") ?: ""
                if (message.isNotBlank()) IronDebugLog.line(tag, message)
                result.success(true)
            }
            "setBackground" -> result.success(true)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val pending = pendingDetectedKeyword
        if (pending != null) {
            pendingDetectedKeyword = null
            emit("detected", mapOf("keyword" to pending))
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onHeartbeat() = emit("heartbeat")

    override fun onDetected(keyword: String) {
        if (eventSink == null) {
            pendingDetectedKeyword = keyword
            return
        }
        emit("detected", mapOf("keyword" to keyword))
    }

    override fun onMicLevel(rms: Float) {
        emit("micLevel", mapOf("rms" to rms.toDouble()))
    }

    fun handlePermissionResult(granted: Boolean): Boolean {
        val callback = pendingMicCallback ?: return false
        pendingMicCallback = null
        callback(granted)
        return true
    }

    private fun ensureMicPermission(callback: (Boolean) -> Unit) {
        if (HeyIronEngine.hasMicPermission(activity)) {
            callback(true)
            return
        }
        pendingMicCallback = callback
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            MIC_PERMISSION_REQUEST,
        )
    }

    private fun statusMap(): Map<String, Any?> {
        return mapOf(
            "modelReady" to HeyIronEngine.isModelReady(activity),
            "listening" to engine.isListening(),
            "running" to engine.isRunning(),
            "recording" to engine.isRecording,
            "hasMicPermission" to HeyIronEngine.hasMicPermission(activity),
            "rms" to engine.lastRms.toDouble(),
            "lastKeyword" to engine.lastDetectedKeyword,
            "lastDetectedAt" to engine.lastDetectedAtMillis,
            "archiveBytes" to HeyIronEngine.EXPECTED_ARCHIVE_BYTES,
            "lastError" to engine.lastError,
        )
    }

    override fun onError(message: String) {
        emit("error", mapOf("message" to message))
    }

    override fun onListeningChanged(listening: Boolean) {
        emit(if (listening) "listening" else "stopped")
    }

    private fun emit(type: String, extra: Map<String, Any?> = emptyMap()) {
        val payload = HashMap<String, Any?>(extra)
        payload["type"] = type
        val sink = eventSink ?: return
        activity.runOnUiThread { sink.success(payload) }
    }

    fun releaseMicrophone() {
        engine.stop()
        stopBackgroundService()
    }

    fun isMicrophoneInUse(): Boolean =
        engine.isRunning() || engine.isRecording || HeyIronForegroundService.isActive

    private fun startBackgroundService() {
        val intent = Intent(activity, HeyIronForegroundService::class.java)
        ContextCompat.startForegroundService(activity, intent)
    }

    private fun stopBackgroundService() {
        activity.stopService(Intent(activity, HeyIronForegroundService::class.java))
    }

    private fun prepareModelOnWorker(): Map<String, Any?> {
        val bundled = HeyIronEngine.installBundledModel(activity)
        if (bundled == null && HeyIronEngine.isModelReady(activity)) {
            return mapOf("ok" to true, "error" to null, "source" to "bundled")
        }
        return try {
            val ok = downloadAndExtract()
            if (ok) {
                mapOf("ok" to true, "error" to null, "source" to "download")
            } else {
                val error = bundled
                    ?: "Изтеглянето на модела не успя."
                emit("error", mapOf("message" to error))
                mapOf("ok" to false, "error" to error, "source" to "download")
            }
        } catch (error: Exception) {
            Log.e(LOG_TAG, "download_failed", error)
            val message = error.message?.takeIf { it.isNotBlank() }
                ?: "Изтеглянето не успя."
            emit("error", mapOf("message" to message))
            mapOf("ok" to false, "error" to message, "source" to "download")
        }
    }

    private fun downloadAndExtract(): Boolean {
        if (downloading) return false
        downloading = true
        val root = File(activity.filesDir, "hey_iron")
        root.mkdirs()
        val archive = File(root, "model.tar.bz2")
        try {
            val connection = (URL(HeyIronEngine.MODEL_URL).openConnection() as HttpURLConnection)
            connection.instanceFollowRedirects = true
            connection.connectTimeout = 20_000
            connection.readTimeout = 60_000
            connection.connect()
            val code = connection.responseCode
            if (code !in 200..299) {
                connection.disconnect()
                throw IllegalStateException("Сървърът за модела върна HTTP $code.")
            }
            val total = connection.contentLengthLong.let {
                if (it > 0) it else HeyIronEngine.EXPECTED_ARCHIVE_BYTES
            }
            connection.inputStream.use { input ->
                FileOutputStream(archive).use { output ->
                    val buf = ByteArray(64 * 1024)
                    var received = 0L
                    var lastEmit = 0L
                    while (true) {
                        val n = input.read(buf)
                        if (n <= 0) break
                        output.write(buf, 0, n)
                        received += n
                        if (received - lastEmit > 256 * 1024) {
                            lastEmit = received
                            emit(
                                "progress",
                                mapOf("received" to received, "total" to total),
                            )
                        }
                    }
                    emit("progress", mapOf("received" to received, "total" to total))
                }
            }
            connection.disconnect()

            val dest = HeyIronEngine.modelDir(activity)
            if (dest.exists()) dest.deleteRecursively()
            dest.mkdirs()

            archive.inputStream().use { fileStream ->
                BZip2CompressorInputStream(fileStream).use { bz ->
                    TarArchiveInputStream(bz).use { tar ->
                        var entry = tar.nextEntry
                        while (entry != null) {
                            if (!entry.isDirectory) {
                                val outFile = resolvedArchiveFile(dest, entry.name)
                                    ?: throw SecurityException("Rejected archive path: ${entry.name}")
                                FileOutputStream(outFile).use { output ->
                                    tar.copyTo(output)
                                }
                            }
                            entry = tar.nextEntry
                        }
                    }
                }
            }
            // Prefer the bundled keyword list (Hey Iron + Хей Айрън).
            val bundledKeywords = try {
                activity.assets.open("${HeyIronEngine.ASSET_MODEL_DIR}/keywords.txt")
                    .use { it.bufferedReader().readText() }
            } catch (_: Exception) {
                KEYWORDS.trimIndent() + "\n"
            }
            File(dest, "keywords.txt").writeText(bundledKeywords)
            if (!HeyIronEngine.isModelReady(activity)) {
                val missing = HeyIronEngine.REQUIRED_FILES.filter {
                    val file = File(dest, it)
                    !file.isFile || file.length() <= 0L
                }
                throw IllegalStateException(
                    "След разархивирането липсват файлове: ${missing.joinToString()}.",
                )
            }
            return true
        } finally {
            if (archive.exists()) archive.delete()
            downloading = false
        }
    }
}
