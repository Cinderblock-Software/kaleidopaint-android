// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import java.util.Locale
import kotlinx.coroutines.*
import org.json.JSONObject

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PerformanceScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var job by remember { mutableStateOf<Job?>(null) }
    var running by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf("") }
    var result by remember { mutableStateOf(DiagnosticReports.summary()) }
    var error by remember { mutableStateOf(false) }
    val save =
        rememberLauncherForActivityResult(
            ActivityResultContracts.CreateDocument("application/zip")
        ) { uri ->
            if (uri != null)
                scope.launch {
                    runCatching {
                        withContext(Dispatchers.IO) {
                            val file = DiagnosticReports.zip()
                            context.contentResolver.openOutputStream(uri)?.use { output ->
                                file.inputStream().use { it.copyTo(output) }
                            } ?: throw IllegalStateException("No output stream")
                        }
                    }
                        .onFailure { error = true }
                }
        }
    fun cancel() {
        job?.cancel()
    }
    BackHandler { if (running) cancel() else onBack() }
    fun run(stress: Int) {
        try {
            DiagnosticReports.stop()
        } catch (failure: Exception) {
            error = true
            return
        }
        running = true
        error = false
        result = null
        job = scope.launch {
            val active = currentCoroutineContext()
            try {
                val report =
                    withContext(Dispatchers.IO) {
                        PerformanceBenchmark.run(
                            context.applicationContext,
                            stress,
                            progress = { label ->
                                scope.launch { progress = label }
                            },
                            cancelled = { !active.isActive },
                            onCheckpoint = { DiagnosticReports.benchmark(it) },
                        )
                    }
                withContext(Dispatchers.IO) { DiagnosticReports.benchmark(report) }
                result = report
            } catch (cancelled: CancellationException) {
                val cancelledReport =
                    (DiagnosticReports.summary() ?: JSONObject())
                        .put("state", "cancelled")
                        .put("device", DiagnosticReports.device(context))
                withContext(NonCancellable + Dispatchers.IO) {
                    DiagnosticReports.benchmark(cancelledReport)
                }
                result = cancelledReport
            } catch (failure: Exception) {
                error = true
                val failedReport =
                    (DiagnosticReports.summary() ?: JSONObject())
                        .put("state", "failed")
                        .put("exceptionType", failure.javaClass.simpleName)
                        .put("message", failure.message?.take(300))
                        .put("device", DiagnosticReports.device(context))
                withContext(Dispatchers.IO) { DiagnosticReports.benchmark(failedReport) }
                result = failedReport
            } finally {
                running = false
                progress = ""
            }
        }
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.performance)) },
                navigationIcon = {
                    TextButton(onClick = { if (running) cancel() else onBack() }) {
                        Text(stringResource(if (running) R.string.stop else R.string.back))
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.performance_explanation))
            Row(
                Modifier.fillMaxWidth()
                    .toggleable(
                        value = FillAcceleration.enabled,
                        enabled = !running,
                        role = Role.Switch,
                        onValueChange = { FillAcceleration.set(context, it) },
                    ),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.use_gpu_fills))
                Switch(
                    checked = FillAcceleration.enabled,
                    onCheckedChange = null,
                    enabled = !running,
                )
            }
            if (running) {
                LinearProgressIndicator(Modifier.fillMaxWidth())
                Text(progress)
            }
            Button(onClick = { run(0) }, enabled = !running) {
                Text(stringResource(R.string.run_benchmark))
            }
            Button(onClick = { run(60) }, enabled = !running) {
                Text(stringResource(R.string.run_stress))
            }
            if (running) TextButton(onClick = ::cancel) { Text(stringResource(R.string.stop)) }
            HorizontalDivider()
            Text(stringResource(R.string.record_explanation))
            Button(
                onClick = {
                    runCatching {
                        if (DiagnosticReports.recording) DiagnosticReports.stop()
                        else DiagnosticReports.start()
                    }
                        .onFailure { error = true }
                },
                enabled = !running,
            ) {
                Text(
                    stringResource(
                        if (DiagnosticReports.recording) R.string.stop_recording
                        else R.string.start_recording
                    )
                )
            }
            if (DiagnosticReports.recording) Text(stringResource(R.string.recording_active))
            result?.let { report ->
                Text(
                    stringResource(
                        when (report.optString("state")) {
                            "complete" -> R.string.benchmark_complete
                            "cancelled" -> R.string.benchmark_stopped
                            "interrupted" -> R.string.benchmark_interrupted
                            else -> R.string.benchmark_failed
                        }
                    )
                )
                val rows = report.optJSONArray("results")
                if (rows != null)
                    for (i in 0 until rows.length()) {
                        val row = rows.getJSONObject(i)
                        Text(
                            "${row.getString("scenario")}: ${String.format(Locale.ROOT,"%.1f",row.getDouble("medianMs"))} ms (median)"
                        )
                    }
            }
            Text(
                stringResource(R.string.report_contents),
                style = MaterialTheme.typography.bodySmall,
            )
            Button(
                enabled = !running,
                onClick = {
                    scope.launch {
                        try {
                            val file = withContext(Dispatchers.IO) { DiagnosticReports.zip() }
                            val uri =
                                FileProvider.getUriForFile(
                                    context,
                                    context.packageName + ".files",
                                    file,
                                )
                            context.startActivity(
                                Intent.createChooser(
                                    Intent(Intent.ACTION_SEND)
                                        .setType("application/zip")
                                        .putExtra(Intent.EXTRA_STREAM, uri)
                                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        .apply {
                                            clipData =
                                                android.content.ClipData.newRawUri(
                                                    "Performance report",
                                                    uri,
                                                )
                                        },
                                    null,
                                )
                            )
                        } catch (failure: Exception) {
                            error = true
                        }
                    }
                },
            ) {
                Text(stringResource(R.string.share_report))
            }
            TextButton(
                enabled = !running,
                onClick = { save.launch("kaleidopaint-performance.zip") },
            ) {
                Text(stringResource(R.string.save_report))
            }
            if (error)
                Text(
                    stringResource(R.string.file_operation_failed),
                    color = MaterialTheme.colorScheme.error,
                )
        }
    }
}
