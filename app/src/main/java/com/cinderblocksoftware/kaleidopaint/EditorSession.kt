// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.app.Application
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import com.cinderblocksoftware.kaleidopaint.geometry.*
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** Owns session model/undo across activity recreation; serializes debounced saves off-main. */
class EditorSession(application: Application) : AndroidViewModel(application) {
    val store = DrawingStore(application.filesDir)

    companion object {
        // A finishing activity and its replacement must not write concurrently.
        private val saves = Executors.newSingleThreadScheduledExecutor()
    }

    private val main = Handler(Looper.getMainLooper())
    private val scheduling = Any()
    private var pending: ScheduledFuture<*>? = null
    private var generation = 0L
    var canSave = true
        private set

    var storageError by mutableStateOf<String?>(null)
    var document by mutableStateOf(load())
        private set

    private fun load(): KaleidoPaintDocument =
        try {
            store.load()
        } catch (failure: Exception) {
            canSave = false
            storageError = getApplication<Application>().getString(R.string.restore_failed)
            KaleidoPaintDocument(WallpaperGroup.wpg632).apply { itsUndoManager = UndoManager() }
        }

    fun replace(next: KaleidoPaintDocument) {
        document = next
        canSave = true
        requestSave(immediate = true)
    }

    fun requestSave(immediate: Boolean = false) {
        if (!canSave) return
        val current = document
        synchronized(scheduling) {
            val request = ++generation
            pending?.cancel(false)
            pending =
                saves.schedule(
                    {
                        try {
                            val bytes =
                                RenderSnapshot.capture(current)
                                    .model
                                    .encodeFileFormat()
                                    .toByteArray(Charsets.UTF_8)
                            // One executor orders all writes. A superseded queued snapshot
                            // cannot overwrite a newer document after import/new/recovery.
                            if (synchronized(scheduling) { request == generation })
                                store.saveBytes(bytes)
                        } catch (failure: Exception) {
                            main.post {
                                storageError =
                                    getApplication<Application>().getString(R.string.save_failed)
                            }
                        }
                    },
                    if (immediate) 0L else 200L,
                    TimeUnit.MILLISECONDS,
                )
        }
    }

    override fun onCleared() {
        requestSave(immediate = true)
        super.onCleared()
    }
}
