package com.rxliuli.linkpure

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import com.rxliuli.linkpure.clean.CleanNotifier
import com.rxliuli.linkpure.clean.Cleaner
import kotlinx.coroutines.launch

/**
 * ★ 唯一的入口：`ACTION_PROCESS_TEXT`。
 *
 * 这是探针实测之后定下来的形态。Android 上做不到 macOS 那种「零操作自动改写」——
 * 系统只让**有焦点**或**默认输入法**读剪贴板，而且连 `clipboardChanged` 事件都不投递给
 * 后台 app（连「知道用户复制了」都做不到）。所以不去碰剪贴板，改用这个入口：
 * 内容随 intent 进来，**完全绕开全部限制**，而且**零配置**（不用像 iOS 那样教用户配快捷指令）。
 *
 * 全程不 `setContentView`：用户点一下，选区里的文字当场变了，那就是全部反馈。
 */
class ProcessTextActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 不 setContentView —— 静默模式下不该有任何界面

        val received = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        val readOnly = intent.getBooleanExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, false)

        if (received.isNullOrBlank()) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }

        lifecycleScope.launch {
            val outcome = Cleaner.clean(received)

            if (readOnly && outcome.changed) {
                // 只读字段：宿主会忽略我们返回的值（文档明确说了），
                // 那就把结果放进剪贴板，至少别让用户白点一下。
                copy(outcome.output)
                setResult(RESULT_OK, Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, received))
                CleanNotifier.show(this@ProcessTextActivity, outcome, copiedInstead = true)
            } else {
                setResult(RESULT_OK, Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, outcome.output))
                CleanNotifier.show(this@ProcessTextActivity, outcome)
            }
            finish()
        }
    }

    private fun copy(text: String) {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("LinkPure", text))
    }
}
