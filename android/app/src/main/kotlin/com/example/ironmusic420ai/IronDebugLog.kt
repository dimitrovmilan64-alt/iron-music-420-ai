package com.example.ironmusic420ai

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Append-only diagnostics for Hey Iron and voice chat. Written to
 * getExternalFilesDir(null)/iron_debug.log so it can be pulled with
 * `adb shell cat /sdcard/Android/data/com.example.ironmusic420ai/files/iron_debug.log`.
 * Never writes API keys or other secrets.
 */
object IronDebugLog {
    private const val FILE_NAME = "iron_debug.log"
    private const val MAX_BYTES = 512 * 1024
    private val lock = ReentrantLock()
    private val timeFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    @Volatile
    private var file: File? = null

    fun init(context: Context) {
        val dir = context.getExternalFilesDir(null) ?: context.filesDir
        file = File(dir, FILE_NAME)
    }

    fun line(tag: String, message: String) {
        val target = file ?: return
        val stamped = "${timeFormat.format(Date())} [$tag] ${redact(message)}\n"
        lock.withLock {
            try {
                if (target.exists() && target.length() > MAX_BYTES) {
                    val kept = target.readText().takeLast(MAX_BYTES / 2)
                    target.writeText("… truncated …\n$kept")
                }
                target.appendText(stamped)
            } catch (_: Exception) {
                // Diagnostics must never break listening.
            }
        }
    }

    fun redact(value: String): String {
        var text = value
        text = KEY_PATTERN.replace(text, "[redacted]")
        text = ASSIGNMENT_PATTERN.replace(text, "$1[redacted]")
        return text
    }

    private val KEY_PATTERN = Regex(
        """(?i)\b(?:AIza[0-9A-Za-z\-_]{8,}|sk-[0-9A-Za-z\-_]{8,})\b""",
    )
    private val ASSIGNMENT_PATTERN = Regex(
        """(?i)(api[_-]?key|authorization|bearer)\s*[:=]\s*\S+""",
    )
}
