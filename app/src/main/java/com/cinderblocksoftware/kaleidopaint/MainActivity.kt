// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint

import android.graphics.Color as AndroidColor
import android.os.Bundle
import android.view.Window
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ViewModelProvider
import com.cinderblocksoftware.kaleidopaint.geometry.*
import org.json.JSONObject

class MainActivity : ComponentActivity() {
    private var frameListener: Window.OnFrameMetricsAvailableListener? = null
    private val session: EditorSession by lazy {
        ViewModelProvider(this)[EditorSession::class.java]
    }
    private lateinit var documentActions: DocumentActions
    private val store
        get() = session.store

    private val document
        get() = session.document

    private var storageError: String?
        get() = session.storageError
        set(value) {
            session.storageError = value
        }

    private fun save() {
        session.requestSave()
    }

    override fun onStop() {
        session.requestSave(immediate = true)
        DiagnosticReports.event("app_background")
        super.onStop()
    }

    override fun onDestroy() {
        frameListener?.let { window.removeOnFrameMetricsAvailableListener(it) }
        if (::documentActions.isInitialized) documentActions.close()
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        FillAcceleration.initialize(this)
        DiagnosticReports.initialize(this)
        frameListener = DiagnosticReports.watch(window)
        documentActions =
            DocumentActions(
                this,
                store,
                current = { document },
                backup = {
                    if (session.canSave)
                        RenderSnapshot.capture(document)
                            .model
                            .encodeFileFormat()
                            .toByteArray(Charsets.UTF_8)
                    else store.readRaw()
                },
                replace = { next -> session.replace(next) },
                onError = { storageError = it },
            )
        enableEdgeToEdge()
        setContent {
            MaterialTheme(
                colorScheme =
                    lightColorScheme(
                        primary = EditorBlue,
                        secondary = EditorBlue,
                        tertiary = EditorBlue,
                        background = Color.White,
                        surface = Color.White,
                        onSurface = Color.Black,
                        surfaceContainerHigh = Color.White,
                        primaryContainer = Color(0xFFE0E0E0),
                        onPrimaryContainer = Color.Black,
                        surfaceVariant = Color(0xFFF2F2F7),
                        onSurfaceVariant = Color.Gray,
                        surfaceContainerHighest = Color(0xFFE5E5E7),
                        outline = Color.Gray,
                        outlineVariant = Color.LightGray,
                        secondaryContainer = Color(0xFFE5E5E7),
                    )
            ) {
                androidx.compose.runtime.key(document) {
                    KaleidoPaintApp(
                        document,
                        ::save,
                        documentActions::perform,
                        documentActions::imageReady,
                    )
                }
                documentActions.Dialogs()
                storageError?.let { message ->
                    AlertDialog(
                        onDismissRequest = { storageError = null },
                        title = { Text(stringResource(R.string.storage_error)) },
                        text = { Text(message) },
                        confirmButton = {
                            TextButton(onClick = { storageError = null }) {
                                Text(stringResource(android.R.string.ok))
                            }
                        },
                    )
                }
            }
        }
    }
}

