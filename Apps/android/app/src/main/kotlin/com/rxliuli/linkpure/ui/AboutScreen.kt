package com.rxliuli.linkpure.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

private const val GITHUB_URL = "https://github.com/rxliuli/LinkPure"
private const val WEBSITE_URL = "https://rxliuli.com/project/linkpure"

private const val DISCORD_URL = "https://discord.gg/gFhKUthc88"

private const val CLEARURLS_URL = "https://github.com/ClearURLs/Addon"
private const val LINKUMORI_URL = "https://github.com/Linkumori/Linkumori-Extension"

@Composable
fun AboutScreen() {
    val context = LocalContext.current

    val version = remember {
        runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull().orEmpty()
    }

    fun open(url: String) {
        runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("LinkPure", style = MaterialTheme.typography.headlineSmall)
        Text(
            if (version.isBlank()) "A link cleaner for Android" else "Version $version",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(Modifier.height(4.dp))

        LinkButton("GitHub", GITHUB_URL, ::open)
        LinkButton("Discord", DISCORD_URL, ::open)
        LinkButton("Website", WEBSITE_URL, ::open)

        HorizontalDivider(Modifier.padding(vertical = 4.dp))

        Text("Built-in rules", style = MaterialTheme.typography.titleSmall)
        Text(
            "The rule library is assembled from ClearURLs and Linkumori, and is distributed " +
                "under the LGPL-3.0. LinkPure itself is GPL-3.0.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        LinkButton("ClearURLs", CLEARURLS_URL, ::open)
        LinkButton("Linkumori", LINKUMORI_URL, ::open)
    }
}

@Composable
private fun LinkButton(title: String, url: String, onOpen: (String) -> Unit) {
    OutlinedButton(
        onClick = { onOpen(url) },
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(
                url.removePrefix("https://"),
                style = MaterialTheme.typography.bodySmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
