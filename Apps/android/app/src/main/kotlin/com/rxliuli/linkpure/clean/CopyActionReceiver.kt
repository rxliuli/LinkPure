package com.rxliuli.linkpure.clean

import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import com.rxliuli.linkpure.R

/** 通知里「复制」按钮的落地：把清洗后的 URL 写进剪贴板。 */
class CopyActionReceiver : BroadcastReceiver() {

    companion object {
        const val EXTRA_TEXT = "text"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val text = intent.getStringExtra(EXTRA_TEXT) ?: return
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("LinkPure", text))
        CleanNotifier.cancel(context)
        Toast.makeText(context, context.getString(R.string.notif_copied), Toast.LENGTH_SHORT).show()
    }
}
