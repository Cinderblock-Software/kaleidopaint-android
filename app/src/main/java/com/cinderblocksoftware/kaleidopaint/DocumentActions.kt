// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.cinderblocksoftware.kaleidopaint.geometry.*
import java.io.File
import java.util.concurrent.Executors

/** System file pickers and an app-private library; all external IO is off the UI thread. */
class DocumentActions(
    private val activity: ComponentActivity,
    private val store: DrawingStore,
    private val current: () -> KaleidoPaintDocument,
    private val backup: () -> ByteArray,
    private val replace: (KaleidoPaintDocument) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val io = Executors.newSingleThreadExecutor()
    private var closed = false
    private var pendingTasks by mutableIntStateOf(0)
    private val working
        get() = pendingTasks > 0

    private var library by mutableStateOf<List<File>?>(null)
    private var newPrompt by mutableStateOf(false)
    private var copyPrompt by mutableStateOf(false)
    private var copyName by mutableStateOf("")
    private var deletePrompt by mutableStateOf<File?>(null)
    private var drawingBytes: ByteArray? = null
    private val pendingImage = File(activity.cacheDir, "pending-export.png")

    private fun ui(action: () -> Unit) {
        activity.runOnUiThread { if (!activity.isDestroyed) action() }
    }

    private fun task(action: () -> Unit) {
        if (closed) return
        pendingTasks++
        io.execute {
            try {
                action()
            } catch (failure: Exception) {
                android.util.Log.e(
                    "KaleidoPaint",
                    "Document operation failed (${failure.javaClass.simpleName})",
                )
                ui { onError(activity.getString(R.string.file_operation_failed)) }
            } finally {
                ui { pendingTasks-- }
            }
        }
    }

    private val open =
        activity.registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null)
                switchTo {
                    activity.contentResolver
                        .openInputStream(uri)
                        ?.bufferedReader(Charsets.UTF_8)
                        ?.use { it.readText() } ?: error("Cannot read selected drawing")
                }
        }
    private val exportDrawing =
        activity.registerForActivityResult(
            ActivityResultContracts.CreateDocument("application/octet-stream")
        ) { uri ->
            if (uri != null) {
                val bytes = drawingBytes
                task {
                    val outputBytes = bytes ?: backup()
                    activity.contentResolver.openOutputStream(uri, "wt")?.use {
                        it.write(outputBytes)
                    } ?: error("Cannot write selected drawing")
                }
            }
            drawingBytes = null
        }
    private val exportImage =
        activity.registerForActivityResult(ActivityResultContracts.CreateDocument("image/png")) {
            uri ->
            if (uri != null)
                task {
                    activity.contentResolver.openOutputStream(uri, "wt")?.use { output ->
                        pendingImage.inputStream().use { it.copyTo(output) }
                    } ?: error("Cannot write selected image")
                    pendingImage.delete()
                }
        }

    private fun createNew() {
        val group = current().itsWallpaperGroup
        task {
            val previous = backup()
            store.archive(previous)
            val next = KaleidoPaintDocument(group).apply { itsUndoManager = UndoManager() }
            ui { replace(next) }
        }
    }

    private fun keepCopy() {
        val name = copyName.trim()
        task { store.archive(backup(), name) }
    }

    private fun switchTo(read: () -> String) {
        task {
            val previous = backup()
            // Decode into a fresh model before touching the current drawing.
            val next =
                KaleidoPaintDocument().apply {
                    decodeFileFormat(read())
                    itsUndoManager = UndoManager()
                }
            store.archive(previous)
            ui { replace(next) }
        }
    }

    fun perform(action: FileAction) {
        when (action) {
            FileAction.OPEN -> open.launch(arrayOf("*/*"))
            FileAction.SAVE -> {
                task {
                    val bytes = backup()
                    ui {
                        drawingBytes = bytes
                        exportDrawing.launch(
                            activity.getString(R.string.drawing_name_default) + ".kaleidopaint"
                        )
                    }
                }
            }
            FileAction.NEW -> newPrompt = true
            FileAction.LIBRARY ->
                task {
                    val files = store.archives()
                    ui { library = files }
                }
            FileAction.SNAPSHOT -> {
                copyName = activity.getString(R.string.drawing_name_default)
                copyPrompt = true
            }
        }
    }

    fun imageReady(bytes: ByteArray, share: Boolean) {
        task {
            if (share) {
                val folder = File(activity.cacheDir, "shared").apply { mkdirs() }
                folder
                    .listFiles()
                    ?.filter { System.currentTimeMillis() - it.lastModified() > 86_400_000 }
                    ?.forEach { it.delete() }
                val file =
                    File(folder, "Drawing-${java.util.UUID.randomUUID()}.png").apply {
                        writeBytes(bytes)
                    }
                val uri =
                    FileProvider.getUriForFile(activity, activity.packageName + ".files", file)
                ui {
                    activity.startActivity(
                        Intent.createChooser(
                            Intent(Intent.ACTION_SEND).apply {
                                type = "image/png"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                clipData =
                                    android.content.ClipData.newRawUri(
                                        activity.getString(R.string.drawing_name_default),
                                        uri,
                                    )
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            },
                            activity.getString(R.string.share_image),
                        )
                    )
                }
            } else {
                pendingImage.writeBytes(bytes)
                ui {
                    exportImage.launch(activity.getString(R.string.drawing_name_default) + ".png")
                }
            }
        }
    }

    fun close() {
        closed = true
        io.shutdown()
    }

    @Composable
    fun Dialogs() {
        if (!working && !newPrompt && !copyPrompt && library == null && deletePrompt == null) return
        // Keep one native dialog window while moving between library, confirmation
        // and progress. Replacing overlapping windows can stall Android's RenderThread.
        val deleting = deletePrompt
        val title =
            when {
                working -> R.string.working
                deleting != null -> R.string.delete_copy
                library != null -> R.string.saved_drawings
                newPrompt -> R.string.new_drawing
                else -> R.string.keep_copy
            }
        val dismiss: () -> Unit = {
            if (!working)
                when {
                    deleting != null -> deletePrompt = null
                    library != null -> library = null
                    newPrompt -> newPrompt = false
                    else -> copyPrompt = false
                }
        }
        AlertDialog(
            onDismissRequest = dismiss,
            title = { Text(stringResource(title)) },
            text = {
                when {
                    working -> LinearProgressIndicator(Modifier.fillMaxWidth())
                    deleting != null -> Text(stringResource(R.string.delete_copy_confirmation))
                    library != null -> {
                        val files = library.orEmpty()
                        if (files.isEmpty()) Text(stringResource(R.string.no_saved_drawings))
                        else
                            LazyColumn(Modifier.heightIn(max = 440.dp)) {
                                items(files) { file ->
                                    Row(Modifier.fillMaxWidth()) {
                                        TextButton(
                                            modifier = Modifier.weight(1f),
                                            onClick = {
                                                library = null
                                                switchTo { file.readText(Charsets.UTF_8) }
                                            },
                                        ) {
                                            Text(
                                                store.displayName(
                                                    file,
                                                    stringResource(R.string.drawing_name_default),
                                                )
                                            )
                                        }
                                        TextButton(onClick = { deletePrompt = file }) {
                                            Text(stringResource(R.string.delete_copy))
                                        }
                                    }
                                }
                            }
                    }
                    newPrompt -> Text(stringResource(R.string.new_drawing_explanation))
                    else ->
                        OutlinedTextField(
                            value = copyName,
                            onValueChange = { copyName = it.take(60) },
                            singleLine = true,
                            label = { Text(stringResource(R.string.drawing_name)) },
                        )
                }
            },
            confirmButton = {
                if (!working)
                    TextButton(
                        enabled = title != R.string.keep_copy || copyName.isNotBlank(),
                        onClick = {
                            when {
                                deleting != null -> {
                                    deletePrompt = null
                                    task {
                                        store.deleteArchive(deleting)
                                        val files = store.archives()
                                        ui { library = files }
                                    }
                                }
                                library != null -> library = null
                                newPrompt -> {
                                    newPrompt = false
                                    createNew()
                                }
                                else -> {
                                    copyPrompt = false
                                    keepCopy()
                                }
                            }
                        },
                    ) {
                        Text(
                            stringResource(
                                when {
                                    deleting != null -> R.string.delete_copy
                                    library != null -> R.string.done
                                    newPrompt -> R.string.create
                                    else -> R.string.save
                                }
                            )
                        )
                    }
            },
            dismissButton = {
                if (!working && (deleting != null || newPrompt || copyPrompt))
                    TextButton(onClick = dismiss) { Text(stringResource(android.R.string.cancel)) }
            },
        )
    }
}
