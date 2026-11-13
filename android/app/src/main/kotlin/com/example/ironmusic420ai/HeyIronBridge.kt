package com.example.ironmusic420ai

import android.app.Activity
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
        private val KEYWORDS = """
            HH EY1 AY1 R AH0 N :6.5 #0.03 @HEY_IRON_BG
            HH EY1 AY1 R AH1 N :6.5 #0.03 @HEY_IRON_BG_STRESS
            HH EY1 AY1 R N :6.5 #0.03 @HEY_IRON_BG_FAST
            HH EH1 Y AY1 R AH0 N :6.5 #0.03 @HEY_IRON_BG_EH
            HH EH1 AY1 R AH0 N :6.5 #0.03 @HEY_IRON_BG_EH_SHORT
            HH EY1 AY1 R AO0 N :6.5 #0.03 @HEY_IRON_BG_O
            HH EY1 AY1 R OW0 N :6.5 #0.03 @HEY_IRON_BG_OW
        """.trimIndent()

        /**
         * Resolves an archive entry into [dest], flattening to the basename so the
         * model files land where [HeyIronEngine] expects them. Rejects absolute
         * paths, `..` segments, and anything that would canonicalize outside [dest].
         */
        internal fun resolvedArchiveFile(dest: File, entryName: String): File? {
            val targetDir = dest.canonicalFile
            val normalized = entryName.replace('\', '/')
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

    fun attach(messenger: BinaryMessenger) {
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
            "status" -> result.success(
                mapOf(
                    "modelReady" to HeyIronEngine.isModelReady(activity),
                    "listening" to engine.isRunning(),
                    "archiveBytes" to HeyIronEngine.EXPECTED_ARCHIVE_BYTES,
                ),
            )
            "downloadModel" -> {
                if (HeyIronEngine.isModelReady(activity)) {
                    result.success(true)
                    return
                }
                Thread({
                    val ok = try {
                        downloadAndExtract()
                    } catch (error: Exception) {
                        Log.e(LOG_TAG, "download_failed", error)
                        emit("error", mapOf("message" to (error.message ?: "Изтеглянето не успя.")))
                        false
                    }
                    activity.runOnUiThread { result.success(ok) }
                }, "HeyIronDownload").start()
            }
            "start" -> {
                val started = engine.start()
                result.success(started)
            }
            "stop" -> {
                engine.stop()
                stopBackgroundService()
                result.success(true)
            }
            "startBackground" -> {
                try {
                    startBackgroundService()
                    result.success(true)
                } catch (error: Exception) {
                    result.error("BACKGROUND", error.message, null)
                }
            }
            "setBackground" -> result.success(true)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onHeartbeat() = emit("heartbeat")

    override fun onDetected(keyword: String) {
        emit("detected", mapOf("keyword" to keyword))
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

    private fun startBackgroundService() {
        val intent = Intent(activity, HeyIronForegroundService::class.java)
        ContextCompat.startForegroundService(activity, intent)
    }

    private fun stopBackgroundService() {
        activity.stopService(Intent(activity, HeyIronForegroundService::class.java))
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
            File(dest, "keywords.txt").writeText(KEYWORDS.trimIndent() + "\n")
            return HeyIronEngine.isModelReady(activity)
        } finally {
            if (archive.exists()) archive.delete()
            downloading = false
        }
    }
}
