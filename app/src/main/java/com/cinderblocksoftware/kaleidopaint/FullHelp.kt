// Adapted from KaleidoPaintHelp.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

/** The original illustrated editor help, plus Android-specific controls. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DrawingHelp(onDismiss: () -> Unit) {
    val context = LocalContext.current
    Dialog(
        onDismissRequest = onDismiss,
        properties =
            DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = true),
    ) {
        val view = androidx.compose.ui.platform.LocalView.current
        androidx.compose.runtime.SideEffect {
            (view.parent as? androidx.compose.ui.window.DialogWindowProvider)?.window?.let { window
                ->
                androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
                    .apply {
                        isAppearanceLightStatusBars = true
                        isAppearanceLightNavigationBars = true
                    }
            }
        }
        Surface(Modifier.fillMaxSize()) {
            Scaffold(
                topBar = {
                    TopAppBar(
                        title = { Text(stringResource(R.string.help)) },
                        navigationIcon = {
                            TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) }
                        },
                    )
                }
            ) { padding ->
                Column(
                    Modifier.fillMaxSize()
                        .padding(padding)
                        .verticalScroll(rememberScrollState())
                        .padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Text(
                        stringResource(R.string.help_android),
                        style = MaterialTheme.typography.titleLarge,
                    )
                    Text(emphasis(stringResource(R.string.help_one_finger)))
                    Text(emphasis(stringResource(R.string.help_two_fingers)))
                    Text(
                        stringResource(
                            R.string.help_body,
                            stringResource(R.string.fill),
                            stringResource(R.string.edit_mode),
                            stringResource(R.string.drawing_name_default),
                        )
                    )
                    Text(emphasis(stringResource(R.string.help_double_tap)))
                    Text(
                        stringResource(R.string.help_editor_title),
                        style = MaterialTheme.typography.titleLarge,
                    )
                    Text(
                        stringResource(R.string.help_illustrations),
                        style = MaterialTheme.typography.bodySmall,
                    )
                    for ((text, image) in
                        listOf(
                            R.string.help_control_points to R.drawable.help_control_points,
                            R.string.help_control_drag to R.drawable.help_control_drag,
                            R.string.help_control_tap to R.drawable.help_control_tap,
                        )) {
                        Text(emphasis(stringResource(text)))
                        Image(
                            painterResource(image),
                            contentDescription = stringResource(text).replace("*", ""),
                            contentScale = ContentScale.Fit,
                            modifier = Modifier.fillMaxWidth().heightIn(max = 360.dp),
                        )
                    }
                    Text(emphasis(stringResource(R.string.help_no_arc_taps)))
                    Text(emphasis(stringResource(R.string.help_performance)))
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        for ((caption, subcaption, image) in
                            listOf(
                                Triple(
                                    R.string.help_bad,
                                    R.string.help_bad_caption,
                                    R.drawable.help_fill_bad,
                                ),
                                Triple(
                                    R.string.help_good,
                                    R.string.help_good_caption,
                                    R.drawable.help_fill_good,
                                ),
                            )) {
                            Column(
                                Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    stringResource(caption),
                                    style = MaterialTheme.typography.titleMedium,
                                )
                                Text(stringResource(subcaption))
                                Image(
                                    painterResource(image),
                                    contentDescription = stringResource(subcaption),
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                        }
                    }
                    Text(
                        stringResource(R.string.export_tile),
                        style = MaterialTheme.typography.titleLarge,
                    )
                    Text(stringResource(R.string.help_tile))
                    Text(
                        emphasis(
                            stringResource(R.string.help_gallery_text)
                                .replace(Regex("\\[([^]]+)\\]\\(([^)]+)\\)"), "$1")
                        )
                    )
                    for ((label, url) in
                        listOf(
                            R.string.help_tutorials to R.string.help_tutorial_url,
                            R.string.help_gallery to R.string.help_gallery_url,
                        )) {
                        TextButton(
                            onClick = {
                                context.startActivity(
                                    Intent(Intent.ACTION_VIEW, Uri.parse(context.getString(url)))
                                )
                            }
                        ) {
                            Text(stringResource(label))
                        }
                    }
                    Text(
                        stringResource(R.string.about_copyright),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
    }
}

private fun emphasis(text: String): AnnotatedString = buildAnnotatedString {
    val pattern = Regex("\\*\\*(.+?)\\*\\*|\\*(.+?)\\*", RegexOption.DOT_MATCHES_ALL)
    var last = 0
    for (match in pattern.findAll(text)) {
        append(text.substring(last, match.range.first))
        val bold = match.groups[1] != null
        pushStyle(
            if (bold) SpanStyle(fontWeight = FontWeight.Bold)
            else SpanStyle(fontStyle = FontStyle.Italic)
        )
        append(match.groups[if (bold) 1 else 2]!!.value)
        pop()
        last = match.range.last + 1
    }
    append(text.substring(last))
}
