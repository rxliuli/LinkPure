package com.rxliuli.linkpure.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * 「怎么用」单独成一页。
 *
 * 第一版把它铺在主界面顶部当一张卡，结果它占了四成屏幕、把真正的列表挤到折叠线以下——
 * 说明文字不该跟内容抢地方。入口放在溢出菜单里，需要的时候再看。
 */
@Composable
fun GuideScreen() {
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Section(
            title = "Clean a link",
            body = "Select it anywhere — browser address bar, chat, notes, mail — then open the " +
                "selection menu (⋮) and pick Process text → Clean URL Text.",
        )
        Section(
            title = "What happens",
            body = "The selection is replaced in place. No screen opens, and your clipboard is " +
                "left alone unless you tap Copy on the notification.",
        )
        Section(
            title = "Already clean, or not a link?",
            body = "The notification says so. That is the only feedback in those cases, which is " +
                "why it is worth allowing notifications.",
        )

        HorizontalDivider()

        Section(
            title = "Why there is no automatic mode",
            body = "On macOS LinkPure can watch the clipboard and rewrite links by itself. " +
                "Android does not allow that: since Android 10 an app can only read the " +
                "clipboard while it is in the foreground or is the current keyboard, and it is " +
                "not even told when the clipboard changes.",
        )
        Section(
            title = "Why this entry point",
            body = "Process text hands the selected text to the app directly through the system " +
                "menu, so nothing has to touch the clipboard. That makes it work everywhere, " +
                "with no setup and no special permissions.",
        )
    }
}

@Composable
private fun Section(title: String, body: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall)
        Text(
            body,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