@Composable
fun KaleidoPaintApp(
    document: KaleidoPaintDocument,
    onSave: () -> Unit,
    onFileAction: (FileAction) -> Unit,
    onImage: (ByteArray, Boolean) -> Unit,
) {
    var showAbout by rememberSaveable { mutableStateOf(false) }
    var performance by rememberSaveable { mutableStateOf(false) }

    if (performance) {
        PerformanceScreen(onBack = { performance = false })
    } else if (showAbout) {
        BackHandler { showAbout = false }
        AboutScreen(onBack = { showAbout = false }, onPerformance = { performance = true })
    } else {
        DrawingScreen(document, onSave, onFileAction, onImage, onAbout = { showAbout = true })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DrawingScreen(
    document: KaleidoPaintDocument,
    onSave: () -> Unit,
    onFileAction: (FileAction) -> Unit,
    onImage: (ByteArray, Boolean) -> Unit,
    onAbout: () -> Unit,
) {
    var revision by remember { mutableIntStateOf(0) }
    var settingsPanel by remember { mutableStateOf<EditorDialog?>(null) }
    var preparingImage by remember { mutableStateOf(false) }
    var filling by remember { mutableStateOf(false) }
    var colorPanel by remember { mutableStateOf<ColorTarget?>(null) }
    val context = LocalContext.current
    val barColor = toSRGBHex(document.itsBackgroundColor)
    SideEffect {
        val window = (context as ComponentActivity).window
        val encoded = AndroidColor.parseColor("#" + barColor)
        val light = AndroidColor.luminance(encoded) > .5f
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = light
            isAppearanceLightNavigationBars = light
        }
    }
    var canvasReady by remember { mutableStateOf(false) }
    val canvas = remember { CanvasView(context, document, onSave) { revision++ } }
    val activity = context as ComponentActivity
    DisposableEffect(canvas) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> {
                    canvas.onResume()
                    canvas.requestRender()
                }
                Lifecycle.Event.ON_PAUSE -> canvas.onPause()
                else -> Unit
            }
        }
        activity.lifecycle.addObserver(observer)
        onDispose {
            activity.lifecycle.removeObserver(observer)
            canvas.onPause()
        }
    }
    // Reading revision subscribes this toolbar to changes made by the native view.
    val group =
        synchronized(document) {
            revision
            document.itsWallpaperGroup
        }
    val undo = synchronized(document) { document.itsUndoManager?.canUndo == true }
    val redo = synchronized(document) { document.itsUndoManager?.canRedo == true }
    fun update(operation: () -> Unit) {
        synchronized(document) { operation() }
        revision++
        canvas.requestRender()
        onSave()
    }
    if (preparingImage)
        AlertDialog(
            onDismissRequest = {},
            title = { Text(stringResource(R.string.working)) },
            text = { LinearProgressIndicator(Modifier.fillMaxWidth()) },
            confirmButton = {},
        )
    var shapeStart by remember { mutableStateOf<UnitCellShape?>(null) }
    if (settingsPanel == EditorDialog.SHAPE)
        CellShapeControls(
            initial = synchronized(document) { document.getUnitCellShape() },
            rigidity = group.torusGroup.itsRigidity,
            onDismiss = {
                val start = shapeStart
                settingsPanel = null
                canvas.previewShape = false
                update {
                    val end = document.getUnitCellShape()
                    if (start != null && start != end) document.changeUnitCellShape(start, end)
                }
                shapeStart = null
            },
            onChange = { shape ->
                update {
                    document.setUnitCellShape(shape)
                    document.changeCount++
                }
            },
        )
    if (settingsPanel == EditorDialog.HELP) DrawingHelp { settingsPanel = null }
    if (settingsPanel == EditorDialog.SMOOTHING)
        SmoothingControls(
            synchronized(document) { document.itsSmoothingTolerance },
            onDismiss = { settingsPanel = null },
            onApply = { value ->
                settingsPanel = null
                update { document.itsSmoothingTolerance = value }
            },
        )
    if (settingsPanel == EditorDialog.CLEAR)
        AlertDialog(
            onDismissRequest = { settingsPanel = null },
            title = { Text(stringResource(R.string.clear_drawing)) },
            text = { Text(stringResource(R.string.clear_explanation)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        settingsPanel = null
                        update {
                            document.changeElementArray(document.itsElements.toList(), emptyList())
                            document.itsControlHandleHit = null
                        }
                    }
                ) {
                    Text(stringResource(R.string.clear))
                }
            },
            dismissButton = {
                TextButton(onClick = { settingsPanel = null }) {
                    Text(stringResource(android.R.string.cancel))
                }
            },
        )
    val hit = synchronized(document) { document.itsControlHandleHit }
    var widthGesture by remember { mutableStateOf<Pair<List<Brushstroke>, Double>?>(null) }
    fun selectedWidth(value: Double, matching: Boolean, finished: Boolean) {
        update {
            val selected = hit?.itsElement as? Brushstroke
            if (selected != null) {
                if (widthGesture == null)
                    widthGesture =
                        (if (matching)
                            document.itsElements.filterIsInstance<Brushstroke>().filter {
                                it.itsThickness == selected.itsThickness
                            }
                        else listOf(selected)) to selected.itsThickness
                val (affected, start) = widthGesture!!
                affected.forEach { it.itsThickness = value }
                document.changeCount++
                if (finished) {
                    if (start != value) document.changeThickness(affected, start, value)
                    widthGesture = null
                }
            }
        }
    }
    fun dismissSelection() {
        val pending = widthGesture
        if (pending != null) selectedWidth(pending.first.first().itsThickness, false, true)
        update { document.itsControlHandleHit = null }
    }
    val settleEdits by rememberUpdatedState {
        synchronized(document) {
            widthGesture?.let { (affected, start) ->
                val end = affected.firstOrNull()?.itsThickness
                if (end != null && start != end) document.changeThickness(affected, start, end)
            }
            widthGesture = null
            shapeStart?.let { start ->
                val end = document.getUnitCellShape()
                if (start != end) document.changeUnitCellShape(start, end)
            }
            shapeStart = null
        }
        onSave()
    }
    DisposableEffect(document) { onDispose { settleEdits() } }
    if (hit != null && colorPanel == null) {
        ElementControls(
            document = document,
            revision = revision,
            hit = hit,
            onDismiss = ::dismissSelection,
            onColor = { color, matching ->
                update {
                    document.changeElementAppearance(
                        element = hit.itsElement,
                        color = color,
                        matchingColor = matching,
                    )
                }
            },
            onWidth = ::selectedWidth,
            onDelete = { matching ->
                update {
                    val old = document.itsElements.toList()
                    val keep = old.filter {
                        if (matching) !it.itsColor.isAlmostTheSameAs(hit.itsElement.itsColor)
                        else it !== hit.itsElement
                    }
                    document.changeElementArray(old, keep)
                    document.itsControlHandleHit = null
                }
            },
            onNodeType = {
                update {
                    val curve = hit.itsElement as? Curve
                    val node = hit.itsNode
                    if (curve != null && node != null)
                        document.changeSplineNodeType(
                            curve,
                            node,
                            node.itsNodeType,
                            if (node.itsNodeType == SplineNodeType.corner) SplineNodeType.smooth
                            else SplineNodeType.corner,
                        )
                }
            },
            onSplitNode = {
                update {
                    val curve = hit.itsElement as? Curve
                    val node = hit.itsNode
                    if (curve != null && node != null) {
                        val (a, b) = curve.itsSpline.splitNode(node)
                        document.splitSplineNode(curve, node, a, b)
                    }
                    document.itsControlHandleHit = null
                }
            },
            onDeleteNode = {
                update {
                    val curve = hit.itsElement as? Curve
                    val node = hit.itsNode
                    if (curve != null && node != null && curve.itsSpline.itsNodes.size > 2)
                        document.deleteSplineNode(curve, node)
                    document.itsControlHandleHit = null
                }
            },
        )
    }
    colorPanel?.let { target ->
        ColorControls(
            title =
                stringResource(
                    when (target) {
                        ColorTarget.FILL -> R.string.fill_color
                        ColorTarget.BRUSH -> R.string.brush_color
                        else -> R.string.background
                    }
                ),
            initial =
                synchronized(document) {
                    when (target) {
                        ColorTarget.FILL -> document.itsFillColor
                        ColorTarget.BRUSH -> document.itsBrushColor
                        else -> document.itsBackgroundColor
                    }
                },
            onDismiss = { colorPanel = null },
            onApply = { color ->
                colorPanel = null
                DiagnosticReports.event(
                    "color_apply",
                    org.json
                        .JSONObject()
                        .put("target", target.name.lowercase(java.util.Locale.ROOT)),
                )
                update {
                    when (target) {
                        ColorTarget.FILL -> document.itsFillColor = color
                        ColorTarget.BRUSH -> document.itsBrushColor = color
                        else ->
                            if (document.itsBackgroundColor != color)
                                document.changeBackgroundColor(color)
                    }
                }
            },
        )
    }
    Box(Modifier.fillMaxSize()) {
        AndroidView(
            factory = { canvas },
            modifier = Modifier.fillMaxSize(),
            update = { view ->
                view.onSurfaceReady = { canvasReady = true }
                view.fillMode = filling
                view.previewShape = settingsPanel == EditorDialog.SHAPE
            },
        )
        if (canvasReady)
            FloatingEditorChrome(
                document,
                revision,
                undo,
                redo,
                filling,
                onAction = { action ->
                    DiagnosticReports.event(
                        "action",
                        JSONObject().put("action", action.reportName),
                    )
                    when (action) {
                        EditorAction.ABOUT -> onAbout()
                        EditorAction.SHAPE -> {
                            shapeStart = synchronized(document) { document.getUnitCellShape() }
                            settingsPanel = EditorDialog.SHAPE
                        }
                        EditorAction.HELP -> settingsPanel = EditorDialog.HELP
                        EditorAction.CLEAR -> settingsPanel = EditorDialog.CLEAR
                        else ->
                            update {
                                when (action) {
                                    EditorAction.UNDO -> document.itsUndoManager?.undo()
                                    EditorAction.REDO -> document.itsUndoManager?.redo()
                                    EditorAction.DRAW,
                                    EditorAction.EDIT -> {
                                        filling = false
                                        document.itsControlHandleHit = null
                                        document.itsTouchMode =
                                            if (action == EditorAction.EDIT) TouchMode.edit
                                            else TouchMode.draw
                                    }
                                    EditorAction.FILL -> {
                                        filling = !filling
                                        document.itsTouchMode = TouchMode.draw
                                        document.itsControlHandleHit = null
                                    }
                                    EditorAction.LOCK -> {
                                        filling = false
                                        document.itsContentIsLocked = !document.itsContentIsLocked
                                        document.itsTouchMode = TouchMode.draw
                                        document.itsControlHandleHit = null
                                    }
                                    EditorAction.GUIDES ->
                                        document.itsShowSingularitiesFlag =
                                            !document.itsShowSingularitiesFlag
                                    EditorAction.COLORS ->
                                        document.itsColorBySymmetryFlag =
                                            !document.itsColorBySymmetryFlag
                                    EditorAction.SHAPE,
                                    EditorAction.HELP,
                                    EditorAction.CLEAR,
                                    EditorAction.ABOUT -> Unit
                                    EditorAction.REALIGN ->
                                        document.changeUnitCellPlacement(
                                            document.itsUnitCellPlacement,
                                            UnitCellPlacement(document.itsWallpaperGroup),
                                        )
                                }
                            }
                    }
                },
                onColor = { colorPanel = it },
                onPaletteColor = { target, color ->
                    update {
                        when (target) {
                            ColorTarget.BRUSH -> document.itsBrushColor = color
                            ColorTarget.FILL -> document.itsFillColor = color
                            ColorTarget.BACKGROUND -> document.changeBackgroundColor(color)
                        }
                    }
                },
                onGroup = { choice ->
                    update {
                        if (choice != document.itsWallpaperGroup)
                            document.changeWallpaperGroup(choice, UnitCellPlacement(choice))
                    }
                },
                onWidth = { value -> update { document.itsBrushThickness = value } },
                onSmoothing = { value -> update { document.itsSmoothingTolerance = value } },
                onFile = onFileAction,
                maximumExportSize = canvas.maximumExportDimension,
                onPreview = { options, callback ->
                    canvas.exportPng(options.rectangle, options.size, options.transparent, callback)
                },
                onExport = { options, share ->
                    preparingImage = true
                    canvas.exportPng(options.rectangle, options.size, options.transparent) { result
                        ->
                        preparingImage = false
                        result.fold(
                            onSuccess = { onImage(it, share) },
                            onFailure = {
                                android.widget.Toast.makeText(
                                        context,
                                        R.string.file_operation_failed,
                                        android.widget.Toast.LENGTH_LONG,
                                    )
                                    .show()
                            },
                        )
                    }
                },
            )
        if (DiagnosticReports.recording)
            Text(
                stringResource(R.string.recording_badge),
                modifier =
                    Modifier.align(androidx.compose.ui.Alignment.TopEnd)
                        .then(Modifier.padding(top = 48.dp, end = 12.dp)),
                color = EditorBlue,
                style = MaterialTheme.typography.bodySmall,
            )
    }
}
