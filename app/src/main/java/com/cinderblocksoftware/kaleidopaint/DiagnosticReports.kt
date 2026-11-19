// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.*
import android.util.AtomicFile
import android.view.FrameMetrics
import android.view.Window
import androidx.compose.runtime.*
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.json.JSONArray
import org.json.JSONObject

/** Opt-in bounded diagnostics. No drawing data, touch coordinates or system logcat. */
internal object DiagnosticReports {
    var recording by mutableStateOf(false)
        private set

    private lateinit var context: Context
    private val worker = Executors.newSingleThreadScheduledExecutor()
    private val ioLock = Any()
    private val events = ArrayDeque<JSONObject>()
    private var header = JSONObject()
    private val actionCounts = mutableMapOf<String, Long>()
    private var started = 0L
    private var checkpoints = 0L
    private var checkpointTotalNs = 0L
    private var checkpointMaxNs = 0L
    private var checkpointBytes = 0L
    private var frames = 0L
    private var totalFrameNs = 0L
    private var maxFrameNs = 0L
    private var slowFrames = 0L
    private var gpu = JSONObject()
    private var uiFrames = 0L
    private var uiTotalNs = 0L
    private var uiMaxNs = 0L
    private var uiDeadlineMisses = 0L
    private var droppedMetricReports = 0L
    private val frameThread by lazy {
        HandlerThread("performance-window-metrics").apply { start() }
    }
    private var initialized = false

    private fun folder() = File(context.filesDir, "diagnostics").apply { mkdirs() }

    @Synchronized
    fun initialize(app: Context) {
        if (initialized) return
        context = app.applicationContext
        initialized = true
        // A previous active checkpoint surviving restart is an interrupted session.
        for (name in listOf("recording.json", "benchmark.json")) {
            val old = File(folder(), name)
            if (old.exists())
                runCatching {
                    val data = JSONObject(old.readText())
                    if (data.optString("state") in listOf("recording", "running"))
                        write(name, data.put("state", "interrupted"))
                }
        }
        worker.scheduleAtFixedRate(
            { if (recording) runCatching { checkpoint() } },
            5,
            5,
            TimeUnit.SECONDS,
        )
    }

    @Synchronized
    fun gpu(renderer: String?, version: String?) {
        gpu = JSONObject().put("renderer", renderer).put("version", version)
    }

    @Synchronized
    fun start() {
        events.clear()
        actionCounts.clear()
        checkpoints = 0
        checkpointTotalNs = 0
        checkpointMaxNs = 0
        checkpointBytes = 0
        frames = 0
        totalFrameNs = 0
        maxFrameNs = 0
        slowFrames = 0
        started = SystemClock.elapsedRealtimeNanos()
        uiFrames = 0
        uiTotalNs = 0
        uiMaxNs = 0
        uiDeadlineMisses = 0
        droppedMetricReports = 0
        header =
            JSONObject()
                .put("startedAt", java.time.Instant.now().toString())
                .put("deviceBefore", device(context))
                .put(
                    "timingMethod",
                    "Normal rendering: CPU submission wall time, without glFinish; not GPU time or presented FPS",
                )
        recording = true
        worker.execute { runCatching { checkpoint() } }
    }

    @Synchronized
    fun stop() {
        if (recording) {
            recording = false
            worker.execute { runCatching { checkpoint() } }
        }
    }

    @Synchronized
    fun event(kind: String, details: JSONObject = JSONObject()) {
        if (!recording) return
        val key = if (kind == "action") "action:" + details.optString("action") else kind
        actionCounts[key] = (actionCounts[key] ?: 0L) + 1L
        if (events.size >= 2000) events.removeFirst()
        events.addLast(
            details
                .put("type", kind)
                .put("elapsedMs", (SystemClock.elapsedRealtimeNanos() - started) / 1e6)
        )
    }

    @Synchronized
    fun frame(
        ns: Long,
        elements: Int,
        group: String,
        snapshotWaitNs: Long = 0,
        snapshotHoldNs: Long = 0,
    ) {
        if (!recording) return
        frames++
        totalFrameNs += ns
        maxFrameNs = maxOf(maxFrameNs, ns)
        if (ns > 33_333_333) slowFrames++
        if (frames % 10L == 0L || ns > 33_333_333)
            event(
                "render",
                JSONObject()
                    .put("cpuSubmitMs", ns / 1e6)
                    .put("elements", elements)
                    .put("group", group)
                    .put("snapshotWaitMs", snapshotWaitNs / 1e6)
                    .put("snapshotHoldMs", snapshotHoldNs / 1e6),
            )
    }

    fun watch(window: Window): Window.OnFrameMetricsAvailableListener {
        val listener = Window.OnFrameMetricsAvailableListener { _, metrics, dropped ->
            if (recording && metrics.getMetric(FrameMetrics.FIRST_DRAW_FRAME) != 1L)
                uiFrame(
                    metrics.getMetric(FrameMetrics.TOTAL_DURATION),
                    metrics.getMetric(FrameMetrics.UNKNOWN_DELAY_DURATION),
                    if (Build.VERSION.SDK_INT >= 31) metrics.getMetric(FrameMetrics.DEADLINE)
                    else -1L,
                    dropped,
                )
        }
        window.addOnFrameMetricsAvailableListener(listener, Handler(frameThread.looper))
        return listener
    }

