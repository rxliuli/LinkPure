package com.rxliuli.linkpure

import android.app.Application
import com.rxliuli.linkpure.clean.CleanNotifier
import com.rxliuli.linkpure.data.RuleStore

class LinkPureApp : Application() {
    override fun onCreate() {
        super.onCreate()
        RuleStore.init(this)
        CleanNotifier.ensureChannel(this)
    }
}
