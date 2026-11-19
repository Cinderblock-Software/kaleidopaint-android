// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint

import android.util.AtomicFile
import com.cinderblocksoftware.kaleidopaint.geometry.*
import java.io.File

/** Current autosave plus private snapshots kept before switching drawings. */
class DrawingStore(private val directory: File) {
    companion object {
        private val currentFileLock = Any()
    }

    private val automaticNames = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val file = AtomicFile(File(directory, "current.kaleidopaint"))

    fun load(): KaleidoPaintDocument =
        synchronized(currentFileLock) {
            val document = KaleidoPaintDocument(WallpaperGroup.wpg632)
            // openRead also recovers an interrupted AtomicFile transaction.
            val text =
                try {
                    file.openRead().bufferedReader(Charsets.UTF_8).use { it.readText() }
                } catch (error: java.io.FileNotFoundException) {
                    if (file.baseFile.exists() || File(file.baseFile.path + ".bak").exists())
                        throw error
                    null
                }
            if (text != null) document.decodeFileFormat(text)
            document.itsUndoManager = UndoManager()
            document
        }

    fun readRaw(): ByteArray =
        synchronized(currentFileLock) { file.openRead().use { it.readBytes() } }

    fun archives(): List<File> =
        File(directory, "drawings")
            .listFiles()
            ?.filter {
                it.isFile && it.extension == "kaleidopaint"
            }
            ?.sortedByDescending { it.lastModified() }
            ?.also { files ->
                // Library enumeration runs on the document IO worker. Composition
                // reads only the cached label, never one file per visible row.
                for (file in files) {
                    val stamp = runCatching {
                        automaticNameMarker(file).takeIf { it.exists() }?.readText()
                    }
                        .getOrNull()
                    if (stamp != null) automaticNames[file.name] = stamp
                    else automaticNames.remove(file.name)
                }
            } ?: emptyList()

    fun archive(bytes: ByteArray, name: String? = null): File {
        val folder = File(directory, "drawings")
        check(folder.isDirectory || folder.mkdirs()) { "Cannot create drawing library" }
        val stamp =
            java.text
                .SimpleDateFormat("yyyy-MM-dd HH-mm-ss", java.util.Locale.ROOT)
                .format(java.util.Date())
        val title =
            name?.trim()?.replace(Regex("""[^\p{L}\p{N} _-]"""), "_")?.take(60)?.takeIf {
                it.isNotBlank()
            } ?: "Drawing $stamp"
        val result =
            File(folder, "$title ${java.util.UUID.randomUUID().toString().take(6)}.kaleidopaint")
        write(AtomicFile(result), bytes)
        // Do not infer automatic naming from user text: an explicit name may also
        // start with "Drawing". Older copies without this marker stay verbatim.
        if (name.isNullOrBlank())
            runCatching {
                automaticNameMarker(result).writeText(stamp)
                automaticNames[result.name] = stamp
            }
        return result
    }

    private fun automaticNameMarker(file: File) = File(file.parentFile, file.name + ".auto-name")

    fun displayName(file: File, localizedDefault: String): String {
        val stamp = automaticNames[file.name]
        return if (
            stamp != null &&
                stamp.matches(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}-[0-9]{2}-[0-9]{2}"))
        )
            "$localizedDefault $stamp"
        else file.nameWithoutExtension.substringBeforeLast(" ")
    }

    fun deleteArchive(file: File) {
        check(file.delete()) { "Cannot delete saved copy" }
        automaticNameMarker(file).delete()
        automaticNames.remove(file.name)
    }

    fun save(document: KaleidoPaintDocument) {
        val bytes =
            synchronized(document) { document.encodeFileFormat().toByteArray(Charsets.UTF_8) }
        saveBytes(bytes)
    }

    fun saveBytes(bytes: ByteArray) = synchronized(currentFileLock) { write(file, bytes) }

    private fun write(target: AtomicFile, bytes: ByteArray) {
        val stream = target.startWrite()
        try {
            stream.write(bytes)
            target.finishWrite(stream)
        } catch (error: Exception) {
            target.failWrite(stream)
            throw error
        }
    }
}