    @Synchronized
    private fun uiFrame(total: Long, delay: Long, deadline: Long, dropped: Int) {
        if (!recording || total < 0) return
        uiFrames++
        uiTotalNs += total
        uiMaxNs = maxOf(uiMaxNs, total)
        droppedMetricReports += dropped
        if (deadline > 0 && total > deadline) uiDeadlineMisses++
        if (uiFrames % 10L == 0L || total > 33_333_333L)
            event(
                "window_frame",
                JSONObject()
                    .put("totalMs", total / 1e6)
                    .put("uiThreadDelayMs", delay / 1e6)
                    .put("deadlineMs", if (deadline > 0) deadline / 1e6 else JSONObject.NULL),
            )
    }

    private fun checkpoint() {
        if (!initialized || started == 0L) return
        val begin = System.nanoTime()
        val epoch = synchronized(this) { started }
        val health = device(context)
        if (recording) event("health", JSONObject(health.toString()))
        val data =
            synchronized(this) {
                JSONObject(header.toString())
                    .put("state", if (recording) "recording" else "stopped")
                    .put("gpu", gpu)
                    .put(
                        "recorderOverhead",
                        JSONObject()
                            .put("periodSeconds", 5)
                            .put("completedCheckpoints", checkpoints)
                            .put("totalCheckpointMs", checkpointTotalNs / 1e6)
                            .put("maxCheckpointMs", checkpointMaxNs / 1e6)
                            .put("bytesWritten", checkpointBytes)
                            .put(
                                "scope",
                                "Prior completed checkpoints: health/PSS, event copy, compact JSON and AtomicFile fsync; worker wall time, not UI pause",
                            ),
                    )
                    .put("eventLimit", 2000)
                    .put("events", JSONArray(events.toList()))
                    .put("uiFrames", uiFrames)
                    .put("meanUiFrameMs", if (uiFrames > 0) uiTotalNs / uiFrames / 1e6 else 0.0)
                    .put("maxUiFrameMs", uiMaxNs / 1e6)
                    .put("uiDeadlineMisses", uiDeadlineMisses)
                    .put("droppedMetricReports", droppedMetricReports)
                    .put("actionCounts", JSONObject(actionCounts.toMap()))
                    .put("frames", frames)
                    .put("meanCpuSubmitMs", if (frames > 0) totalFrameNs / frames / 1e6 else 0.0)
                    .put("maxCpuSubmitMs", maxFrameNs / 1e6)
                    .put("cpuSubmissionsOver33ms", slowFrames)
            }
        data.put("deviceAfter", health)
        val bytes = write("recording.json", data)
        val elapsed = System.nanoTime() - begin
        synchronized(this) {
            if (started == epoch) {
                checkpoints++
                checkpointTotalNs += elapsed
                checkpointMaxNs = maxOf(checkpointMaxNs, elapsed)
                checkpointBytes += bytes
            }
        }
    }

    @Synchronized
    fun benchmark(data: JSONObject) {
        write("benchmark.json", data)
    }

    private fun write(name: String, data: JSONObject) =
        synchronized(ioLock) {
            val file = AtomicFile(File(folder(), name))
            val stream = file.startWrite()
            try {
                val bytes = data.toString().toByteArray()
                stream.write(bytes)
                file.finishWrite(stream)
                bytes.size
            } catch (error: Throwable) {
                file.failWrite(stream)
                throw error
            }
        }

    fun device(context: Context): JSONObject {
        val memory = ActivityManager.MemoryInfo()
        context.getSystemService(ActivityManager::class.java).getMemoryInfo(memory)
        val runtime = Runtime.getRuntime()
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val thermal =
            if (Build.VERSION.SDK_INT >= 29)
                context.getSystemService(PowerManager::class.java).currentThermalStatus
            else -1
        return JSONObject()
            .put("manufacturer", Build.MANUFACTURER)
            .put("model", Build.MODEL)
            .put("android", Build.VERSION.RELEASE)
            .put("gpuFillsRequested", FillAcceleration.enabled)
            .put("api", Build.VERSION.SDK_INT)
            .put("appVersion", BuildConfig.VERSION_NAME)
            .put("versionCode", BuildConfig.VERSION_CODE)
            .put("javaHeapUsedBytes", runtime.totalMemory() - runtime.freeMemory())
            .put("javaHeapLimitBytes", runtime.maxMemory())
            .put("processPssKb", Debug.getPss())
            .put("systemAvailableBytes", memory.availMem)
            .put("systemLowMemory", memory.lowMemory)
            .put("thermalStatus", thermal)
            .put(
                "batteryTemperatureTenthsC",
                battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1,
            )
    }

    fun summary(): JSONObject? = runCatching {
        JSONObject(File(folder(), "benchmark.json").readText())
    }
        .getOrNull()

    fun zip(): File {
        checkpoint()
        val shared = File(context.cacheDir, "shared").apply { mkdirs() }
        val file = File(shared, "kaleidopaint-performance-${System.currentTimeMillis()}.zip")
        ZipOutputStream(file.outputStream().buffered()).use { zip ->
            fun add(name: String, bytes: ByteArray) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(bytes)
                zip.closeEntry()
            }
            add("device.json", device(context).put("gpu", gpu).toString(2).toByteArray())
            for (name in listOf("benchmark.json", "recording.json")) File(folder(), name)
                .takeIf { it.exists() }
                ?.let { add(name, it.readBytes()) }
            add(
                "README.txt",
                "KaleidoPaint performance report. Benchmark uses fixed offscreen scenes and GPU completion fences. Drawing recording uses CPU submission times; it does not measure presented FPS. Contents: device/memory/thermal snapshots, aggregate render timings and a bounded event history.\n"
                    .toByteArray(),
            )
        }
        shared
            .listFiles { f ->
                f.name.startsWith("kaleidopaint-performance-") && f.extension == "zip"
            }
            ?.sortedByDescending { it.lastModified() }
            ?.drop(5)
            ?.forEach { it.delete() }
        return file
    }
}
