package com.clipboardsync.clipboard_sync

import android.app.Service
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.IBinder

class ClipboardListenerService : Service() {

    companion object {
        const val TAG = "CcvClipboard"
        private var instance: ClipboardListenerService? = null

        fun start(context: Context) {
            context.startService(Intent(context, ClipboardListenerService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ClipboardListenerService::class.java))
        }
    }

    private var lastText: String = ""
    private val clipboardListener = ClipboardManager.OnPrimaryClipChangedListener {
        onClipboardChanged()
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        MainActivity.logToFile("CLIPBOARD_SVC", "onCreate")

        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.addPrimaryClipChangedListener(clipboardListener)
        MainActivity.logToFile("CLIPBOARD", "Listener Registered")

        lastText = readClipboard(cm)
        MainActivity.logToFile("CLIPBOARD", "基线: oldClip=\"${lastText.take(80)}\"")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MainActivity.logToFile("CLIPBOARD_SVC", "onStartCommand")
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.removePrimaryClipChangedListener(clipboardListener)
        instance = null
        MainActivity.logToFile("CLIPBOARD_SVC", "onDestroy — Listener removed")
        super.onDestroy()
    }

    private fun onClipboardChanged() {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val newText = readClipboard(cm)
        val ts = java.text.SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.getDefault())
            .format(java.util.Date())

        MainActivity.logToFile("CLIPBOARD", "══════════════════")
        MainActivity.logToFile("CLIPBOARD", "Listener Triggered @ $ts")
        MainActivity.logToFile("CLIPBOARD", "oldClip=\"${lastText.take(80)}\"")
        MainActivity.logToFile("CLIPBOARD", "newClip=\"${newText.take(80)}\"")

        if (newText.isEmpty()) {
            MainActivity.logToFile("CLIPBOARD", "→ (EMPTY) 跳过")
            lastText = newText
            return
        }
        if (newText == lastText) {
            MainActivity.logToFile("CLIPBOARD", "→ 去重跳过")
            return
        }
        lastText = newText
        MainActivity.logToFile("CLIPBOARD", "→ 显示同步按钮")
        SyncButtonService.show(this)
    }

    private fun readClipboard(cm: ClipboardManager): String {
        return try {
            if (!cm.hasPrimaryClip()) return ""
            val clip = cm.primaryClip ?: return ""
            if (clip.itemCount == 0) return ""
            clip.getItemAt(0).coerceToText(this).toString()
        } catch (_: Exception) { "" }
    }
}
