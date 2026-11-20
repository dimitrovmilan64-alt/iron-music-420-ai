package com.example.ironmusic420ai

import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveOutputStream
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class HeyIronModelArchiveTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private fun tarBz2(file: File, entries: Map<String, String>): File {
        file.outputStream().use { raw ->
            BZip2CompressorOutputStream(raw).use { bz ->
                TarArchiveOutputStream(bz).use { tar ->
                    for ((name, body) in entries) {
                        val bytes = body.toByteArray()
                        val entry = TarArchiveEntry(name)
                        entry.size = bytes.size.toLong()
                        tar.putArchiveEntry(entry)
                        tar.write(bytes)
                        tar.closeArchiveEntry()
                    }
                }
            }
        }
        return file
    }

    @Test
    fun sha256MatchesKnownVector() {
        val file = tmp.newFile("abc.txt").apply { writeText("abc") }
        assertEquals(
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            HeyIronModelArchive.sha256Hex(file),
        )
    }

    @Test
    fun pinnedModelHashIsWellFormed() {
        assertTrue(Regex("^[0-9a-f]{64}$").matches(HeyIronEngine.MODEL_SHA256))
    }

    @Test
    fun matchingArchiveIsKept() {
        val file = tmp.newFile("ok.bin").apply { writeText("model") }
        val hash = HeyIronModelArchive.sha256Hex(file)
        HeyIronModelArchive.verifyOrDelete(file, hash.uppercase(), file.length())
        assertTrue(file.exists())
    }

    @Test
    fun tamperedArchiveIsDeletedAndRejected() {
        val file = tmp.newFile("bad.bin").apply { writeText("model") }
        val expected = HeyIronModelArchive.sha256Hex(file)
        file.writeText("modeL")
        try {
            HeyIronModelArchive.verifyOrDelete(file, expected, file.length())
            fail("Tampered archive must be rejected")
        } catch (error: ModelIntegrityException) {
            assertTrue(error.message!!.contains("SHA-256"))
        }
        assertFalse(file.exists())
    }

    @Test
    fun truncatedArchiveIsDeletedAndRejected() {
        val file = tmp.newFile("short.bin").apply { writeText("model") }
        val expected = HeyIronModelArchive.sha256Hex(file)
        try {
            HeyIronModelArchive.verifyOrDelete(file, expected, expectedBytes = 999)
            fail("Truncated archive must be rejected")
        } catch (_: ModelIntegrityException) {
        }
        assertFalse(file.exists())
    }

    @Test
    fun zipSlipEntriesAreRejected() {
        val dest = tmp.newFolder("model")
        assertNull(HeyIronModelArchive.resolvedEntryFile(dest, "../evil.txt"))
        assertNull(HeyIronModelArchive.resolvedEntryFile(dest, "a/../../evil.txt"))
        assertNull(HeyIronModelArchive.resolvedEntryFile(dest, "/etc/passwd"))
        assertNull(HeyIronModelArchive.resolvedEntryFile(dest, "C:\\evil.txt"))
        assertNull(HeyIronModelArchive.resolvedEntryFile(dest, ""))
        val ok = HeyIronModelArchive.resolvedEntryFile(dest, "pkg/sub/tokens.txt")
        assertNotNull(ok)
        assertEquals(File(dest.canonicalFile, "tokens.txt"), ok)
    }

    @Test
    fun extractFlattensModelFiles() {
        val archive = tarBz2(
            tmp.newFile("m.tar.bz2"),
            mapOf("pkg/tokens.txt" to "a b", "pkg/encoder.onnx" to "enc"),
        )
        val dest = File(tmp.root, "out")
        HeyIronModelArchive.extractTarBz2(archive, dest)
        assertEquals("a b", File(dest, "tokens.txt").readText())
        assertEquals("enc", File(dest, "encoder.onnx").readText())
    }

    @Test
    fun maliciousArchiveLeavesNoPartialModel() {
        val archive = tarBz2(
            tmp.newFile("evil.tar.bz2"),
            mapOf("pkg/tokens.txt" to "a b", "../evil.txt" to "pwned"),
        )
        val dest = File(tmp.root, "out")
        try {
            HeyIronModelArchive.extractTarBz2(archive, dest)
            fail("Path traversal must be rejected")
        } catch (_: SecurityException) {
        }
        assertFalse(dest.exists())
        assertFalse(File(tmp.root, "evil.txt").exists())
    }
}
