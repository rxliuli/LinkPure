package com.rxliuli.linkpure

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.rxliuli.linkpure.clean.CleanNotifier
import com.rxliuli.linkpure.data.RuleStore
import com.rxliuli.linkpure.ui.LinkPureTheme
import com.rxliuli.linkpure.ui.RulesScreen

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        RuleStore.init(applicationContext)
        CleanNotifier.ensureChannel(this)

        // 通知是静默模式的反馈渠道（「本来就干净」和「不是 URL」这两种情况没有别的反馈），
        // 所以首次启动就问一次。拒绝也没关系——原位替换照常工作。
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }

        setContent {
            LinkPureTheme { RulesScreen() }
        }
    }
}
