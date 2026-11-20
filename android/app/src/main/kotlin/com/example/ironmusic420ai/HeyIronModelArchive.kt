package com.example.ironmusic420ai

import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest

/** Thrown when the downloaded model archive does not match the pinned hash or size. */
class ModelIntegrityException(message: String) : IOException(message)

/**
 * Pure-JVM helpers for the downloaded Hey Iron keyword model archive: integrity
 * verification (SHA-256 + size) and safe tar.bz2 extraction (Zip Slip guard).
 * Kept free of Android APIs so it is covered by plain JUnit tests.
 */
object HeyIronModelArchive {

    fun sha256Hex(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n <= 0) break
                digest.update(buf, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    /**
     * Verifies [archive] against [expectedSha256] (and [expectedBytes] when > 0).
     * On mismatch the file is deleted and [ModelIntegrityException] is thrown,
     * so a corrupted or tampered download is never extracted or retried from disk.
     */
    fun verifyOrDelete(archive: File, expectedSha256: String, expectedBytes: Long = -1L) {
        val problem = when {
            !archive.isFile -> "файлът липсва"
            expectedBytes > 0 && archive.length() != expectedBytes ->
                "размерът е ${archive.length()} B, очакван $expectedBytes B"
            !sha256Hex(archive).equals(expectedSha256, ignoreCase = true) ->
                "SHA-256 контролната сума не съвпада"
            else -> null
        }
        if (problem != null) {
            archive.delete()
            throw ModelIntegrityException(
                "Изтегленият модел е повреден или подменен ($problem). Опитай отново.",
            )
        }
    }

    /**
     * Resolves an archive entry into [dest], flattening to the basename so the
     * model files land where [HeyIronEngine] expects them. Rejects absolute
     * paths, `..` segments, and anything that would canonicalize outside [dest].
     */
    fun resolvedEntryFile(dest: File, entryName: String): File? {
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

    /**
     * Extracts a tar.bz2 [archive] into a fresh [dest]. Any rejected entry aborts
     * with [SecurityException]; on any failure [dest] is removed so a half-written
     * model is never reported as ready.
     */
    fun extractTarBz2(archive: File, dest: File) {
        if (dest.exists()) dest.deleteRecursively()
        dest.mkdirs()
        try {
            archive.inputStream().use { fileStream ->
                BZip2CompressorInputStream(fileStream).use { bz ->
                    TarArchiveInputStream(bz).use { tar ->
                        var entry = tar.nextEntry
                        while (entry != null) {
                            if (!entry.isDirectory) {
                                val outFile = resolvedEntryFile(dest, entry.name)
                                    ?: throw SecurityException("Rejected archive path: ${entry.name}")
                                FileOutputStream(outFile).use { output -> tar.copyTo(output) }
                            }
                            entry = tar.nextEntry
                        }
                    }
                }
            }
        } catch (error: Throwable) {
            dest.deleteRecursively()
            throw error
        }
    }
}
