// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp

/**
 * Credits, licence and source: credit Jeff Weeks, link the original, state the GPL, and link this
 * port's source.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(onBack: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.about)) },
                navigationIcon = {
                    TextButton(onClick = onBack) {
                        Text(stringResource(R.string.back))
                    }
                },
            )
        }
    ) { innerPadding ->
        Column(
            modifier =
                Modifier.fillMaxSize()
                    .padding(innerPadding)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(
                modifier = Modifier.align(Alignment.CenterHorizontally),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Image(
                    painter = painterResource(R.drawable.kaleidopaint_icon),
                    contentDescription = null,
                    //	The artwork has opaque white corners;  round them off.
                    modifier = Modifier.size(96.dp).clip(RoundedCornerShape(percent = 22)),
                )
                Text(
                    text = stringResource(R.string.app_full_name),
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text(
                    text = stringResource(R.string.version_format, BuildConfig.VERSION_NAME),
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    text = stringResource(R.string.about_credit),
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                )
            }

            Heading(stringResource(R.string.about_original_heading))
            Text(stringResource(R.string.about_original_body))
            Link(stringResource(R.string.about_original_url))

            Heading(stringResource(R.string.about_licence_heading))
            Text(stringResource(R.string.about_copyright))
            Text(stringResource(R.string.about_licence_body))
            Link(stringResource(R.string.about_licence_url))

            Heading(stringResource(R.string.donation_heading))
            Text(stringResource(R.string.donation_body))
            Link(stringResource(R.string.donation_url))

            Heading(stringResource(R.string.about_source_heading))
            Text(stringResource(R.string.about_source_body))
            Link(stringResource(R.string.about_source_url))

            Heading(stringResource(R.string.about_privacy_heading))
            Link(stringResource(R.string.about_privacy_url))
        }
    }
}

@Composable
private fun Heading(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.padding(top = 8.dp),
    )
}

/** A link that opens in the browser, never in a WebView. */
@Composable
private fun Link(url: String) {
    val context = LocalContext.current
    Text(
        text = url,
        color = MaterialTheme.colorScheme.primary,
        textDecoration = TextDecoration.Underline,
        modifier =
            Modifier.clickable {
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            },
    )
}
